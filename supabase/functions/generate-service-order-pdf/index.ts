import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  renderServiceOrderPdf,
  ServiceOrderPdfData,
  resolveServiceAddress,
} from "../_shared/service_order_pdf_engine.ts";

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

function isUuidLike(value: string): boolean {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(
    value,
  );
}

function parseLegacyDescription(text?: string | null): Record<string, string> {
  if (!text || !text.includes("=== INFORMACIÓN DEL EQUIPO ===")) return {};
  const result: Record<string, string> = {};

  const matches = text.matchAll(/===\s*([^=]+?)\s*===\s*([\s\S]*?)(?=\n===|$)/g);
  for (const m of matches) {
    const title = m[1]?.trim();
    const body = m[2]?.trim();
    if (!title || !body) continue;

    for (const rawLine of body.split("\n")) {
      const line = rawLine.replace(/^\s*[•\-]\s*/, "").trim();
      if (!line || !line.includes(":")) continue;
      const colon = line.indexOf(":");
      const k = line.substring(0, colon).trim();
      const v = line.substring(colon + 1).trim();
      if (k && v) {
        result[k] = v;
      }
    }

    if (title.toLowerCase().includes("descripción")) {
      result["__description__"] = body;
    }
  }

  return result;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: JSON_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const token = authHeader.replace("Bearer ", "").trim();
    if (!token) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const supabaseAnonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

    // 1. Authenticate user
    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return jsonResponse({ error: "unauthorized", message: "Invalid session" }, 401);
    }

    // 2. Parse request body
    let requestJson: Record<string, unknown>;
    try {
      requestJson = await request.json();
    } catch {
      return jsonResponse({ error: "invalid_request", message: "Invalid JSON body" }, 400);
    }

    const ticketId = typeof requestJson.ticket_id === "string" ? requestJson.ticket_id.trim() : null;
    if (!ticketId || !isUuidLike(ticketId)) {
      return jsonResponse({ error: "invalid_request", message: "Valid ticket_id is required" }, 400);
    }

    const documentType = typeof requestJson.document_type === "string" && requestJson.document_type.toLowerCase() === "final"
      ? "final"
      : "preliminary";

    // 3. Admin client for DB queries and storage operations
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // 4. Check profile & role
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("id, role, client_id, is_active")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError || !profile) {
      return jsonResponse({ error: "forbidden", message: "Profile not found" }, 403);
    }

    const isStaffOrAdmin = (profile.role === "admin" || profile.role === "staff") && profile.is_active === true;

    // 5. Fetch ticket with client information
    const { data: ticket, error: ticketError } = await supabaseAdmin
      .from("service_tickets")
      .select(`
        id,
        ticket_number,
        title,
        client_id,
        equipment_name,
        equipment_brand,
        equipment_model,
        serial_number,
        equipment_operating,
        type,
        institution,
        department,
        failure_description,
        description,
        contact_name,
        contact_phone,
        contact_email,
        service_address,
        service_city,
        service_state,
        service_region,
        service_location,
        created_at,
        clients (
          id,
          business_name,
          trade_name
        )
      `)
      .eq("id", ticketId)
      .maybeSingle();

    if (ticketError || !ticket) {
      return jsonResponse({ error: "ticket_not_found", message: "Ticket does not exist" }, 404);
    }

    // 6. Verify Ownership or Staff/Admin
    const isOwner = profile.client_id != null && profile.client_id === ticket.client_id;
    if (!isOwner && !isStaffOrAdmin) {
      return jsonResponse({ error: "forbidden", message: "Access denied to this ticket" }, 403);
    }

    // 7. If document_type === 'final', fetch service_orders details
    let completedAt: string | undefined = undefined;
    let workPerformedFormatted: string | null = null;
    let observationsFormatted: string | null = null;
    let selectedServiceOrderId: string | null = null;

    if (documentType === "final") {
      const { data: serviceOrder, error: orderError } = await supabaseAdmin
        .from("service_orders")
        .select("id, diagnosis, solution, recommendations, completed_at, status")
        .eq("service_ticket_id", ticketId)
        .order("completed_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (orderError || !serviceOrder || !serviceOrder.completed_at) {
        return jsonResponse({
          error: "service_order_not_completed",
          message: "No se puede generar la orden final porque el servicio no ha sido completado.",
        }, 400);
      }

      selectedServiceOrderId = serviceOrder.id;
      completedAt = serviceOrder.completed_at;
      const diag = serviceOrder.diagnosis?.trim() ?? "";
      const sol = serviceOrder.solution?.trim() ?? "";
      workPerformedFormatted = `DIAGNÓSTICO:\n${diag}\n\nTRABAJO REALIZADO:\n${sol}`.trim();
      observationsFormatted = serviceOrder.recommendations?.trim() || null;
    }

    // 8. Extract & Normalize PDF Data
    const legacyMap = parseLegacyDescription(ticket.description);
    const hasStructured = ticket.equipment_name || ticket.equipment_brand || ticket.equipment_model ||
      ticket.serial_number || ticket.institution || ticket.failure_description || ticket.equipment_operating !== null;

    let equipmentName = ticket.equipment_name;
    let equipmentBrand = ticket.equipment_brand;
    let equipmentModel = ticket.equipment_model;
    let serialNumber = ticket.serial_number;
    let institution = ticket.institution;
    let failureDescription = ticket.failure_description;
    let equipmentOperating = ticket.equipment_operating;

    // Legacy fallback if structured columns are empty
    if (!hasStructured && Object.keys(legacyMap).length > 0) {
      equipmentName = legacyMap["Nombre"] || legacyMap["Equipo"] || ticket.title;
      equipmentBrand = legacyMap["Marca"];
      equipmentModel = legacyMap["Modelo"];
      serialNumber = legacyMap["Número de serie"] || legacyMap["Serie"];
      institution = legacyMap["Institución"] || legacyMap["Clínica"];
      failureDescription = legacyMap["__description__"] || ticket.description;

      const enc = (legacyMap["¿El equipo enciende?"] || "").toLowerCase();
      if (enc.startsWith("s") || enc === "si" || enc === "sí" || enc === "true") {
        equipmentOperating = true;
      } else if (enc.startsWith("n") || enc === "no" || enc === "false") {
        equipmentOperating = false;
      }
    }

    if (!failureDescription && ticket.description) {
      failureDescription = ticket.description;
    }

    const clientRecord = Array.isArray(ticket.clients) ? ticket.clients[0] : ticket.clients;
    const clientName = clientRecord?.business_name || clientRecord?.trade_name || ticket.contact_name;

    const resolvedAddress = resolveServiceAddress(ticket.service_address, ticket.service_location);

    const pdfData: ServiceOrderPdfData = {
      ticketNumber: ticket.ticket_number,
      createdAt: ticket.created_at,
      completedAt: completedAt,

      equipmentName: equipmentName ?? null,
      equipmentBrand: equipmentBrand ?? null,
      equipmentModel: equipmentModel ?? null,
      serialNumber: serialNumber ?? null,

      serviceType: ticket.type,
      equipmentOperating: equipmentOperating ?? null,

      clientName: clientName ?? null,
      address: resolvedAddress || null,
      city: ticket.service_city ?? null,
      state: ticket.service_state ?? null,
      phone: ticket.contact_phone ?? null,
      email: ticket.contact_email ?? null,
      institution: institution ?? null,

      // Conserve the customer's reported failure description intact in its designated block
      failureDescription: failureDescription ?? null,

      // Combined diagnosis and work performed for final order; null for preliminary order
      workPerformed: workPerformedFormatted,
      observations: observationsFormatted,
      technicianSignature: null,
      clientSignature: null,
      advisorSignature: null,
    };

    // 9. Download private template
    const { data: templateBlob, error: templateError } = await supabaseAdmin.storage
      .from("service-reports")
      .download("templates/orden_servicio_base.pdf");

    if (templateError || !templateBlob) {
      console.error("Failed to download template:", templateError);
      return jsonResponse({ error: "template_not_found", message: "Official template could not be loaded" }, 500);
    }

    const templateBuffer = new Uint8Array(await templateBlob.arrayBuffer());

    // 10. Render PDF
    let pdfBytes: Uint8Array;
    try {
      pdfBytes = await renderServiceOrderPdf(templateBuffer, pdfData);
    } catch (renderError) {
      console.error("PDF generation failed:", renderError);
      return jsonResponse({ error: "pdf_generation_failed", message: "Failed to render PDF" }, 500);
    }

    // 11. Save to Storage (idempotent upsert)
    const fileName = documentType === "final" ? "orden_servicio_final.pdf" : "orden_servicio_preliminar.pdf";
    const storagePath = `orders/${ticket.id}/${fileName}`;
    const { error: uploadError } = await supabaseAdmin.storage
      .from("service-reports")
      .upload(storagePath, pdfBytes, {
        contentType: "application/pdf",
        upsert: true,
      });

    if (uploadError) {
      console.error("Storage upload failed:", uploadError);
      return jsonResponse({ error: "storage_upload_failed", message: "Failed to store PDF document" }, 500);
    }

    // 12. Generate Signed URL (3600 seconds)
    const { data: signedData, error: signedError } = await supabaseAdmin.storage
      .from("service-reports")
      .createSignedUrl(storagePath, 3600);

    if (signedError || !signedData?.signedUrl) {
      console.error("Signed URL creation failed:", signedError);
      return jsonResponse({ error: "signed_url_failed", message: "Failed to generate download link" }, 500);
    }

    // Si es final, actualizar report_pdf_path en service_orders
    if (documentType === "final" && selectedServiceOrderId) {
      await supabaseAdmin
        .from("service_orders")
        .update({ report_pdf_path: storagePath })
        .eq("id", selectedServiceOrderId);
    }

    return jsonResponse({
      ok: true,
      document_type: documentType,
      ticket_number: ticket.ticket_number,
      path: storagePath,
      signed_url: signedData.signedUrl,
      expires_in: 3600,
    });
  } catch (err) {
    console.error("Unhandled error in generate-service-order-pdf:", err);
    return jsonResponse({ error: "internal_error", message: "An unexpected error occurred" }, 500);
  }
});
