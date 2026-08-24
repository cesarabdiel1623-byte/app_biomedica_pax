import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

type JsonRecord = Record<string, unknown>;

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new Error(`missing_environment_variable: ${name}`);
  }
  return value;
}

function getString(source: JsonRecord | null | undefined, key: string): string | null {
  if (!source) return null;
  const value = source[key];
  if (typeof value === "string" && value.trim() !== "") return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function getNumber(source: JsonRecord | null | undefined, key: string): number | null {
  if (!source) return null;
  const value = source[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function decodeBase64UrlJson(input: string): JsonRecord | null {
  try {
    let base64 = input.replace(/-/g, "+").replace(/_/g, "/");
    const pad = base64.length % 4;
    if (pad > 0) base64 += "=".repeat(4 - pad);
    const decoded = atob(base64);
    const parsed = JSON.parse(decoded);
    return isRecord(parsed) ? parsed : null;
  } catch (_) {
    return null;
  }
}

function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization")?.trim() ?? "";
  if (!authHeader.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length).trim();
  return token || null;
}

function getJwtRoleFromBearerToken(token: string): string | null {
  const parts = token.split(".");
  if (parts.length < 2) return null;
  const payload = decodeBase64UrlJson(parts[1]);
  return getString(payload, "role");
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: JSON_HEADERS });
  }
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  try {
    const bearerToken = getBearerToken(request);
    if (!bearerToken) {
      return jsonResponse({ ok: false, error: "unauthorized" }, 401);
    }

    const jwtRole = getJwtRoleFromBearerToken(bearerToken);
    if (jwtRole !== "service_role") {
      return jsonResponse({ ok: false, error: "forbidden" }, 403);
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await request.json().catch(() => ({}));
    const batchSize = Math.min(Math.max(getNumber(isRecord(body) ? body : {}, "batch_size") ?? 5, 1), 20);

    let processedCount = 0;
    let completedCount = 0;
    let failedCount = 0;
    const results: JsonRecord[] = [];

    const fulfillmentFunctionUrl = `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/process-paid-order-fulfillment`;

    for (let i = 0; i < batchSize; i++) {
      // Atomic claim using FOR UPDATE SKIP LOCKED
      const { data: claimData, error: claimError } = await adminClient.rpc("claim_next_fulfillment_job");
      if (claimError || !isRecord(claimData)) {
        break; // No more jobs to process
      }

      const jobId = getString(claimData, "job_id");
      const orderId = getString(claimData, "order_id");
      const attempts = getNumber(claimData, "attempts") ?? 1;

      if (!jobId || !orderId) {
        break;
      }

      processedCount++;

      try {
        const authToken = bearerToken || serviceRoleKey;
        const response = await fetch(fulfillmentFunctionUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${authToken}`,
            "apikey": authToken,
          },
          body: JSON.stringify({ order_id: orderId }),
        });

        const rawText = await response.text();
        let fulfillmentResult: JsonRecord = {};
        try {
          fulfillmentResult = rawText.trim() ? JSON.parse(rawText) : {};
        } catch (_) {
          fulfillmentResult = {};
        }

        if (response.ok && isRecord(fulfillmentResult) && fulfillmentResult.ok === true) {
          await adminClient.rpc("complete_fulfillment_job", { p_job_id: jobId });
          completedCount++;
          results.push({ job_id: jobId, order_id: orderId, status: "completed" });
        } else {
          const errorMsg = getString(isRecord(fulfillmentResult) ? fulfillmentResult : {}, "error") ?? "fulfillment_execution_failed";
          const backoffMinutes = Math.min(Math.pow(2, attempts), 60); // Exponential backoff: 2, 4, 8, 16...
          await adminClient.rpc("fail_fulfillment_job", {
            p_job_id: jobId,
            p_error: errorMsg,
            p_backoff_minutes: backoffMinutes,
          });
          failedCount++;
          results.push({ job_id: jobId, order_id: orderId, status: "failed", error: errorMsg });
        }
      } catch (execError) {
        const errorMsg = execError instanceof Error ? execError.message : "network_or_system_error";
        const backoffMinutes = Math.min(Math.pow(2, attempts), 60);
        await adminClient.rpc("fail_fulfillment_job", {
          p_job_id: jobId,
          p_error: errorMsg,
          p_backoff_minutes: backoffMinutes,
        });
        failedCount++;
        results.push({ job_id: jobId, order_id: orderId, status: "failed", error: errorMsg });
      }
    }

    return jsonResponse({
      ok: true,
      processed_count: processedCount,
      completed_count: completedCount,
      failed_count: failedCount,
      jobs: results,
    });
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: "internal_server_error",
      message: error instanceof Error ? error.message : "unknown_error",
    }, 500);
  }
});
