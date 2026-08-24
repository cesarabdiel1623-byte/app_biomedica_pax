-- ==============================================================================
-- Migración: 20260814040000_t4_3_backfill_legacy_completed_clients.sql
-- Objetivo: Backfill determinista para clientes legacy con actividad real comprobada
-- ==============================================================================

-- 1. Sincronizar full_name en profiles si está vacío o 'Sin especificar' pero el cliente tiene contact_name válido
UPDATE public.profiles p
SET full_name = btrim(c.contact_name),
    updated_at = now()
FROM public.clients c
WHERE p.client_id = c.id
  AND (p.role = 'client' OR p.role IS NULL)
  AND (p.full_name IS NULL OR btrim(p.full_name) = '' OR p.full_name = 'Sin especificar')
  AND (c.contact_name IS NOT NULL AND btrim(c.contact_name) <> '' AND c.contact_name <> 'Sin especificar')
  AND (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.client_id = c.id)
    OR EXISTS (SELECT 1 FROM public.client_addresses ca WHERE ca.client_id = c.id)
  );
-- 2. Marcar profile_completed = true ÚNICAMENTE para clientes con actividad real comprobada (órdenes o direcciones)
-- NOTA: NO se inventa terms_accepted_at, terms_version ni phone_skipped_at. Permanecen NULL si no existen.
UPDATE public.clients c
SET profile_completed = true,
    updated_at = now()
FROM public.profiles p
WHERE p.client_id = c.id
  AND (p.role = 'client' OR p.role IS NULL)
  AND (c.profile_completed = false OR c.profile_completed IS NULL)
  AND (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.client_id = c.id)
    OR EXISTS (SELECT 1 FROM public.client_addresses ca WHERE ca.client_id = c.id)
  );
