// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

type WebhookBody = {
  type?: string;
  topic?: string;
  action?: string;
  live_mode?: boolean;
  data?: {
    id?: string | number;
  };
};

type ParsedSignature = {
  ts: string;
  v1: string;
};

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-signature, x-request-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function getString(source: Record<string, unknown> | null | undefined, key: string): string | null {
  if (!source) return null;
  const value = source[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function getReconciledPaymentStatus(source: unknown): string | null {
  if (!source || typeof source !== "object" || Array.isArray(source)) return null;
  const result = source as Record<string, unknown>;
  return getString(result, "payment_status") ?? getString(result, "status");
}

function isUuidLike(value: string): boolean {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(value);
}

function parseSignature(value: string): ParsedSignature | null {
  const values = new Map<string, string>();
  for (const part of value.split(",")) {
    const separatorIndex = part.indexOf("=");
    if (separatorIndex <= 0) continue;
    const key = part.slice(0, separatorIndex).trim();
    const itemValue = part.slice(separatorIndex + 1).trim();
    values.set(key, itemValue);
  }
  const ts = values.get("ts");
  const v1 = values.get("v1")?.toLowerCase();

  if (!ts || !/^\d+$/.test(ts)) return null;
  if (!v1 || !/^[a-f0-9]{64}$/.test(v1)) return null;

  return { ts, v1 };
}

function hexToBytes(value: string): Uint8Array {
  const output = new Uint8Array(value.length / 2);
  for (let index = 0; index < output.length; index++) {
    output[index] = Number.parseInt(
      value.slice(index * 2, index * 2 + 2),
      16,
    );
  }
  return output;
}

function timingSafeEqual(first: Uint8Array, second: Uint8Array): boolean {
  if (first.length !== second.length) return false;
  let difference = 0;
  for (let index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference === 0;
}

function buildManifest(
  timestamp: string,
  requestId: string | null,
  dataId: string | null,
): string {
  let manifest = "";
  if (dataId) {
    manifest += `id:${dataId.toLowerCase()};`;
  }
  if (requestId) {
    manifest += `request-id:${requestId};`;
  }
  manifest += `ts:${timestamp};`;
  return manifest;
}

async function calculateSignature(
  secret: string,
  manifest: string,
): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  return new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(manifest)),
  );
}

async function validateSignature(
  headerValue: string,
  requestId: string | null,
  queryDataId: string | null,
  bodyDataId: string | null,
  secret: string,
): Promise<{
  valid: boolean;
  dataIdUsed: string | null;
  source: "query" | "body" | "omitted" | "none";
}> {
  const parsed = parseSignature(headerValue);
  if (!parsed) {
    return { valid: false, dataIdUsed: null, source: "none" };
  }

  const candidates: Array<{
    dataId: string | null;
    source: "query" | "body" | "omitted";
  }> = [];

  if (queryDataId) {
    candidates.push({ dataId: queryDataId, source: "query" });
  } else {
    if (bodyDataId) {
      candidates.push({ dataId: bodyDataId, source: "body" });
    }
    candidates.push({ dataId: null, source: "omitted" });
  }

  const receivedSignature = hexToBytes(parsed.v1);

  for (const candidate of candidates) {
    const manifest = buildManifest(parsed.ts, requestId, candidate.dataId);
    const calculatedSignature = await calculateSignature(secret, manifest);

    if (timingSafeEqual(calculatedSignature, receivedSignature)) {
      return {
        valid: true,
        dataIdUsed: candidate.dataId,
        source: candidate.source,
      };
    }
  }

  return { valid: false, dataIdUsed: null, source: "none" };
}

