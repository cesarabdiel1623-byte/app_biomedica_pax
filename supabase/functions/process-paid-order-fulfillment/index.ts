import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  REQUIRED_ORIGIN_FIELDS,
  resolveShippingOrigin,
  resolveSkydropxEnvironment,
} from "../_shared/skydropx_shipping_origin.ts";

type JsonRecord = Record<string, unknown>;
type SupabaseAdminClient = SupabaseClient;

type ShippingRate = {
  rate_id: string;
  carrier: string;
  service: string;
  days: number | null;
  total: number;
};

type ShippingUnit = {
  parcel: {
    length: number;
    width: number;
    height: number;
    weight: number;
  };
  packageTypeCode: string;
  consignmentNote: string;
};

type RefreshedRateSelection = {
  quotation_id: string;
  rate: ShippingRate;
  selection_reason: "same_carrier_service" | "free_shipping_cheapest";
  old_rate_metadata_found: boolean;
};

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const QUOTATION_POLL_INTERVAL_MS = 3000;
const QUOTATION_MAX_POLL_ATTEMPTS = 20;

const ALLOWED_CARRIER_PATTERNS = [
  { normalized: "FedEx", regex: /(?:^|[^a-z0-9])fedex(?:[^a-z0-9]|$)/i },
  { normalized: "DHL", regex: /(?:^|[^a-z0-9])dhl(?:[^a-z0-9]|$)/i },
  { normalized: "Estafeta", regex: /(?:^|[^a-z0-9])estafeta(?:[^a-z0-9]|$)/i },
  { normalized: "Paquetexpress", regex: /(?:^|[^a-z0-9])paquetexpress(?:[^a-z0-9]|$)|(?:^|[^a-z0-9])paquete\s*express(?:[^a-z0-9]|$)/i },
];

function isAllowedCarrier(carrierName: string | null | undefined): boolean {
  if (!carrierName || typeof carrierName !== "string") return false;
  const clean = carrierName
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase();

  return ALLOWED_CARRIER_PATTERNS.some((c) => c.regex.test(clean));
}

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

