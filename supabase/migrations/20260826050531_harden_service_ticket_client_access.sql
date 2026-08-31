BEGIN;
-- ============================================================
-- 1. SERVICE_TICKETS
-- Eliminar políticas legacy demasiado amplias o incorrectas.
-- ============================================================

DROP POLICY IF EXISTS "Los clientes solo pueden ver sus propios tickets"
ON public.service_tickets;
DROP POLICY IF EXISTS client_access_insert_tickets
ON public.service_tickets;
DROP POLICY IF EXISTS client_access_select_tickets
ON public.service_tickets;
-- ============================================================
-- 2. INSERT DE TICKETS
-- Cliente:
--   - solo puede crear tickets para su propio client_id
--   - requested_by debe ser su propio auth.uid()
--   - siempre inicia en open
--   - no puede autodesignar técnico ni autorizar rutas
--
-- Staff/admin conserva capacidad administrativa.
-- ============================================================

DROP POLICY IF EXISTS tickets_insert_client_or_staff
ON public.service_tickets;
CREATE POLICY tickets_insert_client_or_staff
ON public.service_tickets
FOR INSERT
TO authenticated
WITH CHECK (
    public.is_staff_or_admin()
    OR (
        client_id = public.get_my_client_id()
        AND requested_by = auth.uid()
        AND status = 'open'::public.ticket_status
        AND assigned_technician_id IS NULL
        AND assigned_technician_custom_name IS NULL
        AND scheduled_start_at IS NULL
        AND scheduled_end_at IS NULL
        AND route_required IS FALSE
        AND route_authorized IS FALSE
        AND route_notes IS NULL
    )
);
-- ============================================================
-- 3. SELECT DE TICKETS
-- Cliente ve los de su client_id.
-- Técnico ve los asignados.
-- Staff/admin ve todos.
-- ============================================================

DROP POLICY IF EXISTS tickets_select_staff_tech_or_own
ON public.service_tickets;
CREATE POLICY tickets_select_staff_tech_or_own
ON public.service_tickets
FOR SELECT
TO authenticated
USING (
    public.is_staff_or_admin()
    OR assigned_technician_id = auth.uid()
    OR client_id = public.get_my_client_id()
);
-- ============================================================
-- 4. UPDATE DE TICKETS
-- Los clientes NO modifican ejecución/cierre.
-- Solo staff/admin o técnico asignado.
-- ============================================================

DROP POLICY IF EXISTS tickets_update_staff_or_tech
ON public.service_tickets;
CREATE POLICY tickets_update_staff_or_tech
ON public.service_tickets
FOR UPDATE
TO authenticated
USING (
    public.is_staff_or_admin()
    OR assigned_technician_id = auth.uid()
)
WITH CHECK (
    public.is_staff_or_admin()
    OR assigned_technician_id = auth.uid()
);
-- ============================================================
-- 5. SERVICE_TICKET_MESSAGES
-- Quitar políticas legacy amplias.
--
-- Se mantienen las políticas modernas:
-- clients_can_insert_own_ticket_messages
-- clients_can_read_own_ticket_messages
-- staff_can_insert_ticket_messages
-- admin_staff_can_read_all_ticket_messages
-- insert_messages / select_messages
-- ============================================================

DROP POLICY IF EXISTS client_access_insert_ticket_messages
ON public.service_ticket_messages;
DROP POLICY IF EXISTS client_access_select_ticket_messages
ON public.service_ticket_messages;
-- ============================================================
-- 6. STORAGE: ticket-attachments
--
-- Eliminar políticas que permitían:
-- - cualquier authenticated subir a cualquier ruta
-- - lectura mediante role public
--
-- Se conservan las políticas nuevas que verifican ticket_id
-- contra el client_id del usuario, y las políticas de staff.
-- ============================================================

DROP POLICY IF EXISTS "Allow authenticated users to upload to ticket-attachments"
ON storage.objects;
DROP POLICY IF EXISTS "Allow public read access to ticket-attachments"
ON storage.objects;
-- Reafirmar que el bucket debe permanecer privado.
UPDATE storage.buckets
SET public = false
WHERE id = 'ticket-attachments';
COMMIT;
