import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  resolveShippingOrigin,
  resolveSkydropxEnvironment,
  SKYDROPX_SANDBOX_TEST_ORIGIN,
} from "../_shared/skydropx_shipping_origin.ts";

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonRecord = Record<string, unknown>;

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
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getString(source: JsonRecord, key: string): string | null {
  const value = source[key];
  if (typeof value === "string" && value.trim() !== "") return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function getNumber(source: JsonRecord, key: string): number | null {
  const value = source[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function roundFinancialAmount(value: number): number {
  return Math.round(Math.max(0, value) * 100) / 100;
}

function roundCommercialAmount(value: number): number {
  return Math.round(Math.max(0, value));
}

function getEffectiveCommercialUnitPrice(product: JsonRecord, baseUnitPrice: number): number {
  let effectiveUnitPrice = roundCommercialAmount(baseUnitPrice);
  const promotions = Array.isArray(product.active_product_promotions)
    ? product.active_product_promotions
    : [];

  for (const rawPromo of promotions) {
    if (!isRecord(rawPromo)) continue;
    const promotionalPrice = getNumber(rawPromo, "promotional_price_mxn");
    if (promotionalPrice === null || promotionalPrice < 0) continue;
    effectiveUnitPrice = Math.min(
      effectiveUnitPrice,
      roundCommercialAmount(promotionalPrice),
    );
  }

  return effectiveUnitPrice;
}

function extractNeighborhood(storedAddress: string, city: string): string | null {
  if (!storedAddress || storedAddress.trim() === "") return null;

  const linesOrParts = storedAddress.split(/\r?\n|,\s+/);
  const unlabeled: string[] = [];

  for (const rawPart of linesOrParts) {
    const part = rawPart.trim();
    if (!part) continue;

    const separator = part.indexOf(":");
    if (separator > 0) {
      const label = part.substring(0, separator).trim().toLowerCase();
      const val = part.substring(separator + 1).trim();
      if ((label === "colonia" || label === "barrio") && val !== "") {
        return val;
      }
    } else {
      const lower = part.toLowerCase();
      if (lower.startsWith("colonia ")) {
        const val = part.substring("colonia ".length).trim();
        if (val) return val;
      } else if (lower.startsWith("col. ")) {
        const val = part.substring("col. ".length).trim();
        if (val) return val;
      } else {
        unlabeled.push(part);
      }
    }
  }

  if (unlabeled.length > 1) {
    const candidate = unlabeled[1].trim();
    if (candidate && candidate.toLowerCase() !== city.toLowerCase()) {
      return candidate;
    }
  }

  return null;
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function parseJsonResponse(response: Response): Promise<unknown> {
  const rawText = await response.text();
  try {
    return JSON.parse(rawText);
  } catch (_) {
    throw new Error("invalid_json_response");
  }
}

async function getSandboxAccessToken(baseUrl: string): Promise<string> {
  const clientId = Deno.env.get("SKYDROPX_SANDBOX_CLIENT_ID")?.trim();
  const clientSecret = Deno.env.get("SKYDROPX_SANDBOX_CLIENT_SECRET")?.trim();

  if (!clientId || !clientSecret) {
    throw new Error("missing_oauth_configuration");
  }

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

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: JSON_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ ok: false, error: "unauthorized", message: "Header Authorization requerido." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();

  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceKey) {
    return jsonResponse({
      ok: false,
      error: "missing_server_configuration",
      message: "Error de configuración interna del servidor.",
    }, 500);
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ ok: false, error: "unauthorized", message: "Sesión no válida o expirada." }, 401);
  }

  const adminClient = createClient(supabaseUrl, supabaseServiceKey);

  let body: JsonRecord = {};
  try {
    const parsed = await request.json();
    if (isRecord(parsed)) body = parsed;
  } catch (_) {
    return jsonResponse({ ok: false, error: "invalid_json_body" }, 400);
  }

  const cartId = getString(body, "cart_id");
  if (!cartId) {
    return jsonResponse({ ok: false, error: "cart_id_required", message: "Identificador de carrito requerido." }, 400);
  }

  const { data: profile } = await adminClient
    .from("profiles")
    .select("client_id")
    .eq("id", user.id)
    .single();

  const clientId = profile?.client_id;
  if (!clientId) {
    return jsonResponse({ ok: false, error: "client_not_found", message: "Perfil de cliente no asociado." }, 400);
  }

  const { data: cart } = await adminClient
    .from("carts")
    .select("*")
    .eq("id", cartId)
    .eq("client_id", clientId)
    .single();

  if (!cart || cart.status !== "active") {
    return jsonResponse({ ok: false, error: "cart_not_found", message: "Carrito no encontrado o inactivo." }, 404);
  }

  const addressId = getString(body, "address_id");
  let addressRecord: JsonRecord | null = null;

  if (addressId) {
    const { data: addr } = await adminClient
      .from("client_addresses")
      .select("*")
      .eq("id", addressId)
      .eq("client_id", clientId)
      .single();

    if (!addr || !isRecord(addr)) {
      return jsonResponse({
        ok: false,
        error: "shipping_address_not_found",
        message: "La dirección de envío seleccionada no existe o no pertenece al cliente.",
      }, 404);
    }
    addressRecord = addr;
  } else {
    const { data: addrList } = await adminClient
      .from("client_addresses")
      .select("*")
      .eq("client_id", clientId)
      .order("is_default", { ascending: false })
      .limit(1);

    if (addrList && addrList.length > 0 && isRecord(addrList[0])) {
      addressRecord = addrList[0];
    }
  }

  if (!addressRecord) {
    return jsonResponse({
      ok: false,
      error: "shipping_address_required",
      message: "Agrega o selecciona una dirección de entrega para cotizar el envío.",
    }, 400);
  }

  const { data: cartItems } = await adminClient
    .from("cart_items")
    .select("id, product_id, quantity, products(id, name, unit_price_mxn, active_product_promotions(promotional_price_mxn, computed_status))")
    .eq("cart_id", cartId);

  if (!cartItems || cartItems.length === 0) {
    return jsonResponse({ ok: false, error: "cart_empty", message: "El carrito está vacío." }, 400);
  }

  let productSubtotal = 0;
  const parcels: Array<{ length: number; width: number; height: number; weight: number }> = [];

  for (const item of cartItems) {
    const prod = isRecord(item.products) ? item.products : null;
    const qty = getNumber(isRecord(item) ? item : {}, "quantity") ?? 1;
    const prodName = prod ? (getString(prod, "name") ?? "Producto") : "Producto";
    const prodId = prod ? (getString(prod, "id") ?? "") : "";
    const unitPrice = prod ? (getNumber(prod, "unit_price_mxn") ?? 0) : 0;
    const payableUnitPrice = prod
      ? getEffectiveCommercialUnitPrice(prod, unitPrice)
      : 0;

    productSubtotal += roundFinancialAmount(payableUnitPrice * qty);

    const { data: logistics } = await adminClient
      .from("product_logistics_data")
      .select("package_length, package_width, package_height, package_weight")
      .eq("product_id", prodId)
      .single();

    if (!logistics || !isRecord(logistics)) {
      return jsonResponse({
        ok: false,
        shippable: false,
        error: "product_not_shippable",
        message: `El producto "${prodName}" no cuenta con dimensiones logísticas para cotizar envío.`,
        product_id: prodId,
        product_name: prodName,
      }, 422);
    }

    const len = getNumber(logistics, "package_length");
    const wid = getNumber(logistics, "package_width");
    const hei = getNumber(logistics, "package_height");
    const wei = getNumber(logistics, "package_weight");

    if (!len || len <= 0 || !wid || wid <= 0 || !hei || hei <= 0 || !wei || wei <= 0) {
      return jsonResponse({
        ok: false,
        shippable: false,
        error: "product_not_shippable",
        message: `El producto "${prodName}" no cuenta con dimensiones logísticas completas para cotizar envío.`,
        product_id: prodId,
        product_name: prodName,
      }, 422);
    }

    for (let i = 0; i < qty; i++) {
      parcels.push({
        length: len,
        width: wid,
        height: hei,
        weight: wei,
      });
    }
  }

  const destPostalCode = getString(addressRecord, "postal_code") ?? "";
  const destState = getString(addressRecord, "state") ?? "";
  const destCity = getString(addressRecord, "city") ?? "";
  const destAddressText = getString(addressRecord, "address") ?? "";
  const destNeighborhood = extractNeighborhood(destAddressText, destCity);

  if (!destPostalCode || !destState || !destCity || !destNeighborhood) {
    return jsonResponse({
      ok: false,
      error: "invalid_shipping_address",
      message: "La dirección seleccionada no cuenta con un código postal, estado, municipio o colonia válidos.",
    }, 400);
  }

  const rawBaseUrl = Deno.env.get("SKYDROPX_SANDBOX_BASE_URL")?.trim() || "https://sb-pro.skydropx.com";
  const baseUrl = rawBaseUrl.replace(/\/+$/, "");

  let accessToken: string;
  try {
    accessToken = await getSandboxAccessToken(baseUrl);
  } catch (err) {
    return jsonResponse({
      ok: false,
      error: "skydropx_auth_error",
      message: "No fue posible autenticar la conexión con el proveedor logístico.",
    }, 502);
  }

  let originResult: { origin: JsonRecord; source: string };
  try {
    const environment = resolveSkydropxEnvironment();
    originResult = await resolveShippingOrigin(adminClient, environment);
  } catch (error) {
    const errorName = error instanceof Error ? error.message : "invalid_shipping_origin";
    const status = errorName === "multiple_shipping_origins" ? 409 : 500;
    return jsonResponse({
      ok: false,
      error: errorName,
      message: "Error al resolver la dirección de origen para el envío.",
    }, status);
  }

  const quotationPayload = {
    address_from: {
      country_code: getString(originResult.origin, "country_code"),
      postal_code: getString(originResult.origin, "postal_code"),
      area_level1: getString(originResult.origin, "area_level1"),
      area_level2: getString(originResult.origin, "area_level2"),
      area_level3: getString(originResult.origin, "area_level3"),
    },
    address_to: {
      country_code: "MX",
      postal_code: destPostalCode,
      area_level1: destState,
      area_level2: destCity,
      area_level3: destNeighborhood,
    },
    parcels: parcels,
  };

  let createQuoteResponse: Response;
  try {
    createQuoteResponse = await fetchWithTimeout(
      `${baseUrl}/api/v1/quotations`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          quotation: {
            address_from: quotationPayload.address_from,
            address_to: quotationPayload.address_to,
            parcels: quotationPayload.parcels,
          },
        }),
      },
      15000,
    );
  } catch (_) {
    return jsonResponse({
      ok: false,
      error: "skydropx_network_error",
      message: "Error de red al consultar SkyDropX.",
    }, 502);
  }

  let quoteData: unknown;
  try {
    quoteData = await parseJsonResponse(createQuoteResponse);
  } catch (_) {
    if (createQuoteResponse.ok) {
      return jsonResponse({
        ok: false,
        error: "skydropx_invalid_response",
        message: "La respuesta devuelta por el proveedor logístico no es válida.",
      }, 502);
    }
    quoteData = {};
  }

  if (!createQuoteResponse.ok || !isRecord(quoteData)) {
    if (createQuoteResponse.status === 400 || createQuoteResponse.status === 422) {
      return jsonResponse({
        ok: false,
        error: "invalid_shipping_address",
        message: "No fue posible cotizar esta dirección. Verifica código postal, estado, municipio y colonia.",
      }, 422);
    }

    if (createQuoteResponse.status === 429) {
      return jsonResponse({
        ok: false,
        error: "skydropx_rate_limited",
        message: "El proveedor logístico está limitando temporalmente las cotizaciones. Inténtalo de nuevo en unos minutos.",
      }, 429);
    }

    return jsonResponse({
      ok: false,
      error: "skydropx_quote_failed",
      message: "No fue posible crear la cotización de envío con SkyDropX.",
    }, 502);
  }

  const quotationId = getString(quoteData, "id");
  if (!quotationId) {
    return jsonResponse({
      ok: false,
      error: "missing_quotation_id",
      message: "No se recibió un identificador de cotización válido del proveedor.",
    }, 502);
  }

  let finalQuoteData = quoteData;
  if (quoteData.is_completed === false) {
    for (let poll = 0; poll < 5; poll++) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      const pollRes = await fetchWithTimeout(
        `${baseUrl}/api/v1/quotations/${quotationId}`,
        {
          method: "GET",
          headers: { "Authorization": `Bearer ${accessToken}` },
        },
        10000,
      );
      const pollData = await parseJsonResponse(pollRes);
      if (pollRes.ok && isRecord(pollData)) {
        finalQuoteData = pollData;
        if (pollData.is_completed === true) break;
      }
    }
  }

  if (finalQuoteData.is_completed !== true) {
    return jsonResponse({
      ok: false,
      error: "quotation_still_processing",
      message: "La cotización aún se encuentra procesando en el proveedor logístico. Inténtalo de nuevo.",
    }, 504);
  }

  const rawRates = Array.isArray(finalQuoteData.rates) ? finalQuoteData.rates : [];
  const validRates: Array<{
    rate_id: string;
    carrier: string;
    service: string;
    days: number;
    actual_shipping_cost: number;
  }> = [];

  for (const r of rawRates) {
    if (!isRecord(r)) continue;
    const rId = getString(r, "id");
    const rStatus = getString(r, "status");
    const rCurrency = (getString(r, "currency_code") ?? "").toUpperCase();
    const rTotal = getNumber(r, "total");
    const rCarrier = getString(r, "provider_display_name") ?? getString(r, "provider_name") ?? "Carrier";
    const rService = getString(r, "provider_service_name") ?? "Estándar";
    const rDays = getNumber(r, "days") ?? 3;

    if (
      !rId ||
      !isAllowedCarrier(rCarrier) ||
      rStatus === "no_coverage" ||
      rStatus === "not_applicable" ||
      rTotal === null ||
      rTotal <= 0 ||
      rCurrency !== "MXN"
    ) {
      continue;
    }

    validRates.push({
      rate_id: rId,
      carrier: rCarrier,
      service: rService,
      days: rDays,
      actual_shipping_cost: Math.round(rTotal * 100) / 100,
    });
  }

  if (validRates.length === 0) {
    return jsonResponse({
      ok: false,
      error: "no_valid_rates",
      message: "No hay opciones de envío disponibles para la dirección seleccionada.",
    }, 422);
  }

  validRates.sort((a, b) => a.actual_shipping_cost - b.actual_shipping_cost);

  const { data: storeSetting } = await adminClient
    .from("store_settings")
    .select("free_shipping_threshold")
    .limit(1)
    .single();

  const threshold = getNumber(isRecord(storeSetting) ? storeSetting : {}, "free_shipping_threshold") ?? 5000;
  productSubtotal = roundFinancialAmount(productSubtotal);
  const freeShippingUnlocked = productSubtotal >= threshold;
  const cheapestValidRateTotal = validRates[0].actual_shipping_cost;

  const processedRates = validRates.map((rate) => {
    let customerShippingAmount = rate.actual_shipping_cost;
    let shippingDiscountAmount = 0;

    if (freeShippingUnlocked) {
      shippingDiscountAmount = cheapestValidRateTotal;
      customerShippingAmount = Math.max(0, Math.round((rate.actual_shipping_cost - cheapestValidRateTotal) * 100) / 100);
    }

    const label = customerShippingAmount === 0
      ? "GRATIS"
      : `+$${customerShippingAmount.toFixed(2)}`;

    return {
      rate_id: rate.rate_id,
      carrier: rate.carrier,
      service: rate.service,
      days: rate.days,
      actual_shipping_cost: rate.actual_shipping_cost,
      customer_shipping_amount: customerShippingAmount,
      shipping_discount_amount: shippingDiscountAmount,
      label: label,
    };
  });

  return jsonResponse({
    ok: true,
    shippable: true,
    product_subtotal: Math.round(productSubtotal * 100) / 100,
    free_shipping_threshold: threshold,
    free_shipping_unlocked: freeShippingUnlocked,
    cheapest_valid_rate_total: cheapestValidRateTotal,
    quotation_id: quotationId,
    rates: processedRates,
  });
});
