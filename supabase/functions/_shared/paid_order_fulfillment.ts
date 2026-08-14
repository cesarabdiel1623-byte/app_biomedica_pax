import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

type JsonRecord = Record<string, unknown>;

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getString(source: JsonRecord | null | undefined, key: string): string | null {
  if (!source) return null;
  const value = source[key];
  if (typeof value === "string" && value.trim() !== "") return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

async function invokeLocalFulfillment(orderId: string): Promise<JsonRecord> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !serviceRoleKey) {
    return { ok: false, error: "missing_supabase_configuration" };
  }

  const functionUrl = `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/process-paid-order-fulfillment`;

  const response = await fetch(functionUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
    body: JSON.stringify({ order_id: orderId }),
  });

  const rawText = await response.text();
  let data: unknown = {};
  try {
    data = rawText.trim() ? JSON.parse(rawText) : {};
  } catch (_) {
    data = { ok: false, error: "invalid_fulfillment_response" };
  }

  return {
    ok: response.ok,
    status: response.status,
    data: isRecord(data) ? data : {},
  };
}

export async function triggerPaidOrderFulfillment(
  orderId: string | null | undefined,
): Promise<JsonRecord> {
  if (!orderId) return { ok: false, error: "missing_order_id" };

  const mode = Deno.env.get("FULFILLMENT_TRIGGER_MODE")?.trim().toLowerCase() ||
    "edge_function";

  if (mode === "edge_function") {
    try {
      return await invokeLocalFulfillment(orderId);
    } catch (error) {
      return {
        ok: false,
        error: "fulfillment_invocation_failed",
        message: error instanceof Error ? error.message : "unknown_error",
      };
    }
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !serviceRoleKey) {
    return { ok: false, error: "missing_supabase_configuration" };
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await adminClient.rpc("apply_paid_order_post_payment", {
    p_order_id: orderId,
  });

  if (error) {
    return { ok: false, error: "post_payment_rpc_failed", message: error.message };
  }

  return {
    ok: isRecord(data) ? data.success === true : true,
    status: 200,
    data: isRecord(data) ? data : {},
    order_id: getString(isRecord(data) ? data : {}, "order_id") ?? orderId,
  };
}
