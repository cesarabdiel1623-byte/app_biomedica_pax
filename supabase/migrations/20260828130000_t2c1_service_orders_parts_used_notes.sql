-- Migration: T2C.1 / T2C.2 — Soporte de refacciones libres y notas de materiales en órdenes de servicio técnico
-- Timestamp: 20260828130000
-- Objetivo: Permitir la captura ágil y flexible de refacciones utilizadas (proceso real Go Medical)
-- sin obligar a selección de producto de catálogo, almacén o costo unitario, eliminando ambigüedad en RPC.

-- 1. Agregar columna nullable parts_used_notes en public.service_orders
ALTER TABLE public.service_orders
ADD COLUMN IF NOT EXISTS parts_used_notes text DEFAULT NULL;

-- 2. Eliminar sobrecargas previas para garantizar una ÚNICA firma canónica en PostgREST
DROP FUNCTION IF EXISTS public.complete_service_order(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.complete_service_order(uuid, text, text, text, text);

-- 3. Crear función canónica única con soporte de p_parts_used_notes DEFAULT NULL
CREATE OR REPLACE FUNCTION public.complete_service_order(
    p_service_order_id uuid,
    p_diagnosis text,
    p_solution text,
    p_recommendations text DEFAULT NULL,
    p_parts_used_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id uuid;
    v_order record;
    v_ticket record;
    v_diagnosis text := trim(p_diagnosis);
    v_solution text := trim(p_solution);
    v_recommendations text := nullif(trim(p_recommendations), '');
    v_parts_used_notes text := nullif(trim(p_parts_used_notes), '');
    v_completed_at timestamptz := now();
BEGIN
    -- 1. Autenticación y Autorización
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED: Debes iniciar sesión.' USING ERRCODE = '42501';
    END IF;

    IF p_service_order_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_SERVICE_ORDER_ID: Se requiere p_service_order_id.' USING ERRCODE = '22023';
    END IF;

    -- 2. Cargar service_order con FOR UPDATE
    SELECT *
    INTO v_order
    FROM public.service_orders
    WHERE id = p_service_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SERVICE_ORDER_NOT_FOUND: La orden de servicio no existe.' USING ERRCODE = '02000';
    END IF;

    IF NOT (public.is_staff_or_admin() OR v_order.assigned_technician_id = v_user_id) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Solo el personal administrativo o el técnico asignado pueden completar la orden.' USING ERRCODE = '42501';
    END IF;

    -- 3. Manejo de reintento idempotente si ya está finalizada
    IF v_order.status IN ('resolved'::public.ticket_status, 'closed'::public.ticket_status) THEN
        IF COALESCE(v_order.diagnosis, '') = v_diagnosis 
           AND COALESCE(v_order.solution, '') = v_solution 
           AND nullif(trim(v_order.recommendations), '') IS NOT DISTINCT FROM v_recommendations
           AND nullif(trim(v_order.parts_used_notes), '') IS NOT DISTINCT FROM v_parts_used_notes THEN
            -- Reintento idéntico: devolver datos existentes sin reescribir completed_at ni duplicar evento
            RETURN jsonb_build_object(
                'ok', true,
                'service_order_id', p_service_order_id,
                'ticket_id', v_order.service_ticket_id,
                'status', v_order.status,
                'diagnosis', v_order.diagnosis,
                'solution', v_order.solution,
                'recommendations', v_order.recommendations,
                'parts_used_notes', v_order.parts_used_notes,
                'completed_at', v_order.completed_at
            );
        ELSE
            RAISE EXCEPTION 'SERVICE_ORDER_ALREADY_COMPLETED: La orden ya fue finalizada previamente y sus datos técnicos están congelados.' USING ERRCODE = '23514';
        END IF;
    END IF;

    IF v_diagnosis IS NULL OR v_diagnosis = '' THEN
        RAISE EXCEPTION 'EMPTY_DIAGNOSIS: Se requiere el diagnóstico técnico final.' USING ERRCODE = '22023';
    END IF;

    IF v_solution IS NULL OR v_solution = '' THEN
        RAISE EXCEPTION 'EMPTY_SOLUTION: Se requiere especificar el trabajo realizado y la solución aplicada.' USING ERRCODE = '22023';
    END IF;

    -- 4. Cargar service_ticket
    SELECT *
    INTO v_ticket
    FROM public.service_tickets
    WHERE id = v_order.service_ticket_id
    FOR UPDATE;

    -- 5. Actualizar service_order
    UPDATE public.service_orders
    SET 
        diagnosis = v_diagnosis,
        solution = v_solution,
        recommendations = v_recommendations,
        parts_used_notes = v_parts_used_notes,
        status = 'resolved'::public.ticket_status,
        completed_at = v_completed_at,
        updated_at = now()
    WHERE id = p_service_order_id;

    -- 6. Actualizar service_ticket a 'resolved'
    UPDATE public.service_tickets
    SET 
        status = 'resolved'::public.ticket_status,
        updated_at = now()
    WHERE id = v_order.service_ticket_id;

    -- 7. Registrar evento si hubo transición
    INSERT INTO public.service_ticket_events (
        ticket_id,
        event_type,
        from_status,
        to_status,
        actor_profile_id
    ) VALUES (
        v_order.service_ticket_id,
        'completed',
        v_ticket.status,
        'resolved'::public.ticket_status,
        v_user_id
    );

    RETURN jsonb_build_object(
        'ok', true,
        'service_order_id', p_service_order_id,
        'ticket_id', v_order.service_ticket_id,
        'status', 'resolved',
        'diagnosis', v_diagnosis,
        'solution', v_solution,
        'recommendations', v_recommendations,
        'parts_used_notes', v_parts_used_notes,
        'completed_at', v_completed_at
    );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_service_order(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_service_order(uuid, text, text, text, text) TO authenticated;

-- 4. Actualizar trigger de inmutabilidad para proteger parts_used_notes
CREATE OR REPLACE FUNCTION public.guard_service_orders_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF OLD.status IN ('resolved'::public.ticket_status, 'closed'::public.ticket_status) THEN
        IF NEW.diagnosis IS DISTINCT FROM OLD.diagnosis THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se puede modificar el diagnóstico de una orden finalizada.' USING ERRCODE = '23514';
        END IF;

        IF NEW.solution IS DISTINCT FROM OLD.solution THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se puede modificar la solución de una orden finalizada.' USING ERRCODE = '23514';
        END IF;

        IF NEW.recommendations IS DISTINCT FROM OLD.recommendations THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se pueden modificar las recomendaciones de una orden finalizada.' USING ERRCODE = '23514';
        END IF;

        IF NEW.parts_used_notes IS DISTINCT FROM OLD.parts_used_notes THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se pueden modificar las refacciones de una orden finalizada.' USING ERRCODE = '23514';
        END IF;

        IF NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se puede modificar la fecha de finalización.' USING ERRCODE = '23514';
        END IF;

        IF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se puede modificar la fecha de inicio.' USING ERRCODE = '23514';
        END IF;

        IF NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se puede modificar la fecha programada en orden finalizada.' USING ERRCODE = '23514';
        END IF;

        IF NEW.assigned_technician_id IS DISTINCT FROM OLD.assigned_technician_id THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se puede modificar el técnico en una orden finalizada.' USING ERRCODE = '23514';
        END IF;

        IF NEW.service_ticket_id IS DISTINCT FROM OLD.service_ticket_id THEN
            RAISE EXCEPTION 'IMMUTABLE_SERVICE_ORDER: No se puede reasignar el ticket de la orden.' USING ERRCODE = '23514';
        END IF;

        IF NEW.status IS DISTINCT FROM OLD.status THEN
            IF NOT (OLD.status = 'resolved'::public.ticket_status AND NEW.status = 'closed'::public.ticket_status) THEN
                RAISE EXCEPTION 'INVALID_STATUS_TRANSITION: Una orden finalizada solo puede pasar de resolved a closed.' USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
