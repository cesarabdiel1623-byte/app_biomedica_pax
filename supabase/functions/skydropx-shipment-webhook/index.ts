import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

type JsonRecord = Record<string, unknown>;

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

function jsonResponse(body: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

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

function getNestedRecord(source: JsonRecord, key: string): JsonRecord | null {
  const value = source[key];
  return isRecord(value) ? value : null;
}

function getNestedString(source: JsonRecord, keys: string[]): string | null {
  let current: unknown = source;
  for (const key of keys) {
    if (!isRecord(current)) return null;
    current = current[key];
  }
  if (typeof current === "string" && current.trim() !== "") return current.trim();
  if (typeof current === "number" && Number.isFinite(current)) return String(current);
  return null;
}

function getJsonApiResource(body: JsonRecord): JsonRecord | null {
  const data = getNestedRecord(body, "data");
  if (!data) return null;

  const nestedData = getNestedRecord(data, "data");
  return nestedData ?? data;
}

export function parseSkydropxAuthorization(authorization: string | null): string | null {
  if (!authorization?.startsWith("HMAC ")) return null;
  const signature = authorization.slice("HMAC ".length);
  if (!/^[a-f0-9]{128}$/.test(signature)) return null;
  return signature;
}

function hexToBytes(value: string): Uint8Array | null {
  const normalized = value.trim();
  if (!/^[a-f0-9]{128}$/.test(normalized)) return null;
  const output = new Uint8Array(normalized.length / 2);
  for (let index = 0; index < output.length; index++) {
    output[index] = Number.parseInt(normalized.slice(index * 2, index * 2 + 2), 16);
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

export function bytesToLowercaseHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function calculateHmacSha512Hex(secret: string, rawBody: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody)));
  return bytesToLowercaseHex(signature);
}

export async function verifySkydropxSignature(
  rawBody: string,
  authorization: string | null,
  secret: string | null | undefined,
): Promise<boolean> {
  if (!secret || !authorization) return false;

  const receivedSignature = parseSkydropxAuthorization(authorization);
  if (!receivedSignature) return false;

  const calculatedSignature = await calculateHmacSha512Hex(secret, rawBody);
  const received = hexToBytes(receivedSignature);
  const expected = hexToBytes(calculatedSignature);
  if (!received) return false;
  if (!expected) return false;

  return timingSafeEqual(expected, received);
}

export function extractPayloadFields(body: JsonRecord): {
  packageId: string | null;
  shipmentId: string | null;
  trackingNumber: string | null;
  trackingUrl: string | null;
  labelUrl: string | null;
  providerStatus: string | null;
  description: string | null;
  location: string | null;
  eventAt: string | null;
} {
  const resource = getJsonApiResource(body);
  const attributes = resource ? getNestedRecord(resource, "attributes") : null;

  return {
    packageId: resource ? getString(resource, "id") : null,
    shipmentId: resource
      ? getNestedString(resource, ["relationships", "shipment", "data", "id"])
      : null,
    trackingNumber: getString(attributes, "tracking_number"),
    trackingUrl: getString(attributes, "tracking_url_provider"),
    labelUrl: getString(attributes, "label_url"),
    providerStatus: getString(attributes, "status"),
    description: getString(attributes, "event_description"),
    location: getString(attributes, "location"),
    eventAt: getString(attributes, "event_at") ??
      getString(attributes, "occurred_at") ??
      getString(attributes, "created_at"),
  };
}

export async function handleRequest(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  const rawBody = await request.text();
  const webhookSecret = Deno.env.get("SKYDROPX_SANDBOX_WEBHOOK_SECRET")?.trim();
  const signatureOk = await verifySkydropxSignature(
    rawBody,
    request.headers.get("Authorization"),
    webhookSecret,
  );
  if (!signatureOk) {
    return jsonResponse({ ok: false, error: "invalid_signature" }, 401);
  }

  let body: unknown;
  try {
    body = rawBody.trim() ? JSON.parse(rawBody) : {};
  } catch (_) {
    return jsonResponse({ ok: false, error: "invalid_json" }, 400);
  }

  if (!isRecord(body)) {
    return jsonResponse({ ok: false, error: "invalid_payload" }, 400);
  }

  const fields = extractPayloadFields(body);
  if (!fields.providerStatus) {
    return jsonResponse({ ok: true, ignored: true, reason: "missing_status" });
  }

  if (!fields.shipmentId) {
    return jsonResponse({
      ok: true,
      ignored: true,
      reason: "missing_shipment_id",
      provider_status: fields.providerStatus.toLowerCase(),
    });
  }

  const normalizedStatus = fields.providerStatus.toLowerCase();
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ ok: false, error: "missing_supabase_configuration" }, 500);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await adminClient.rpc("record_skydropx_shipment_event", {
    p_skydropx_shipment_id: fields.shipmentId,
    p_tracking_number: fields.trackingNumber,
    p_tracking_url: fields.trackingUrl,
    p_label_url: fields.labelUrl,
    p_provider_status: normalizedStatus,
    p_description: fields.description,
    p_location: fields.location,
    p_event_at: fields.eventAt,
    p_raw_payload: body,
  });

  if (error) {
    return jsonResponse({ ok: false, error: "shipment_event_store_failed" }, 500);
  }

  return jsonResponse({
    ok: true,
    result: isRecord(data) ? data : {},
  });
}

if (import.meta.main) {
  Deno.serve(handleRequest);
}
