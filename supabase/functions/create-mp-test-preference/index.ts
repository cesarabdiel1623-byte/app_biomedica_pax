import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonRecord = Record<string, unknown>;

function jsonResponse(body: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}

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

  let data: unknown;
  try {
    data = await parseJsonResponse(response);
  } catch (_) {
    throw new Error("invalid_oauth_token_response");
  }

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

  if ("user_id" in body || "profile_id" in body || "client_id" in body) {
    return jsonResponse({
      ok: false,
      error: "identity_fields_not_allowed",
      message: "La identidad del comprador se determina únicamente desde la sesión autenticada.",
    }, 400);
  }

  const cartId = getString(body, "cart_id");
  const addressId = getString(body, "address_id");
  const quotationId = getString(body, "skydropx_quotation_id");
  const rateId = getString(body, "skydropx_rate_id");
  const notes = getString(body, "notes");

  // Validación estricta de selección de envío
  if (!cartId || !addressId || !quotationId || !rateId) {
    return jsonResponse({
      ok: false,
      error: "missing_shipping_selection",
      message: "Debes seleccionar una opción de envío válida para continuar al pago.",
    }, 400);
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

  const { data: addr } = await adminClient
    .from("client_addresses")
    .select("id")
    .eq("id", addressId)
    .eq("client_id", clientId)
    .single();

  if (!addr) {
    return jsonResponse({
      ok: false,
      error: "shipping_address_not_found",
      message: "La dirección seleccionada no pertenece al cliente.",
    }, 404);
  }

  const rawBaseUrl = Deno.env.get("SKYDROPX_SANDBOX_BASE_URL")?.trim() || "https://sb-pro.skydropx.com";
  const baseUrl = rawBaseUrl.replace(/\/+$/, "");

  let accessToken: string;
  try {
    accessToken = await getSandboxAccessToken(baseUrl);
  } catch (_) {
    return jsonResponse({
      ok: false,
      error: "skydropx_auth_error",
      message: "No fue posible verificar la tarifa logísticamente.",
    }, 502);
  }

  let quoteRes: Response;
  try {
    quoteRes = await fetchWithTimeout(
      `${baseUrl}/api/v1/quotations/${quotationId}`,
      {
        method: "GET",
        headers: { "Authorization": `Bearer ${accessToken}` },
      },
      10000,
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
    quoteData = await parseJsonResponse(quoteRes);
  } catch (_) {
    return jsonResponse({
      ok: false,
      error: "skydropx_invalid_response",
      message: "La respuesta devuelta por el proveedor logístico no es válida.",
    }, 502);
  }

  if (!quoteRes.ok || !isRecord(quoteData) || quoteData.is_completed !== true) {
    return jsonResponse({
      ok: false,
      error: "shipping_quote_expired",
      message: "La cotización de envío seleccionada ha expirado o aún no se completa.",
    }, 400);
  }

  const rawRates = Array.isArray(quoteData.rates) ? quoteData.rates : [];
  const validRates: Array<{ id: string; total: number }> = [];

  for (const r of rawRates) {
    if (!isRecord(r)) continue;
    const rId = getString(r, "id");
    const rStatus = getString(r, "status");
    const rCurrency = (getString(r, "currency_code") ?? "").toUpperCase();
    const rTotal = getNumber(r, "total");

    const rCarrier = getString(r, "provider_display_name") ?? getString(r, "provider_name") ?? "";

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
    validRates.push({ id: rId, total: Math.round(rTotal * 100) / 100 });
  }

  const matchedRate = validRates.find((r) => r.id === rateId);
  if (!matchedRate) {
    return jsonResponse({
      ok: false,
      error: "invalid_shipping_rate",
      message: "La tarifa de envío seleccionada ya no es válida o disponible.",
    }, 400);
  }

  validRates.sort((a, b) => a.total - b.total);
  const selectedRateTotal = matchedRate.total;
  const cheapestValidRateTotal = validRates[0].total;

  const { data: orderData, error: rpcError } = await adminClient.rpc("prepare_mp_order", {
    p_user_id: user.id,
    p_cart_id: cartId,
    p_address_id: addressId,
    p_skydropx_quotation_id: quotationId,
    p_skydropx_rate_id: rateId,
    p_selected_rate_total: selectedRateTotal,
    p_cheapest_valid_rate_total: cheapestValidRateTotal,
    p_notes: notes,
  });

  if (rpcError || !isRecord(orderData)) {
    return jsonResponse({
      ok: false,
      error: "order_preparation_failed",
      message: rpcError?.message ?? "Error al preparar la orden de compra.",
    }, 500);
  }

  const paymentTotal = getNumber(orderData, "payment_total");
  if (!paymentTotal || !Number.isFinite(paymentTotal) || paymentTotal <= 0) {
    return jsonResponse({
      ok: false,
      error: "invalid_payment_total",
      message: "El total de pago devuelto por el servidor es inválido.",
    }, 500);
  }

  const mpToken = Deno.env.get("MERCADO_PAGO_ACCESS_TOKEN")?.trim();
  if (!mpToken) {
    return jsonResponse({
      ok: false,
      error: "mercado_pago_token_missing",
      message: "Configuración de Mercado Pago incompleta en el servidor.",
    }, 500);
  }

  const orderNumber = getString(orderData, "order_number") ?? "";
  const orderId = getString(orderData, "order_id") ?? "";
  const paymentRecordId = getString(orderData, "payment_record_id");
  const preferenceExpiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  let prefRes: Response;
  try {
    prefRes = await fetchWithTimeout(
      "https://api.mercadopago.com/checkout/preferences",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${mpToken}`,
        },
        body: JSON.stringify({
          items: [
            {
              title: `Pedido Go Medical - ${orderNumber}`,
              quantity: 1,
              unit_price: Number(paymentTotal.toFixed(2)),
              currency_id: "MXN",
            },
          ],
          external_reference: orderNumber,
          expires: true,
          expiration_date_to: preferenceExpiresAt,
          back_urls: {
            success: "gomedical://payment/success",
            pending: "gomedical://payment/pending",
            failure: "gomedical://payment/failure",
          },
          auto_return: "approved",
        }),
      },
      10000,
    );
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: "mercado_pago_network_error",
      message: error instanceof Error ? error.message : "Error al conectar con Mercado Pago.",
    }, 502);
  }

  const prefData = await parseJsonResponse(prefRes);
  if (!prefRes.ok || !isRecord(prefData)) {
    return jsonResponse({
      ok: false,
      error: "mercado_pago_preference_failed",
      message: "Mercado Pago no pudo crear la preferencia de pago.",
      provider_status: prefRes.status,
    }, 502);
  }

  const checkoutUrl = getString(prefData, "init_point");
  const preferenceId = getString(prefData, "id");

  if (!checkoutUrl || !preferenceId) {
    return jsonResponse({
      ok: false,
      error: "invalid_mercado_pago_response",
      message: "Respuesta inválida de la pasarela de pagos.",
    }, 502);
  }

  // Persistir canónicamente en order_payments (fail-closed)
  let persistQuery = adminClient
    .from("order_payments")
    .update({
      preference_id: preferenceId,
      checkout_url: checkoutUrl,
      preference_expires_at: preferenceExpiresAt,
      updated_at: new Date().toISOString(),
    })
    .eq("order_id", orderId);

  if (paymentRecordId) {
    persistQuery = persistQuery.eq("id", paymentRecordId);
  } else {
    persistQuery = persistQuery.eq("external_reference", orderNumber);
  }

  const { data: updatedPayment, error: persistError } = await persistQuery
    .select("id, preference_id, checkout_url, preference_expires_at")
    .maybeSingle();

  if (persistError || !updatedPayment || !getString(updatedPayment, "checkout_url")) {
    return jsonResponse({
      ok: false,
      error: "preference_persistence_failed",
      message: "Error al registrar la preferencia de pago en la base de datos.",
    }, 500);
  }

  return jsonResponse({
    ok: true,
    checkout_url: getString(updatedPayment, "checkout_url") ?? checkoutUrl,
    preference_id: getString(updatedPayment, "preference_id") ?? preferenceId,
    preference_expires_at: getString(updatedPayment, "preference_expires_at") ?? preferenceExpiresAt,
    order_id: orderId,
    order_number: orderNumber,
    product_subtotal: getNumber(orderData, "product_subtotal"),
    customer_shipping_amount: getNumber(orderData, "customer_shipping_amount"),
    skydropx_shipping_cost: getNumber(orderData, "skydropx_shipping_cost"),
    shipping_discount_amount: getNumber(orderData, "shipping_discount_amount"),
    payment_total: paymentTotal,
    reused: orderData.reused === true,
  });
});
