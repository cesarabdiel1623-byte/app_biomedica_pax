-- FASE T1.3: HARDENING DE PERMISOS DE TRACKING Y PROTECCIÓN DE DATOS SENSIBLES (LOCAL - SIN EJECUTAR EN CLOUD)
-- Nombre de migración: 20260807151000_t1_3_harden_tracking_privileges.sql
-- Propósito: Revocar privilegios amplios directos sobre tablas base de envíos y limitar el rol authenticated a selección por columnas públicas y vistas seguras.

BEGIN;

-- 1. REVOCAR TODOS LOS PRIVILEGIOS DIRECTOS EXISTENTES EN TABLAS BASE PARA ROLES NO ADMINISTRATIVOS
REVOKE ALL PRIVILEGES ON TABLE public.order_shipments FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.shipment_events FROM authenticated;

REVOKE ALL PRIVILEGES ON TABLE public.order_shipments FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.shipment_events FROM anon;

REVOKE ALL PRIVILEGES ON TABLE public.order_shipments FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.shipment_events FROM PUBLIC;

-- 2. CONSERVAR Y GARANTIZAR ACCESO COMPLETO EXCLUSIVO PARA SERVICE_ROLE (Edge Functions / Webhooks)
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.order_shipments TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.shipment_events TO service_role;

-- 3. OTORGAR ÚNICAMENTE SELECT SOBRE COLUMNAS PÚBLICAS NO SENSIBLES A AUTHENTICATED
-- (Se excluyen explícitamente: label_url y skydropx_shipment_id)
GRANT SELECT (
  id,
  order_id,
  carrier,
  service_name,
  tracking_number,
  tracking_url,
  shipping_status,
  estimated_delivery,
  created_at,
  updated_at
) ON TABLE public.order_shipments TO authenticated;

GRANT SELECT (
  id,
  shipment_id,
  status,
  description,
  location,
  event_at,
  created_at
) ON TABLE public.shipment_events TO authenticated;

-- 4. ACCESO A VISTAS SEGURAS PARA EL ROL AUTHENTICATED
GRANT SELECT ON public.customer_order_shipments TO authenticated;
GRANT SELECT ON public.customer_shipment_events TO authenticated;

REVOKE ALL ON public.customer_order_shipments FROM anon, PUBLIC;
REVOKE ALL ON public.customer_shipment_events FROM anon, PUBLIC;

COMMIT;
