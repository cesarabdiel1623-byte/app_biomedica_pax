import { createClient } from "npm:@supabase/supabase-js@2";

type JsonRecord = Record<string, unknown>;
type SupabaseAdminClient = {
  from: (table: string) => any;
};
type PaymentRecord = {
  id: string;
  environment: string | null;
  status: string | null;
  amount: number | null;
  external_reference: string | null;
  preference_id: string | null;
  checkout_url: string | null;
  preference_expires_at: string | null;
};

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getString(source: JsonRecord | null | undefined, key: string): string | null {
  if (!source) return null;
  const value = source[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function getNumber(source: JsonRecord | null | undefined, key: string): number | null {
  if (!source) return null;
  const value = source[key];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function readMercadoPagoEnvironment(): "test" | "production" {
  const configured = Deno.env.get("MERCADO_PAGO_ENV")?.trim().toLowerCase();
  if (configured === "test" || configured === "production") {
    return configured;
  }
  throw new Error("invalid_mercado_pago_environment_configuration");
}

function isUuid(value: string | null | undefined): boolean {
  if (!value) return false;
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(value);
}

async function fetchWithTimeout(
  url: string,
  options: RequestInit,
  timeoutMs = 10000,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function parseJsonResponse(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    throw new Error(`invalid_json_response_${response.status}`);
  }
}

function hasReusablePreference(payment: Partial<PaymentRecord> | null | undefined): payment is PaymentRecord {
  if (!payment?.checkout_url || !payment.preference_expires_at) return false;
  return new Date(payment.preference_expires_at) > new Date();
}

async function findReusablePayment(
  adminClient: SupabaseAdminClient,
  orderId: string,
): Promise<PaymentRecord | null> {
  const { data } = await adminClient
    .from("order_payments")
    .select("id, environment, status, amount, external_reference, preference_id, checkout_url, preference_expires_at")
    .eq("order_id", orderId)
    .not("preference_id", "is", null)
    .not("checkout_url", "is", null)
    .gt("preference_expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return (data as PaymentRecord | null) ?? null;
}

async function waitForConcurrentPreference(
  adminClient: SupabaseAdminClient,
  orderId: string,
): Promise<PaymentRecord | null> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const reusable = await findReusablePayment(adminClient, orderId);
    if (reusable?.checkout_url) return reusable;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return null;
}

async function releasePreferenceClaim(
  adminClient: SupabaseAdminClient,
  paymentRecordId: string,
  reason: string,
): Promise<void> {
  await adminClient
    .from("order_payments")
    .update({
      status: "created",
      status_detail: reason,
      updated_at: new Date().toISOString(),
    })
    .eq("id", paymentRecordId)
    .eq("status", "pending")
    .is("preference_id", null);
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
    return jsonResponse(
      { ok: false, error: "unauthorized", message: "Header Authorization requerido." },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();

  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceKey) {
    return jsonResponse(
      {
        ok: false,
        error: "missing_server_configuration",
        message: "Error de configuración interna del servidor.",
      },
      500,
    );
  }

  // 1. Cliente con credenciales del usuario para preservar auth.uid() en RPC
  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return jsonResponse(
      { ok: false, error: "unauthorized", message: "Sesión no válida o expirada." },
      401,
    );
  }

  // 2. Parseo y validación estricta del body
  let body: JsonRecord = {};
  try {
    const parsed = await request.json();
    if (isRecord(parsed)) body = parsed;
  } catch (_) {
    return jsonResponse({ ok: false, error: "invalid_json_body" }, 400);
  }

  // Seguridad: Rechazar cualquier intento de forjar montos, identidades o referencias
  const forbiddenFields = [
    "user_id",
    "profile_id",
    "client_id",
    "amount",
    "total",
    "subtotal",
    "tax",
    "discount",
    "currency_id",
    "external_reference",
    "environment",
    "order_id",
    "payment_record_id",
    "preference_id",
  ];
  for (const field of forbiddenFields) {
    if (field in body) {
      return jsonResponse(
        {
          ok: false,
          error: "forbidden_field",
          message: `El campo '${field}' no está permitido en la solicitud.`,
        },
        400,
      );
    }
  }

  const quoteId = getString(body, "quote_id");
  const notes = getString(body, "notes");

  if (!quoteId || !isUuid(quoteId)) {
    return jsonResponse(
      {
        ok: false,
        error: "invalid_quote_id",
        message: "Se requiere un ID de cotización válido (UUID).",
      },
      400,
    );
  }

  // 3. Ejecutar RPC autoritativa prepare_quote_order mediante userClient
  const { data: prepData, error: prepError } = await userClient.rpc(
    "prepare_quote_order",
    {
      p_quote_id: quoteId,
      ...(notes ? { p_notes: notes } : {}),
    },
  );

  if (prepError || !isRecord(prepData)) {
    const msg = prepError?.message ?? "Error al preparar la orden de la cotización.";
    console.error("prepare_quote_order RPC failed", {
      user_id: user.id,
      quote_id: quoteId,
      error: msg,
    });
    return jsonResponse(
      {
        ok: false,
        error: "prepare_order_failed",
        message: msg,
      },
      400,
    );
  }

  const orderId = getString(prepData, "order_id");
  const orderNumber = getString(prepData, "order_number");
  const amount = getNumber(prepData, "amount");
  const currencyId = getString(prepData, "currency_id") ?? "MXN";
  const alreadyPaid = prepData.already_paid === true;
  const reusePreference = prepData.reuse_preference === true;

  // 4. Caso A: Orden ya pagada
  if (alreadyPaid) {
    return jsonResponse({
      ok: true,
      already_paid: true,
      reuse_preference: false,
      order_id: orderId,
      order_number: orderNumber,
      amount: amount,
      currency_id: currencyId,
    });
  }

  // 5. Caso B: Preferencia vigente reutilizable
  if (reusePreference && getString(prepData, "checkout_url")) {
    return jsonResponse({
      ok: true,
      already_paid: false,
      reuse_preference: true,
      order_id: orderId,
      order_number: orderNumber,
      payment_record_id: getString(prepData, "payment_record_id"),
      external_reference: getString(prepData, "external_reference"),
      checkout_url: getString(prepData, "checkout_url"),
      amount: amount,
      currency_id: currencyId,
      expires_at: getString(prepData, "expires_at"),
    });
  }

  // 6. Caso C: Generación de nueva preferencia en Mercado Pago
  const paymentRecordId = getString(prepData, "payment_record_id");
  const externalReference = getString(prepData, "external_reference");

  if (!orderId || !paymentRecordId || !externalReference || !amount || amount <= 0) {
    return jsonResponse(
      {
        ok: false,
        error: "invalid_order_state",
        message: "El estado de la orden preparada es inconsistente.",
      },
      500,
    );
  }

  const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Validaciones server-side de consistencia en BD
  const { data: orderRow, error: orderErr } = await adminClient
    .from("orders")
    .select("id, client_id, total, source_quote_id, status, payment_status")
    .eq("id", orderId)
    .single();

  if (orderErr || !orderRow || orderRow.source_quote_id !== quoteId) {
    return jsonResponse(
      {
        ok: false,
        error: "order_verification_failed",
        message: "No se pudo verificar la orden asociada a la cotización.",
      },
      404,
    );
  }

  const { data: quoteRow, error: quoteErr } = await adminClient
    .from("quotes")
    .select("id, client_id, service_ticket_id, status")
    .eq("id", quoteId)
    .single();

  if (quoteErr || !quoteRow || !quoteRow.service_ticket_id) {
    return jsonResponse(
      {
        ok: false,
        error: "quote_verification_failed",
        message: "La cotización debe pertenecer a un expediente técnico de servicio.",
      },
      400,
    );
  }

  // Obtener registro de order_payments y validar ambiente server-side
  const { data: paymentRow, error: paymentRowErr } = await adminClient
    .from("order_payments")
    .select("id, environment, status, amount, external_reference, preference_id, checkout_url, preference_expires_at")
    .eq("id", paymentRecordId)
    .single();

  if (paymentRowErr || !paymentRow) {
    return jsonResponse(
      {
        ok: false,
        error: "payment_record_not_found",
        message: "No se encontró el registro de pago para la orden.",
      },
      404,
    );
  }

  // Idempotencia: Si ya cuenta con preferencia vigente persistida
  if (
    paymentRow.checkout_url &&
    paymentRow.preference_expires_at &&
    new Date(paymentRow.preference_expires_at) > new Date()
  ) {
    return jsonResponse({
      ok: true,
      already_paid: false,
      reuse_preference: true,
      order_id: orderId,
      order_number: orderNumber,
      payment_record_id: paymentRecordId,
      external_reference: externalReference,
      checkout_url: paymentRow.checkout_url,
      amount: amount,
      currency_id: currencyId,
      expires_at: paymentRow.preference_expires_at,
    });
  }

  // Validación estricta de ambiente: MERCADO_PAGO_ENV vs order_payments.environment
  let configuredEnv: "test" | "production";
  try {
    configuredEnv = readMercadoPagoEnvironment();
  } catch (envError) {
    console.error("Mercado Pago environment configuration error", {
      order_id: orderId,
      error: envError instanceof Error ? envError.message : "invalid_environment",
    });
    return jsonResponse(
      {
        ok: false,
        error: "server_misconfigured",
        message: "El ambiente de Mercado Pago no está configurado correctamente en el servidor.",
      },
      500,
    );
  }
  const paymentEnv = paymentRow.environment?.trim().toLowerCase();

  if (!paymentEnv || (paymentEnv !== "test" && paymentEnv !== "production")) {
    return jsonResponse(
      {
        ok: false,
        error: "invalid_payment_environment",
        message: "El ambiente registrado en el intento de pago no es válido.",
      },
      500,
    );
  }

  if (configuredEnv !== paymentEnv) {
    console.error("Payment environment mismatch", {
      configured_env: configuredEnv,
      payment_env: paymentEnv,
      order_id: orderId,
    });
    return jsonResponse(
      {
        ok: false,
        error: "PAYMENT_ENVIRONMENT_MISMATCH",
        message: "El entorno de pago no coincide con la configuración del servidor.",
      },
      409,
    );
  }

  // Requerir credencial real de Mercado Pago sin fallback mock
  const mpToken = Deno.env.get("MERCADO_PAGO_ACCESS_TOKEN")?.trim();
  if (!mpToken) {
    return jsonResponse(
      {
        ok: false,
        error: "server_misconfigured",
        message: "Credencial de pasarela de pago (MERCADO_PAGO_ACCESS_TOKEN) no configurada en el servidor.",
      },
      500,
    );
  }

  const expirationDate = new Date(Date.now() + 30 * 60 * 1000).toISOString();
  let prefId: string | null = null;
  let checkoutUrl: string | null = null;

  // Claim DB-backed: solo un request puede pasar de created -> pending sin preference.
  // Los demás no llaman a Mercado Pago; esperan una preference persistida o fallan temporalmente.
  const { data: claimedPayment, error: claimError } = await adminClient
    .from("order_payments")
    .update({
      status: "pending",
      status_detail: "preference_creation_in_progress",
      updated_at: new Date().toISOString(),
    })
    .eq("id", paymentRecordId)
    .eq("order_id", orderId)
    .eq("status", "created")
    .is("preference_id", null)
    .is("checkout_url", null)
    .select("id, environment, status, amount, external_reference, preference_id, checkout_url, preference_expires_at")
    .maybeSingle<PaymentRecord>();

  if (claimError) {
    console.error("Payment preference claim failed", {
      payment_record_id: paymentRecordId,
      order_id: orderId,
      error: claimError.message,
    });
    return jsonResponse(
      {
        ok: false,
        error: "preference_claim_failed",
        message: "No fue posible preparar la sesión de pago. Intenta nuevamente.",
      },
      500,
    );
  }

  if (!claimedPayment) {
    const concurrentPayment = await waitForConcurrentPreference(adminClient, orderId);
    if (concurrentPayment?.checkout_url) {
      return jsonResponse({
        ok: true,
        already_paid: false,
        reuse_preference: true,
        order_id: orderId,
        order_number: orderNumber,
        payment_record_id: concurrentPayment.id,
        external_reference: externalReference,
        checkout_url: concurrentPayment.checkout_url,
        amount: amount,
        currency_id: currencyId,
        expires_at: concurrentPayment.preference_expires_at,
      });
    }

    return jsonResponse(
      {
        ok: false,
        error: "preference_creation_in_progress",
        message: "Ya se está creando una sesión de pago para esta cotización. Intenta nuevamente en unos segundos.",
      },
      409,
    );
  }

  try {
    const prefRes = await fetchWithTimeout(
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
              id: orderId,
              title: `Servicio Go Medical - ${orderNumber}`,
              quantity: 1,
              unit_price: Number(amount.toFixed(2)),
              currency_id: "MXN",
            },
          ],
          external_reference: externalReference,
          expires: true,
          expiration_date_from: new Date().toISOString(),
          expiration_date_to: expirationDate,
        }),
      },
      10000,
    );

    const prefData = await parseJsonResponse(prefRes);
    if (prefRes.ok && isRecord(prefData)) {
      if (typeof prefData.id === "string") prefId = prefData.id;
      if (typeof prefData.init_point === "string") checkoutUrl = prefData.init_point;
    } else {
      console.error("Mercado Pago preference API failed", {
        status: prefRes.status,
        error: isRecord(prefData) ? getString(prefData, "message") ?? getString(prefData, "error") : null,
      });
      await releasePreferenceClaim(adminClient, paymentRecordId, "mercado_pago_preference_error");
      return jsonResponse(
        {
          ok: false,
          error: "mercado_pago_preference_error",
          message: "No fue posible generar la sesión de pago con Mercado Pago.",
        },
        502,
      );
    }
  } catch (prefErr) {
    console.error("Error connecting to Mercado Pago preference API", {
      order_id: orderId,
      error: prefErr instanceof Error ? prefErr.message : String(prefErr),
    });
    await releasePreferenceClaim(adminClient, paymentRecordId, "mercado_pago_network_error");
    return jsonResponse(
      {
        ok: false,
        error: "mercado_pago_network_error",
        message: "Error de conexión al comunicarse con Mercado Pago.",
      },
      502,
    );
  }

  if (!prefId || !checkoutUrl) {
    await releasePreferenceClaim(adminClient, paymentRecordId, "invalid_mercado_pago_response");
    return jsonResponse(
      {
        ok: false,
        error: "invalid_mercado_pago_response",
        message: "Respuesta incompleta devuelta por la pasarela de pagos.",
      },
      502,
    );
  }

  // 7. Actualizar order_payments con la preferencia creada (Fail-Closed y Concurrencia segura)
  const { data: updatedPayment, error: updateErr } = await adminClient
    .from("order_payments")
    .update({
      preference_id: prefId,
      checkout_url: checkoutUrl,
      preference_expires_at: expirationDate,
      updated_at: new Date().toISOString(),
    })
    .eq("id", paymentRecordId)
    .eq("order_id", orderId)
    .eq("status", "pending")
    .is("preference_id", null)
    .select("id, preference_id, checkout_url, preference_expires_at")
    .maybeSingle();

  if (updateErr || !updatedPayment) {
    console.warn("Direct update on payment record failed or superseded, checking concurrent payment", {
      payment_record_id: paymentRecordId,
      order_id: orderId,
      error: updateErr?.message,
    });

    // Re-evaluar si otro worker concurrente persistió una preferencia válida para esta orden
    const { data: fallbackPayment } = await adminClient
      .from("order_payments")
      .select("id, preference_id, checkout_url, preference_expires_at")
      .eq("order_id", orderId)
      .not("preference_id", "is", null)
      .gt("preference_expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (fallbackPayment && fallbackPayment.checkout_url) {
      return jsonResponse({
        ok: true,
        already_paid: false,
        reuse_preference: true,
        order_id: orderId,
        order_number: orderNumber,
        payment_record_id: fallbackPayment.id,
        external_reference: externalReference,
        checkout_url: fallbackPayment.checkout_url,
        amount: amount,
        currency_id: currencyId,
        expires_at: fallbackPayment.preference_expires_at,
      });
    }

    // Fail-closed si no se pudo persistir la preferencia en BD
    return jsonResponse(
      {
        ok: false,
        error: "preference_persistence_failed",
        message: "No fue posible persistir la sesión de pago. Por favor intenta nuevamente.",
      },
      500,
    );
  }

  return jsonResponse({
    ok: true,
    already_paid: false,
    reuse_preference: false,
    order_id: orderId,
    order_number: orderNumber,
    payment_record_id: paymentRecordId,
    external_reference: externalReference,
    checkout_url: checkoutUrl,
    amount: amount,
    currency_id: currencyId,
    expires_at: expirationDate,
  });
});