function parseJsonSafely(rawBody: string): WebhookBody | null {
  if (!rawBody.trim()) return {};
  try {
    return JSON.parse(rawBody) as WebhookBody;
  } catch {
    return null;
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: JSON_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const traceId = crypto.randomUUID();

  try {
    const webhookSecret = requiredEnv("MERCADO_PAGO_WEBHOOK_SECRET");
    const accessToken = requiredEnv("MERCADO_PAGO_ACCESS_TOKEN");
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

    const expectedCollectorId =
      Deno.env.get("MERCADO_PAGO_COLLECTOR_ID")?.trim() || null;
    const configuredEnvironment =
      Deno.env.get("MERCADO_PAGO_ENV")?.trim().toLowerCase() || null;

    if (
      configuredEnvironment &&
      !["test", "production"].includes(configuredEnvironment)
    ) {
      console.error("Invalid MERCADO_PAGO_ENV configuration", {
        trace_id: traceId,
        configured_environment: configuredEnvironment,
      });
      return jsonResponse({ error: "server_configuration_error" }, 500);
    }

    const rawBody = await request.text();
    const body = parseJsonSafely(rawBody);

    if (body === null) {
      return jsonResponse({ error: "invalid_json" }, 400);
    }

    const url = new URL(request.url);
    const signatureHeader = request.headers.get("x-signature");
    const mercadoPagoRequestId = request.headers.get("x-request-id");

    const rawQueryDataId =
      url.searchParams.get("data.id")?.trim() ||
      url.searchParams.get("data_id")?.trim() ||
      url.searchParams.get("id")?.trim() ||
      null;
    const queryDataId = rawQueryDataId ? rawQueryDataId.toLowerCase() : null;

    const rawBodyDataId =
      body.data?.id !== undefined && body.data?.id !== null
        ? String(body.data.id).trim()
        : null;
    const bodyDataId = rawBodyDataId ? rawBodyDataId.toLowerCase() : null;

    if (!signatureHeader) {
      console.warn("Missing Mercado Pago webhook signature", {
        trace_id: traceId,
        has_request_id: Boolean(mercadoPagoRequestId),
        has_query_data_id: Boolean(queryDataId),
      });
      return jsonResponse({ error: "invalid_signature" }, 401);
    }

    const signatureResult = await validateSignature(
      signatureHeader,
      mercadoPagoRequestId,
      queryDataId,
      bodyDataId,
      webhookSecret,
    );

    if (!signatureResult.valid) {
      console.warn("Invalid Mercado Pago webhook signature", {
        trace_id: traceId,
        has_request_id: Boolean(mercadoPagoRequestId),
        has_query_data_id: Boolean(queryDataId),
      });
      return jsonResponse({ error: "invalid_signature" }, 401);
    }

    const notificationType =
      url.searchParams.get("type") ??
      url.searchParams.get("topic") ??
      body.type ??
      body.topic ??
      null;

    if (notificationType !== "payment") {
      console.info("Mercado Pago event ignored", {
        trace_id: traceId,
        notification_type: notificationType,
      });
      return jsonResponse({ received: true, ignored: true });
    }

    const paymentId = queryDataId ?? bodyDataId ?? signatureResult.dataIdUsed;
    if (!paymentId) {
      return jsonResponse({ error: "missing_payment_id" }, 400);
    }

    if (queryDataId && bodyDataId && queryDataId !== bodyDataId) {
      console.warn("Mercado Pago payment id mismatch", {
        trace_id: traceId,
        query_payment_id: queryDataId,
        body_payment_id: bodyDataId,
      });
      return jsonResponse({ error: "payment_id_mismatch" }, 400);
    }

    // Consulta directa a la API de Mercado Pago (Fuente de Verdad)
    const mercadoPagoResponse = await fetch(
      `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: "application/json",
        },
      },
    );

    let payment: Record<string, any> = {};
    try {
      payment = await mercadoPagoResponse.json();
    } catch {
      payment = {};
    }

    if (!mercadoPagoResponse.ok) {
      console.error("Payment lookup failed", {
        trace_id: traceId,
        payment_id: paymentId,
        provider_status: mercadoPagoResponse.status,
      });
      return jsonResponse({ error: "payment_lookup_failed" }, 502);
    }

    if (String(payment.id ?? "").toLowerCase() !== paymentId) {
      console.error("Mercado Pago payment response mismatch", {
        trace_id: traceId,
        requested_payment_id: paymentId,
        received_payment_id: payment.id ?? null,
      });
      return jsonResponse({ error: "payment_response_mismatch" }, 502);
    }

    if (
      expectedCollectorId &&
      String(payment.collector_id ?? "") !== expectedCollectorId
    ) {
      console.error("Unexpected Mercado Pago collector", {
        trace_id: traceId,
        payment_id: paymentId,
      });
      return jsonResponse({ error: "collector_mismatch" }, 409);
    }

    if (
      typeof payment.external_reference !== "string" ||
      !payment.external_reference.trim()
    ) {
      console.error("Mercado Pago payment without external reference", {
        trace_id: traceId,
        payment_id: paymentId,
      });
      return jsonResponse({ error: "missing_external_reference" }, 409);
    }

    const paymentEnvironment = payment.live_mode === true ? "production" : "test";

    if (configuredEnvironment && configuredEnvironment !== paymentEnvironment) {
      console.warn("Mercado Pago environment configuration mismatch", {
        trace_id: traceId,
        payment_id: paymentId,
        configured_environment: configuredEnvironment,
        payment_environment: paymentEnvironment,
      });
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const { data: reconciliationResult, error: reconciliationError } =
      await supabaseAdmin.rpc("reconcile_mercado_pago_payment", {
        p_payment_id: String(payment.id),
        p_external_reference: payment.external_reference.trim(),
        p_status: payment.status ?? null,
        p_status_detail: payment.status_detail ?? null,
        p_amount: payment.transaction_amount ?? null,
        p_currency_id: payment.currency_id ?? null,
        p_payment_method_id: payment.payment_method_id ?? null,
        p_payment_type_id: payment.payment_type_id ?? null,
        p_installments: payment.installments ?? null,
        p_live_mode: payment.live_mode === true,
        p_date_approved: payment.date_approved ?? null,
        p_provider_created_at: payment.date_created ?? null,
        p_provider_updated_at: payment.date_last_updated ?? null,
        p_raw_metadata: {
          collector_id: payment.collector_id ?? null,
          operation_type: payment.operation_type ?? null,
          action: body.action ?? null,
          signature_data_id_source: signatureResult.source,
        },
      });

    if (reconciliationError) {
      console.error("Payment reconciliation failed", {
        trace_id: traceId,
        payment_id: paymentId,
        rpc_message: reconciliationError.message ?? null,
      });
      return jsonResponse({ error: "payment_reconciliation_failed" }, 409);
    }

    console.log("Mercado Pago payment reconciled", {
      trace_id: traceId,
      payment_id: paymentId,
      result: reconciliationResult,
    });

    return jsonResponse({ received: true, reconciled: true });
  } catch (error) {
    console.error("Unexpected webhook error", {
      trace_id: traceId,
      message: error instanceof Error ? error.message : "unknown_error",
    });

    return jsonResponse({ error: "internal_server_error" }, 500);
  }
});
