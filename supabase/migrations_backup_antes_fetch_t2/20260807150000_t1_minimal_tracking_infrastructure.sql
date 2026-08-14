-- FASE T1.2: INFRAESTRUCTURA MÍNIMA DE TRACKING Y SEGUIMIENTO LOGÍSTICO (LOCAL - SIN EJECUTAR EN CLOUD)
-- Nombre de migración: 20260816000000_t1_minimal_tracking_infrastructure.sql
-- Propósito: Definir la estructura normalizada de envíos, soporte multipaquete, eventos de rastreo, trigger updated_at y vistas seguras RLS.

BEGIN;

-- 1. TABLA DE ENVÍOS VINCULADA A ORDERS (Sin restricción UNIQUE para admitir múltiples paquetes futuros)
CREATE TABLE IF NOT EXISTS public.order_shipments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  skydropx_shipment_id TEXT,
  carrier TEXT,
  service_name TEXT,
  tracking_number TEXT,
  tracking_url TEXT,
  label_url TEXT,
  shipping_status TEXT DEFAULT 'pending',
  estimated_delivery TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. TABLA DE EVENTOS DE RASTREO HISTÓRICOS
CREATE TABLE IF NOT EXISTS public.shipment_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id UUID NOT NULL REFERENCES public.order_shipments(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  description TEXT,
  location TEXT,
  event_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexación de consultas frecuentes por orden e historial
CREATE INDEX IF NOT EXISTS idx_order_shipments_order_id ON public.order_shipments(order_id);
CREATE INDEX IF NOT EXISTS idx_shipment_events_shipment_id ON public.shipment_events(shipment_id);

-- 3. TRIGGER PARA ACTUALIZAR UPDATED_AT EN ORDER_SHIPMENTS
CREATE OR REPLACE FUNCTION public.set_order_shipment_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_shipment_updated_at ON public.order_shipments;
CREATE TRIGGER trg_order_shipment_updated_at
  BEFORE UPDATE ON public.order_shipments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_order_shipment_updated_at();

-- 4. POLÍTICAS DE SEGURIDAD (RLS) BASADAS EXCLUSIVAMENTE EN GET_MY_CLIENT_ID()
ALTER TABLE public.order_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_events ENABLE ROW LEVEL SECURITY;

-- Política RLS para order_shipments validando estrictamente la identidad del cliente vía get_my_client_id()
CREATE POLICY order_shipments_select_own ON public.order_shipments
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_shipments.order_id 
        AND o.client_id = public.get_my_client_id()
    )
  );

-- Política RLS para shipment_events transitiva por la orden
CREATE POLICY shipment_events_select_own ON public.shipment_events
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.order_shipments s
      JOIN public.orders o ON o.id = s.order_id
      WHERE s.id = shipment_events.shipment_id 
        AND o.client_id = public.get_my_client_id()
    )
  );

-- Permisos de lectura/escritura completos para service_role (Edge Functions / Webhooks)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_shipments TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shipment_events TO service_role;

-- Permisos restringidos a nivel de columna para rol authenticated (Previene lectura de label_url y skydropx_shipment_id al usar security_invoker = true)
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
) ON public.order_shipments TO authenticated;

GRANT SELECT (
  id,
  shipment_id,
  status,
  description,
  location,
  event_at,
  created_at
) ON public.shipment_events TO authenticated;

-- Revocar accesos anónimos
REVOKE ALL ON public.order_shipments FROM anon;
REVOKE ALL ON public.shipment_events FROM anon;

-- 5. VISTAS SEGURAS PARA LA APLICACIÓN FLUTTER (Security Invoker, sin label_url ni skydropx_shipment_id)
CREATE OR REPLACE VIEW public.customer_order_shipments
WITH (security_invoker = true) AS
SELECT 
  s.id,
  s.order_id,
  s.carrier,
  s.service_name,
  s.tracking_number,
  s.tracking_url,
  s.shipping_status,
  s.estimated_delivery,
  s.created_at,
  s.updated_at
FROM public.order_shipments s;

CREATE OR REPLACE VIEW public.customer_shipment_events
WITH (security_invoker = true) AS
SELECT 
  e.id,
  e.shipment_id,
  e.status,
  e.description,
  e.location,
  e.event_at,
  e.created_at
FROM public.shipment_events e;

GRANT SELECT ON public.customer_order_shipments TO authenticated;
GRANT SELECT ON public.customer_shipment_events TO authenticated;

COMMIT;
