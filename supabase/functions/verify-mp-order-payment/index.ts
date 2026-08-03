// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

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

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: JSON_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  try {
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const supabaseAnonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const accessToken = requiredEnv("MERCADO_PAGO_ACCESS_TOKEN");

    // Cliente del usuario para verificar autenticación y propiedad
    const supabaseUserClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const { data: { user }, error: userError } = await supabaseUserClient.auth.getUser();
    if (userError || !user) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const body = await request.json().catch(() => ({}));
    const orderId = body.order_id?.toString()?.trim();

    if (!orderId) {
      return jsonResponse({ error: "missing_order_id" }, 400);
    }

    // Cliente admin para consultar la BD
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Obtener perfil y client_id del usuario
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("client_id")
      .eq("id", user.id)
      .maybeSingle();

    const userClientId = profile?.client_id ?? user.id;

    // Obtener la orden y verificar propiedad
    const { data: order, error: orderError } = await supabaseAdmin
      .from("orders")
      .select("id, client_id, status, payment_status, total")
      .eq("id", orderId)
      .maybeSingle();

    if (orderError || !order) {
      return jsonResponse({ error: "order_not_found" }, 404);
    }

    if (order.client_id !== user.id && order.client_id !== userClientId) {
      return jsonResponse({ error: "forbidden" }, 403);
    }

    // Si la orden ya está pagada en la BD, responder inmediatamente
    if (order.payment_status === "approved" || order.status === "paid") {
      return jsonResponse({
        order_id: order.id,
        payment_status: "approved",
        order_status: order.status,
        confirmed: true,
      });
    }

    // Buscar la referencia de pago asociada en order_payments
    const { data: orderPayment } = await supabaseAdmin
      .from("order_payments")
      .select("external_reference, environment")
      .eq("order_id", order.id)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!orderPayment || !orderPayment.external_reference) {
      return jsonResponse({
        order_id: order.id,
        payment_status: order.payment_status ?? "pending",
        order_status: order.status,
        confirmed: false,
      });
    }

    const externalRef = orderPayment.external_reference.trim();

    // Consultar a la API de Mercado Pago por external_reference
    const mpSearchUrl = `https://api.mercadopago.com/v1/payments/search?external_reference=${encodeURIComponent(externalRef)}&sort=date_created&criteria=desc`;
    const mpResponse = await fetch(mpSearchUrl, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
      },
    });

    if (!mpResponse.ok) {
      return jsonResponse({
        order_id: order.id,
        payment_status: order.payment_status ?? "pending",
        order_status: order.status,
        confirmed: false,
      });
    }

    const searchData = await mpResponse.json();
    const results = Array.isArray(searchData.results) ? searchData.results : [];

    // Buscar pago aprobado coincidente
    const approvedPayment = results.find(
      (p) =>
        p.external_reference === externalRef &&
        (p.status === "approved" || p.status_detail === "accredited") &&
        Math.abs((p.transaction_amount ?? 0) - Number(order.total)) < 0.05,
    );

    if (approvedPayment) {
      // Conciliar mediante RPC
      const { error: rpcError } = await supabaseAdmin.rpc(
        "reconcile_mercado_pago_payment",
        {
          p_payment_id: String(approvedPayment.id),
          p_external_reference: externalRef,
          p_status: approvedPayment.status ?? "approved",
          p_status_detail: approvedPayment.status_detail ?? "accredited",
          p_amount: approvedPayment.transaction_amount ?? order.total,
          p_currency_id: approvedPayment.currency_id ?? "MXN",
          p_payment_method_id: approvedPayment.payment_method_id ?? null,
          p_payment_type_id: approvedPayment.payment_type_id ?? null,
          p_installments: approvedPayment.installments ?? null,
          p_live_mode: approvedPayment.live_mode === true,
          p_date_approved: approvedPayment.date_approved ?? null,
          p_provider_created_at: approvedPayment.date_created ?? null,
          p_provider_updated_at: approvedPayment.date_last_updated ?? null,
          p_raw_metadata: { source: "manual_verification" },
        },
      );

      if (!rpcError) {
        return jsonResponse({
          order_id: order.id,
          payment_status: "approved",
          order_status: "paid",
          confirmed: true,
        });
      }
    }

    // Si hay algún pago rechazado o pendiente reciente
    const latestPayment = results[0];
    const finalPaymentStatus = latestPayment
      ? (latestPayment.status ?? "pending")
      : (order.payment_status ?? "pending");

    return jsonResponse({
      order_id: order.id,
      payment_status: finalPaymentStatus,
      order_status: order.status,
      confirmed: finalPaymentStatus === "approved",
    });
  } catch (error) {
    return jsonResponse(
      { error: "internal_server_error", message: error instanceof Error ? error.message : "unknown" },
      500,
    );
  }
});
