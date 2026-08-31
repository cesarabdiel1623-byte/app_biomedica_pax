BEGIN;
-- ============================================================
-- H6.1 / H7 SECURITY
-- Endurecer la creación de service_tickets para clientes.
--
-- Reglas:
-- 1. Un ticket de cliente solo puede pertenecer a su client_id.
-- 2. requested_by debe ser el usuario autenticado.
-- 3. Debe iniciar en estado open.
-- 4. El cliente no puede llenar campos administrativos.
-- 5. Si usa un equipo registrado:
--      - debe pertenecer al mismo cliente;
--      - product_id debe coincidir con el producto real del equipo.
-- 6. Si usa "Otro equipo":
--      - equipment_unit_id debe ser NULL;
--      - product_id debe ser NULL.
--
-- Staff/admin conserva su flujo administrativo.
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

        -- El ticket debe pertenecer al cliente autenticado.
        client_id = public.get_my_client_id()

        -- El solicitante debe ser el usuario autenticado.
        AND requested_by = auth.uid()

        -- Todo ticket creado por cliente inicia abierto.
        AND status = 'open'::public.ticket_status

        -- Campos exclusivamente administrativos/técnicos.
        AND assigned_technician_id IS NULL
        AND assigned_technician_custom_name IS NULL
        AND scheduled_start_at IS NULL
        AND scheduled_end_at IS NULL
        AND route_required IS FALSE
        AND route_authorized IS FALSE
        AND route_notes IS NULL

        -- Integridad del equipo.
        AND (
            -- "Otro equipo": no existe unidad registrada asociada.
            (
                equipment_unit_id IS NULL
                AND product_id IS NULL
            )

            OR

            -- Equipo registrado:
            -- debe pertenecer al cliente autenticado y
            -- product_id debe coincidir con el producto real de la unidad.
            EXISTS (
                SELECT 1
                FROM public.equipment_units AS eu
                WHERE eu.id = service_tickets.equipment_unit_id
                  AND eu.current_client_id = public.get_my_client_id()
                  AND eu.product_id = service_tickets.product_id
            )
        )
    )
);
COMMIT;