function getNumber(source: JsonRecord | null | undefined, key: string): number | null {
  if (!source) return null;
  const value = source[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_env_${name}`);
  return value;
}

function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization")?.trim() ?? "";
  if (!authHeader.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length).trim();
  return token || null;
}

function decodeBase64UrlJson(value: string): JsonRecord | null {
  try {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(
      normalized.length + ((4 - normalized.length % 4) % 4),
      "=",
    );
    const decoded = atob(padded);
    const parsed = JSON.parse(decoded);
    return isRecord(parsed) ? parsed : null;
  } catch (_) {
    return null;
  }
}

function getJwtRoleFromBearerToken(token: string): string | null {
  const parts = token.split(".");
  if (parts.length < 2) return null;
  const payload = decodeBase64UrlJson(parts[1]);
  return getString(payload, "role");
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function parseJsonResponse(response: Response): Promise<unknown> {
  const rawText = await response.text();
  if (!rawText.trim()) return {};
  try {
    return JSON.parse(rawText);
  } catch (_) {
    throw new Error("invalid_json_response");
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getSandboxAccessToken(baseUrl: string): Promise<string> {
  const clientId = requiredEnv("SKYDROPX_SANDBOX_CLIENT_ID");
  const clientSecret = requiredEnv("SKYDROPX_SANDBOX_CLIENT_SECRET");
  const bodyParams = new URLSearchParams();
  bodyParams.append("grant_type", "client_credentials");
  bodyParams.append("client_id", clientId);
  bodyParams.append("client_secret", clientSecret);

  const response = await fetchWithTimeout(
    `${baseUrl}/api/v1/oauth/token`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
      },
      body: bodyParams.toString(),
    },
    10000,
  );

  const data = await parseJsonResponse(response);
  if (!response.ok || !isRecord(data) || typeof data.access_token !== "string") {
    throw new Error(`oauth_failed_${response.status}`);
  }
  return data.access_token;
}

function buildQuotationAddress(address: JsonRecord): JsonRecord {
  const quotationAddress: JsonRecord = {};
  for (const field of [
    "country_code",
    "postal_code",
    "area_level1",
    "area_level2",
    "area_level3",
  ]) {
    const value = getString(address, field);
    if (!value) throw new Error("invalid_quotation_address");
    quotationAddress[field] = field === "country_code" ? value.toUpperCase() : value;
  }
  return quotationAddress;
}

const SKYDROPX_SHIPMENT_REFERENCE_MAX_CHARS = 30;

function truncateToMaxChars(value: string, maxLength: number): string {
  const characters = Array.from(value.trim());
  if (characters.length === 0) throw new Error("invalid_shipment_reference");
  if (!Number.isInteger(maxLength) || maxLength <= 0) {
    throw new Error("invalid_max_length");
  }
  return characters.length <= maxLength
    ? characters.join("")
    : characters.slice(0, maxLength).join("");
}

function buildShipmentAddress(address: JsonRecord): JsonRecord {
  const reference = getString(address, "reference") ?? "Entrega Go Medical";
  return {
    ...address,
    reference: truncateToMaxChars(
      reference,
      SKYDROPX_SHIPMENT_REFERENCE_MAX_CHARS,
    ),
  };
}

function readTaggedValue(source: string, labels: string[]): string | null {
  for (const rawPart of source.split(/\r?\n|,\s+/)) {
    const part = rawPart.trim();
    if (!part) continue;
    const separatorIndex = part.indexOf(":");
    if (separatorIndex <= 0) continue;
    const label = part.slice(0, separatorIndex).trim().toLowerCase();
    if (!labels.includes(label)) continue;
    const value = part.slice(separatorIndex + 1).trim();
    if (value) return value;
  }
  return null;
}

function buildAddressTo(order: JsonRecord, client: JsonRecord): JsonRecord {
  const snapshot = getString(order, "shipping_address") ?? "";
  const postalCode = readTaggedValue(snapshot, ["codigo postal", "código postal", "cp"]) ??
    snapshot.match(/\b\d{5}\b/)?.[0] ?? null;
  const state = readTaggedValue(snapshot, ["estado"]);
  const city = readTaggedValue(snapshot, ["municipio", "ciudad"]);
  const neighborhood = readTaggedValue(snapshot, ["colonia", "barrio"]);
  const street = readTaggedValue(snapshot, ["direccion", "dirección", "calle"]);
  const interior = readTaggedValue(snapshot, ["interior", "numero interior", "número interior"]);
  const receiverName = readTaggedValue(snapshot, ["recibe", "receptor", "responsable"]);
  const receiverPhone = readTaggedValue(snapshot, ["telefono", "teléfono", "phone"]);
  const reference = readTaggedValue(snapshot, ["indicaciones", "referencia"]);
  const recipientEmail = getString(client, "email");
  const businessName = getString(client, "business_name");

  if (!postalCode || !state || !city || !neighborhood || !street || !receiverName || !receiverPhone || !recipientEmail) {
    throw new Error("invalid_recipient_shipping_data");
  }

  const street1 = interior ? `${street}, Interior ${interior}` : street;

  return {
    country_code: "MX",
    postal_code: postalCode,
    area_level1: state,
    area_level2: city,
    area_level3: neighborhood,
    name: receiverName,
    street1,
    company: businessName ?? receiverName,
    phone: receiverPhone,
    email: recipientEmail,
    reference: reference ?? "Entrega Go Medical",
  };
}

function sanitizeShipment(data: unknown): JsonRecord {
  if (!isRecord(data)) return {};
  const shipment = isRecord(data.shipment)
    ? data.shipment
    : isRecord(data.data)
    ? data.data
    : data;
  const attributes = isRecord(shipment.attributes) ? shipment.attributes : {};
  const carrier = isRecord(shipment.carrier) ? shipment.carrier : {};
  const service = isRecord(shipment.service) ? shipment.service : {};

  return {
    id: getString(shipment, "id"),
    carrier: getString(shipment, "carrier") ??
      getString(carrier, "name") ??
      getString(attributes, "carrier") ??
      getString(attributes, "carrier_name") ??
      getString(shipment, "provider_name") ??
      getString(shipment, "provider_display_name") ??
      getString(attributes, "provider_name") ??
      getString(attributes, "provider_display_name"),
    service_name: getString(shipment, "service_name") ??
      getString(service, "name") ??
      getString(attributes, "service_name") ??
      getString(shipment, "provider_service_name") ??
      getString(attributes, "provider_service_name"),
    tracking_number: getString(shipment, "tracking_number") ??
      getString(attributes, "tracking_number") ??
      getString(shipment, "tracking_code") ??
      getString(attributes, "tracking_code"),
    tracking_url: getString(shipment, "tracking_url") ??
      getString(attributes, "tracking_url") ??
      getString(shipment, "tracking_url_provider") ??
      getString(attributes, "tracking_url_provider"),
    label_url: getString(shipment, "label_url") ??
      getString(attributes, "label_url") ??
      getString(shipment, "label") ??
      getString(attributes, "label"),
    status: getString(shipment, "status") ??
      getString(attributes, "status") ??
      getString(shipment, "tracking_status") ??
      getString(attributes, "tracking_status") ??
      "created",
  };
}

const PROVIDER_DETAIL_TEXT_FIELDS = [
  "error",
  "error_description",
  "errors",
  "message",
  "detail",
  "details",
  "code",
  "error_detail",
  "validation_errors",
] as const;

const SENSITIVE_PROVIDER_DETAIL_PATTERN =
  /authorization|token|secret|service[_-]?role|api[_-]?key|apikey|password/i;
const PROVIDER_PII_KEY_PATTERN =
  /email|phone|street1|name|company|reference/i;
const PROVIDER_DIAGNOSTIC_MAX_DEPTH = 4;
const PROVIDER_DIAGNOSTIC_MAX_ARRAY_ITEMS = 10;
const PROVIDER_DIAGNOSTIC_MAX_OBJECT_FIELDS = 20;
const PROVIDER_DIAGNOSTIC_MAX_STRING_LENGTH = 500;

function isBlockedProviderDetailKey(key: string): boolean {
  return SENSITIVE_PROVIDER_DETAIL_PATTERN.test(key) ||
    PROVIDER_PII_KEY_PATTERN.test(key);
}

function sanitizeProviderDetailText(value: unknown): string | null {
  if (
    typeof value !== "string" &&
    typeof value !== "number" &&
    typeof value !== "boolean"
  ) {
    return null;
  }
  const text = String(value).trim();
  if (!text || SENSITIVE_PROVIDER_DETAIL_PATTERN.test(text)) return null;
  return text.length > PROVIDER_DIAGNOSTIC_MAX_STRING_LENGTH
    ? `${text.slice(0, PROVIDER_DIAGNOSTIC_MAX_STRING_LENGTH)}...`
    : text;
}

function sanitizeProviderDiagnostic(
  value: unknown,
  depth = 0,
): unknown | null {
  if (depth > PROVIDER_DIAGNOSTIC_MAX_DEPTH) return null;

  if (Array.isArray(value)) {
    const sanitizedItems = value
      .slice(0, PROVIDER_DIAGNOSTIC_MAX_ARRAY_ITEMS)
      .map((entry) => sanitizeProviderDiagnostic(entry, depth + 1))
      .filter((entry) => entry !== null);
    return sanitizedItems.length > 0 ? sanitizedItems : null;
  }

  if (isRecord(value)) {
    const sanitizedObject: JsonRecord = {};
    for (
      const [key, entry] of Object.entries(value).slice(
        0,
        PROVIDER_DIAGNOSTIC_MAX_OBJECT_FIELDS,
      )
    ) {
      if (isBlockedProviderDetailKey(key)) continue;
      const sanitized = sanitizeProviderDiagnostic(entry, depth + 1);
      if (sanitized !== null) sanitizedObject[key] = sanitized;
    }
    return Object.keys(sanitizedObject).length > 0 ? sanitizedObject : null;
  }

  return sanitizeProviderDetailText(value);
}

function extractProviderErrorDetails(data: unknown): JsonRecord {
  const providerDetails: JsonRecord = {};
  if (!isRecord(data)) return providerDetails;

  const sources = [
    data,
    isRecord(data.error) ? data.error : null,
    isRecord(data.data) ? data.data : null,
  ].filter((source): source is JsonRecord => isRecord(source));

  for (const source of sources) {
    for (const field of PROVIDER_DETAIL_TEXT_FIELDS) {
      if (providerDetails[field] !== undefined || source[field] === undefined) {
        continue;
      }
      const sanitized = sanitizeProviderDiagnostic(source[field]);
      if (sanitized !== null) providerDetails[field] = sanitized;
    }
  }

  return providerDetails;
}

function getProviderValueType(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value === "object" ? "object" : typeof value;
}

function describeProviderShape(data: unknown): JsonRecord {
  const providerShape: JsonRecord = {
    body_type: getProviderValueType(data),
  };
  if (!isRecord(data)) return providerShape;

  const safeKeys = Object.keys(data)
    .filter((key) => !isBlockedProviderDetailKey(key))
    .slice(0, PROVIDER_DIAGNOSTIC_MAX_OBJECT_FIELDS);
  const topLevelTypes: JsonRecord = {};
  for (const key of safeKeys) {
    topLevelTypes[key] = getProviderValueType(data[key]);
  }

  providerShape.top_level_keys = safeKeys;
  providerShape.top_level_types = topLevelTypes;
  return providerShape;
}

async function buildShippingUnits(adminClient: SupabaseAdminClient, orderId: string): Promise<ShippingUnit[]> {
  const { data: items, error } = await adminClient
    .from("order_items")
    .select("product_id, quantity, product_name_snapshot")
    .eq("order_id", orderId);

  if (error || !Array.isArray(items) || items.length === 0) {
    throw new Error("order_items_not_found");
  }

  const shippingUnits: ShippingUnit[] = [];
  for (const item of items) {
    if (!isRecord(item)) continue;
    const productId = getString(item, "product_id");
    const quantity = Math.max(1, Math.trunc(getNumber(item, "quantity") ?? 1));
    if (!productId) throw new Error("order_item_without_product");

    const { data: logistics, error: logisticsError } = await adminClient
      .from("product_logistics_data")
      .select("package_length, package_width, package_height, package_weight, package_type_code")
      .eq("product_id", productId)
      .maybeSingle();

    if (logisticsError || !isRecord(logistics)) {
      throw new Error("product_not_shippable");
    }

    const { data: fiscal, error: fiscalError } = await adminClient
      .from("product_fiscal_data")
      .select("sat_product_service_code")
      .eq("product_id", productId)
      .maybeSingle();

    if (fiscalError || !isRecord(fiscal)) {
      throw new Error("missing_consignment_note");
    }

    const length = getNumber(logistics, "package_length");
    const width = getNumber(logistics, "package_width");
    const height = getNumber(logistics, "package_height");
    const weight = getNumber(logistics, "package_weight");
    const packageTypeCode = getString(logistics, "package_type_code");
    const consignmentNote = getString(fiscal, "sat_product_service_code");
    if (!length || !width || !height || !weight || length <= 0 || width <= 0 || height <= 0 || weight <= 0) {
      throw new Error("product_not_shippable");
    }
    if (!packageTypeCode) {
      throw new Error("missing_package_type_code");
    }
    if (!consignmentNote) {
      throw new Error("missing_consignment_note");
    }

    for (let i = 0; i < quantity; i++) {
      shippingUnits.push({
        parcel: { length, width, height, weight },
        packageTypeCode,
        consignmentNote,
      });
    }
  }

  return shippingUnits;
}

function buildParcels(
  shippingUnits: ShippingUnit[],
): Array<{ length: number; width: number; height: number; weight: number }> {
  return shippingUnits.map((unit) => unit.parcel);
}

function buildShipmentPackages(
  shippingUnits: ShippingUnit[],
): Array<{ package_number: string; package_protected: boolean; package_type: string; consignment_note: string }> {
  return shippingUnits.map((unit, index) => ({
    package_number: String(index + 1),
    package_protected: false,
    package_type: unit.packageTypeCode,
    consignment_note: unit.consignmentNote,
  }));
}

function unwrapQuotation(data: unknown): JsonRecord | null {
  if (!isRecord(data)) return null;
  return isRecord(data.quotation) ? data.quotation : data;
}

function normalizeForRateMatch(value: string | null): string {
  return (value ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

function extractRate(rawRate: unknown): ShippingRate | null {
  if (!isRecord(rawRate)) return null;
  const rateId = getString(rawRate, "id");
  const status = normalizeForRateMatch(getString(rawRate, "status"));
  const currency = (getString(rawRate, "currency_code") ?? "").toUpperCase();
  const total = getNumber(rawRate, "total");
  const carrier = getString(rawRate, "provider_display_name") ??
    getString(rawRate, "provider_name");
  const service = getString(rawRate, "provider_service_name");
  const days = getNumber(rawRate, "days");

  if (
    !rateId ||
    !carrier ||
    !isAllowedCarrier(carrier) ||
    !service ||
    status === "no_coverage" ||
    status === "not_applicable" ||
    total === null ||
    total <= 0 ||
    currency !== "MXN"
  ) {
    return null;
  }

  return {
    rate_id: rateId,
    carrier,
    service,
    days,
    total: Math.round(total * 100) / 100,
  };
}

type SanitizedRateDiagnostic = {
  rate_id: string | null;
  provider_name: string | null;
  provider_service_name: string | null;
  status: string | null;
  currency_code: string | null;
  total: number | null;
  days: number | null;
  normalized_carrier: string | null;
  allowed_carrier: boolean;
};

type RateDiagnosticsResult = {
  event: "skydropx_rate_diagnostics";
  order_id: string | null;
  quotation_id: string | null;
  is_completed: boolean;
  raw_rate_count: number;
  allowed_rate_count: number;
  reason_classification:
    | "SKYDROPX_ZERO_RATES"
    | "ONLY_DISALLOWED_CARRIERS"
    | "NO_COVERAGE_RATES"
    | "ALLOWED_RATE_FILTER_BUG"
    | "VALID_RATES_FOUND";
  rates: SanitizedRateDiagnostic[];
};

function diagnoseQuotationRates(
  quotation: JsonRecord,
  orderId?: string | null,
): RateDiagnosticsResult {
  const quotationId = getString(quotation, "id");
  const isCompleted = quotation.is_completed === true;
  const rawRates = Array.isArray(quotation.rates) ? quotation.rates : [];

  const sanitizedRates: SanitizedRateDiagnostic[] = [];
  let allowedCount = 0;
  let allowedCarrierCount = 0;
  let noCoverageCount = 0;

  for (const rawRate of rawRates) {
    if (!isRecord(rawRate)) continue;
    const rateId = getString(rawRate, "id");
    const providerName = getString(rawRate, "provider_display_name") ??
      getString(rawRate, "provider_name");
    const serviceName = getString(rawRate, "provider_service_name");
    const status = getString(rawRate, "status");
    const currency = getString(rawRate, "currency_code");
    const total = getNumber(rawRate, "total");
    const days = getNumber(rawRate, "days");
    const normalizedCarrier = providerName
      ? providerName
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .trim()
        .toLowerCase()
      : null;
    const allowed = isAllowedCarrier(providerName);

    if (allowed) allowedCarrierCount++;

    const statusNorm = normalizeForRateMatch(status);
    if (statusNorm === "no_coverage" || statusNorm === "not_applicable") {
      noCoverageCount++;
    }

    const isValid = extractRate(rawRate) !== null;
    if (isValid) allowedCount++;

    sanitizedRates.push({
      rate_id: rateId,
      provider_name: providerName,
      provider_service_name: serviceName,
      status,
      currency_code: currency,
      total,
      days,
      normalized_carrier: normalizedCarrier,
      allowed_carrier: allowed,
    });
  }

  let classification:
    | "SKYDROPX_ZERO_RATES"
    | "ONLY_DISALLOWED_CARRIERS"
    | "NO_COVERAGE_RATES"
    | "ALLOWED_RATE_FILTER_BUG"
    | "VALID_RATES_FOUND" = "VALID_RATES_FOUND";

  if (allowedCount === 0) {
    if (rawRates.length === 0) {
      classification = "SKYDROPX_ZERO_RATES";
    } else if (allowedCarrierCount === 0) {
      classification = "ONLY_DISALLOWED_CARRIERS";
    } else if (noCoverageCount === rawRates.length) {
      classification = "NO_COVERAGE_RATES";
    } else if (allowedCarrierCount > 0) {
      classification = "ALLOWED_RATE_FILTER_BUG";
    }
  }

  const result: RateDiagnosticsResult = {
    event: "skydropx_rate_diagnostics",
    order_id: orderId ?? null,
    quotation_id: quotationId,
    is_completed: isCompleted,
    raw_rate_count: rawRates.length,
    allowed_rate_count: allowedCount,
    reason_classification: classification,
    rates: sanitizedRates,
  };

  console.log(JSON.stringify(result));
  return result;
}

function extractValidRates(quotation: JsonRecord): ShippingRate[] {
  const rawRates = Array.isArray(quotation.rates) ? quotation.rates : [];
  return rawRates
    .map(extractRate)
    .filter((rate): rate is ShippingRate => rate !== null)
    .sort((a, b) => a.total - b.total);
}

function findValidRateById(quotation: JsonRecord, rateId: string | null): ShippingRate | null {
  if (!rateId || !Array.isArray(quotation.rates)) return null;
  for (const rawRate of quotation.rates) {
    const rate = extractRate(rawRate);
    if (rate?.rate_id === rateId) return rate;
  }
  return null;
}

async function getQuotationIfAvailable(
  baseUrl: string,
  accessToken: string,
  quotationId: string | null,
): Promise<JsonRecord | null> {
  if (!quotationId) return null;
  try {
    const response = await fetchWithTimeout(
      `${baseUrl}/api/v1/quotations/${encodeURIComponent(quotationId)}`,
      {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
      },
      10000,
    );
    const data = await parseJsonResponse(response);
    if (!response.ok) return null;
    return unwrapQuotation(data);
  } catch (_) {
    return null;
  }
}

async function createFreshQuotation(
  baseUrl: string,
  accessToken: string,
  addressFrom: JsonRecord,
  addressTo: JsonRecord,
  parcels: Array<{ length: number; width: number; height: number; weight: number }>,
  orderId?: string | null,
): Promise<JsonRecord> {
  let createResponse: Response;
  let createData: unknown;
  let quotationAddressFrom: JsonRecord;
  let quotationAddressTo: JsonRecord;
  try {
    quotationAddressFrom = buildQuotationAddress(addressFrom);
    quotationAddressTo = buildQuotationAddress(addressTo);
  } catch (_) {
    throw new Error("invalid_quotation_address");
  }
  try {
    createResponse = await fetchWithTimeout(
      `${baseUrl}/api/v1/quotations`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          quotation: {
            address_from: quotationAddressFrom,
            address_to: quotationAddressTo,
            parcels,
          },
        }),
      },
      15000,
    );
    createData = await parseJsonResponse(createResponse);
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("skydropx_requotation_timeout");
    }
    throw new Error("skydropx_requotation_failed");
  }

  const createdQuotation = unwrapQuotation(createData);
  if (!createResponse.ok || !createdQuotation) {
    throw new Error("skydropx_requotation_failed");
  }

  const quotationId = getString(createdQuotation, "id");
  if (!quotationId) throw new Error("skydropx_requotation_failed");

  if (createdQuotation.is_completed === true) {
    diagnoseQuotationRates(createdQuotation, orderId);
    if (extractValidRates(createdQuotation).length === 0) {
      throw new Error("no_valid_shipping_rates");
    }
    return createdQuotation;
  }

  for (let attempt = 0; attempt < QUOTATION_MAX_POLL_ATTEMPTS; attempt++) {
    await sleep(QUOTATION_POLL_INTERVAL_MS);
    let pollResponse: Response;
    let pollData: unknown;
    try {
      pollResponse = await fetchWithTimeout(
        `${baseUrl}/api/v1/quotations/${encodeURIComponent(quotationId)}`,
        {
          method: "GET",
          headers: {
            "Accept": "application/json",
            "Authorization": `Bearer ${accessToken}`,
          },
        },
        10000,
      );
      pollData = await parseJsonResponse(pollResponse);
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        throw new Error("skydropx_requotation_timeout");
      }
      throw new Error("skydropx_requotation_failed");
    }

    const pollQuotation = unwrapQuotation(pollData);
    if (!pollResponse.ok || !pollQuotation) {
      throw new Error("skydropx_requotation_failed");
    }

    if (pollQuotation.is_completed !== true) {
      continue;
    }

    diagnoseQuotationRates(pollQuotation, orderId);
    if (extractValidRates(pollQuotation).length === 0) {
      throw new Error("no_valid_shipping_rates");
    }

    return pollQuotation;
  }

  throw new Error("skydropx_requotation_timeout");
}

async function refreshShippingRateForShipment(params: {
  baseUrl: string;
  accessToken: string;
  orderId?: string | null;
  oldQuotationId: string | null;
  oldRateId: string | null;
  customerShippingAmount: number;
  addressFrom: JsonRecord;
  addressTo: JsonRecord;
  parcels: Array<{ length: number; width: number; height: number; weight: number }>;
}): Promise<RefreshedRateSelection> {
  const oldQuotation = await getQuotationIfAvailable(
    params.baseUrl,
    params.accessToken,
    params.oldQuotationId,
  );
  const oldRate = oldQuotation ? findValidRateById(oldQuotation, params.oldRateId) : null;

  const freshQuotation = await createFreshQuotation(
    params.baseUrl,
    params.accessToken,
    params.addressFrom,
    params.addressTo,
    params.parcels,
    params.orderId,
  );
  const newQuotationId = getString(freshQuotation, "id");
  if (!newQuotationId) throw new Error("skydropx_requotation_failed");

  const validRates = extractValidRates(freshQuotation);
  if (validRates.length === 0) throw new Error("no_valid_shipping_rates");

  if (oldRate) {
    const oldCarrier = normalizeForRateMatch(oldRate.carrier);
    const oldService = normalizeForRateMatch(oldRate.service);
    const matchedRate = validRates.find((rate) =>
      normalizeForRateMatch(rate.carrier) === oldCarrier &&
      normalizeForRateMatch(rate.service) === oldService
    );
    if (matchedRate) {
      return {
        quotation_id: newQuotationId,
        rate: matchedRate,
        selection_reason: "same_carrier_service",
        old_rate_metadata_found: true,
      };
    }
  }

  if (Math.round(params.customerShippingAmount * 100) === 0) {
    return {
      quotation_id: newQuotationId,
      rate: validRates[0],
      selection_reason: "free_shipping_cheapest",
      old_rate_metadata_found: oldRate !== null,
    };
  }

  throw new Error("shipping_rate_refresh_requires_manual_selection");
}

async function updateFulfillmentJobStatus(
  adminClient: SupabaseAdminClient,
  orderId: string,
  status: "pending" | "processing" | "completed" | "failed",
  lastError: string | null = null,
): Promise<void> {
  try {
    const nextAttemptAt = status === "failed"
      ? new Date(Date.now() + 5 * 60 * 1000).toISOString()
      : new Date().toISOString();

    await adminClient
      .from("order_fulfillment_jobs")
      .upsert(
        {
          order_id: orderId,
          status,
          last_error: lastError,
          next_attempt_at: nextAttemptAt,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "order_id" },
      );
  } catch (_) {
    // Non-blocking
  }
}

async function triggerFulfillmentForOrder(
  orderId: string,
): Promise<{ body: JsonRecord; status: number }> {
  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: order, error: orderError } = await adminClient
    .from("orders")
    .select("*")
    .eq("id", orderId)
    .maybeSingle();

  if (orderError || !isRecord(order)) {
    return { status: 404, body: { ok: false, error: "order_not_found" } };
  }

  if (order.payment_status !== "approved") {
    return { status: 400, body: { ok: false, error: "order_not_approved" } };
  }

  // 1. Service-only check first (bypass before any physical inventory guard)
  const { data: physicalItems, error: itemsError } = await adminClient
    .from("order_items")
    .select("id, product_id")
    .eq("order_id", orderId)
    .not("product_id", "is", null);

  if (itemsError) {
    return {
      status: 500,
      body: {
        ok: false,
        error: "failed_to_check_order_items",
        details: itemsError.message,
        order_id: orderId,
      },
    };
  }

  const hasPhysicalItems = Array.isArray(physicalItems) && physicalItems.length > 0;
  const hasShippingRate = Boolean(getString(order, "skydropx_rate_id"));
  const sourceQuoteId = getString(order, "source_quote_id");

  let isServiceQuote = false;
  if (sourceQuoteId) {
    const { data: quoteData, error: quoteError } = await adminClient
      .from("quotes")
      .select("id, service_ticket_id")
      .eq("id", sourceQuoteId)
      .maybeSingle();

    if (quoteError) {
      return {
        status: 500,
        body: {
          ok: false,
          error: "failed_to_check_source_quote",
          details: quoteError.message,
          order_id: orderId,
        },
      };
    }

    if (isRecord(quoteData) && getString(quoteData, "service_ticket_id")) {
      isServiceQuote = true;
    }
  }

  // Bypass ÚNICAMENTE para orden de servicio confirmada (cotización ligada a ticket) sin artículos físicos ni tarifa de envío
  if (isServiceQuote === true && !hasPhysicalItems && !hasShippingRate) {
    await updateFulfillmentJobStatus(adminClient, orderId, "completed");
    return {
      status: 200,
      body: {
        ok: true,
        order_id: orderId,
        shipment_created: false,
        service_only: true,
        is_service_quote: true,
        message: "No physical shipment required for verified service ticket order",
      },
    };
  }

  // 2. Physical order authoritative guard: positive stock_status === 'deducted' check
  const stockStatus = getString(order, "stock_status");
  if (stockStatus !== "deducted") {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "inventory_not_finalized");
    return {
      status: 409,
      body: {
        ok: false,
        error: "inventory_not_finalized",
        order_id: orderId,
        stock_status: stockStatus,
      },
    };
  }

  await updateFulfillmentJobStatus(adminClient, orderId, "processing");

  // 3. Existing shipment reuse check
  const { data: existingShipment } = await adminClient
    .from("order_shipments")
    .select("id, skydropx_shipment_id, carrier, service_name, tracking_number, tracking_url, shipping_status")
    .eq("order_id", orderId)
    .not("skydropx_shipment_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (isRecord(existingShipment) && getString(existingShipment, "skydropx_shipment_id")) {
    await updateFulfillmentJobStatus(adminClient, orderId, "completed");
    return {
      status: 200,
      body: {
        ok: true,
        order_id: orderId,
        shipment_created: false,
        shipment_reused: true,
        shipment: existingShipment,
      },
    };
  }

  const oldRateId = getString(order, "skydropx_rate_id");
  const oldQuotationId = getString(order, "skydropx_quotation_id");
  const customerShippingAmount = getNumber(order, "customer_shipping_amount") ?? 0;

  const rawBaseUrl = requiredEnv("SKYDROPX_SANDBOX_BASE_URL");
  const baseUrl = rawBaseUrl.replace(/\/+$/, "");
  let environment: string;
  let autoAdvance: boolean;
  let originResult: { origin: JsonRecord; source: string };
  try {
    environment = resolveSkydropxEnvironment();
    autoAdvance = environment === "sandbox";
    originResult = await resolveShippingOrigin(adminClient, environment);
  } catch (error) {
    const errorName = error instanceof Error ? error.message : "invalid_shipping_origin";
    const status = errorName === "multiple_shipping_origins" ? 409 : 500;
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", errorName);
    return { status, body: { ok: false, error: errorName, order_id: orderId } };
  }

  const clientId = getString(order, "client_id");
  if (!clientId) {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "invalid_recipient_shipping_data");
    return { status: 422, body: { ok: false, error: "invalid_recipient_shipping_data", order_id: orderId } };
  }

  const { data: client, error: clientError } = await adminClient
    .from("clients")
    .select("email, business_name")
    .eq("id", clientId)
    .maybeSingle();

  if (clientError || !isRecord(client)) {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "invalid_recipient_shipping_data");
    return { status: 422, body: { ok: false, error: "invalid_recipient_shipping_data", order_id: orderId } };
  }

  let addressTo: JsonRecord;
  try {
    addressTo = buildAddressTo(order, client);
  } catch (_) {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "invalid_recipient_shipping_data");
    return { status: 422, body: { ok: false, error: "invalid_recipient_shipping_data", order_id: orderId } };
  }

  let shippingUnits: ShippingUnit[];
  try {
    shippingUnits = await buildShippingUnits(adminClient, orderId);
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : "invalid_order_parcels";
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", errorMsg);
    return {
      status: 422,
      body: {
        ok: false,
        error: errorMsg,
        order_id: orderId,
      },
    };
  }
  const parcels = buildParcels(shippingUnits);
  const packages = buildShipmentPackages(shippingUnits);

  let accessToken: string;
  try {
    accessToken = await getSandboxAccessToken(baseUrl);
  } catch (_) {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "skydropx_auth_error");
    return { status: 502, body: { ok: false, error: "skydropx_auth_error", order_id: orderId } };
  }

  let refreshedRate: RefreshedRateSelection;
  try {
    refreshedRate = await refreshShippingRateForShipment({
      baseUrl,
      accessToken,
      orderId,
      oldQuotationId,
      oldRateId,
      customerShippingAmount,
      addressFrom: originResult.origin,
      addressTo,
      parcels,
    });
  } catch (error) {
    const errorName = error instanceof Error ? error.message : "skydropx_requotation_failed";
    const status = errorName === "skydropx_requotation_timeout"
      ? 504
      : errorName === "no_valid_shipping_rates"
      ? 422
      : errorName === "invalid_quotation_address"
      ? 422
      : errorName === "shipping_rate_refresh_requires_manual_selection"
      ? 409
      : 502;
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", errorName);
    return { status, body: { ok: false, error: errorName, order_id: orderId } };
  }

  const { error: logisticsUpdateError } = await adminClient
    .from("orders")
    .update({
      skydropx_quotation_id: refreshedRate.quotation_id,
      skydropx_rate_id: refreshedRate.rate.rate_id,
      skydropx_shipping_cost: refreshedRate.rate.total,
    })
    .eq("id", orderId);

  if (logisticsUpdateError) {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "skydropx_requotation_failed");
    return { status: 500, body: { ok: false, error: "skydropx_requotation_failed", order_id: orderId } };
  }

  const shipmentAddressFrom = buildShipmentAddress(originResult.origin);
  const shipmentAddressTo = buildShipmentAddress(addressTo);
  const shipmentPayload = {
    shipment: {
      rate_id: refreshedRate.rate.rate_id,
      address_from: shipmentAddressFrom,
      address_to: shipmentAddressTo,
      packages,
      unique_shipment: true,
      auto_advance: autoAdvance,
    },
  };

  let shipmentResponse: Response;
  try {
    shipmentResponse = await fetchWithTimeout(
      `${baseUrl}/api/v1/shipments`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify(shipmentPayload),
      },
      20000,
    );
  } catch (error) {
    const errorName = error instanceof Error && error.name === "AbortError"
      ? "skydropx_timeout"
      : "skydropx_network_error";
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", errorName);
    return {
      status: 502,
      body: {
        ok: false,
        error: errorName,
        order_id: orderId,
      },
    };
  }

  let shipmentData: JsonRecord = {};
  try {
    shipmentData = await shipmentResponse.json();
  } catch (_) {
    shipmentData = {};
  }

  if (!shipmentResponse.ok) {
    const providerErrorText = JSON.stringify(shipmentData).toLowerCase();
    const providerDetails = extractProviderErrorDetails(shipmentData);
    const providerShape = describeProviderShape(shipmentData);
    const providerDiagnostic = {
      ...(Object.keys(providerDetails).length > 0
        ? { provider_details: providerDetails }
        : {}),
      provider_shape: providerShape,
    };
    if (
      shipmentResponse.status === 400 || shipmentResponse.status === 422
    ) {
      if (
        providerErrorText.includes("consignment") ||
        providerErrorText.includes("package_type") ||
        providerErrorText.includes("carta porte")
      ) {
        await updateFulfillmentJobStatus(adminClient, orderId, "failed", "skydropx_consignment_note_required");
        return {
          status: 422,
          body: {
            ok: false,
            error: "skydropx_consignment_note_required",
            order_id: orderId,
            provider_status: shipmentResponse.status,
            ...providerDiagnostic,
          },
        };
      }
    }

    const errorMessage = shipmentResponse.status === 422 ? "skydropx_shipment_rejected" : "skydropx_shipment_failed";
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", errorMessage);
    return {
      status: shipmentResponse.status === 422 ? 422 : 502,
      body: {
        ok: false,
        error: shipmentResponse.status === 422
          ? "skydropx_shipment_rejected"
          : "skydropx_shipment_failed",
        order_id: orderId,
        provider_status: shipmentResponse.status,
        ...providerDiagnostic,
      },
    };
  }

  const sanitized = sanitizeShipment(shipmentData);
  const skydropxShipmentId = getString(sanitized, "id");
  if (!skydropxShipmentId) {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "missing_skydropx_shipment_id");
    return { status: 502, body: { ok: false, error: "missing_skydropx_shipment_id", order_id: orderId } };
  }

  const { data: storedShipment, error: shipmentStoreError } = await adminClient.rpc(
    "record_skydropx_order_shipment",
    {
      p_order_id: orderId,
      p_skydropx_shipment_id: skydropxShipmentId,
      p_carrier: getString(sanitized, "carrier") ?? refreshedRate.rate.carrier,
      p_service_name: getString(sanitized, "service_name") ?? refreshedRate.rate.service,
      p_tracking_number: getString(sanitized, "tracking_number"),
      p_tracking_url: getString(sanitized, "tracking_url"),
      p_label_url: getString(sanitized, "label_url"),
      p_shipping_status: getString(sanitized, "status") ?? "created",
      p_estimated_delivery: null,
    },
  );

  if (shipmentStoreError) {
    await updateFulfillmentJobStatus(adminClient, orderId, "failed", "shipment_store_failed");
    return {
      status: 500,
      body: { ok: false, error: "shipment_store_failed", order_id: orderId },
    };
  }

  await updateFulfillmentJobStatus(adminClient, orderId, "completed");

  return {
    status: 200,
    body: {
      ok: true,
      environment,
      order_id: orderId,
      stock_status: stockStatus,
      shipment_created: true,
      unique_shipment: true,
      auto_advance: autoAdvance,
      origin_source: originResult.source,
      rate_refreshed: true,
      rate_selection_reason: refreshedRate.selection_reason,
      old_rate_metadata_found: refreshedRate.old_rate_metadata_found,
      skydropx_quotation_id: refreshedRate.quotation_id,
      skydropx_rate_id: refreshedRate.rate.rate_id,
      skydropx_shipping_cost: refreshedRate.rate.total,
      shipment: storedShipment,
    },
  };
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
    const apiKeyHeader = request.headers.get("apikey")?.trim() || null;
    const token = bearerToken || apiKeyHeader;

    if (!token) {
      return jsonResponse({ ok: false, error: "unauthorized" }, 401);
    }

    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || "";
    const jwtRole = getJwtRoleFromBearerToken(token);

    if (
      jwtRole !== "service_role" &&
      (serviceRoleKey === "" || (token !== serviceRoleKey && bearerToken !== serviceRoleKey && apiKeyHeader !== serviceRoleKey))
    ) {
      return jsonResponse({ ok: false, error: "forbidden" }, 403);
    }

    const body = await request.json().catch(() => ({}));
    if (!isRecord(body)) {
      return jsonResponse({ ok: false, error: "invalid_json_body" }, 400);
    }
    const orderId = getString(body, "order_id");
    if (!orderId || !/^[0-9a-fA-F-]{36}$/.test(orderId)) {
      return jsonResponse({ ok: false, error: "invalid_order_id" }, 400);
    }

    const result = await triggerFulfillmentForOrder(orderId);
    return jsonResponse(result.body, result.status);
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: "internal_server_error",
      message: error instanceof Error ? error.message : "unknown_error",
    }, 500);
  }
});
