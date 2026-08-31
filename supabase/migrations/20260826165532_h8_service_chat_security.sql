BEGIN;
-- ============================================================
-- H8 SECURITY
-- Chat entre cliente y técnico asignado.
-- ============================================================

DROP POLICY IF EXISTS technician_read_assigned_ticket_public_messages
ON public.service_ticket_messages;
CREATE POLICY technician_read_assigned_ticket_public_messages
ON public.service_ticket_messages
FOR SELECT
TO authenticated
USING (
    COALESCE(is_internal, false) = false
    AND EXISTS (
        SELECT 1
        FROM public.service_tickets t
        WHERE t.id = service_ticket_messages.ticket_id
          AND t.assigned_technician_id = auth.uid()
    )
);
DROP POLICY IF EXISTS technician_insert_assigned_ticket_public_messages
ON public.service_ticket_messages;
CREATE POLICY technician_insert_assigned_ticket_public_messages
ON public.service_ticket_messages
FOR INSERT
TO authenticated
WITH CHECK (
    sender_profile_id = auth.uid()
    AND sender_type = 'staff'
    AND COALESCE(is_internal, false) = false
    AND EXISTS (
        SELECT 1
        FROM public.service_tickets t
        WHERE t.id = service_ticket_messages.ticket_id
          AND t.assigned_technician_id = auth.uid()
    )
);
-- ============================================================
-- RPC de cotizaciones/pagos:
-- las cuatro requieren usuario autenticado de todas formas.
-- Quitamos acceso innecesario a anon.
-- ============================================================

REVOKE EXECUTE ON FUNCTION
public.create_service_quote(uuid, jsonb, date, text, boolean)
FROM anon;
REVOKE EXECUTE ON FUNCTION
public.send_service_quote(uuid)
FROM anon;
REVOKE EXECUTE ON FUNCTION
public.respond_to_quote(uuid, boolean)
FROM anon;
REVOKE EXECUTE ON FUNCTION
public.prepare_quote_order(uuid, text)
FROM anon;
-- Reafirmar acceso de usuarios autenticados.
GRANT EXECUTE ON FUNCTION
public.create_service_quote(uuid, jsonb, date, text, boolean)
TO authenticated;
GRANT EXECUTE ON FUNCTION
public.send_service_quote(uuid)
TO authenticated;
GRANT EXECUTE ON FUNCTION
public.respond_to_quote(uuid, boolean)
TO authenticated;
GRANT EXECUTE ON FUNCTION
public.prepare_quote_order(uuid, text)
TO authenticated;
COMMIT;
