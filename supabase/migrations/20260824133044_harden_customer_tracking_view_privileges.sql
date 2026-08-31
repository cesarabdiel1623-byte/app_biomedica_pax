-- Hardening de las vistas de seguimiento para clientes.
-- Los usuarios autenticados solo necesitan consultar sus propios envíos.
-- security_invoker + RLS de las tablas base mantienen el aislamiento por cliente.

REVOKE ALL ON public.customer_order_shipments
FROM authenticated, anon, PUBLIC;
GRANT SELECT ON public.customer_order_shipments
TO authenticated;
REVOKE ALL ON public.customer_shipment_events
FROM authenticated, anon, PUBLIC;
GRANT SELECT ON public.customer_shipment_events
TO authenticated;
