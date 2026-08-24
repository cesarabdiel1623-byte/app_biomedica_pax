-- ============================================================================
-- MIGRACIÓN T2C: HARDENING BACKEND DE EJECUCIÓN TÉCNICA Y CIERRE DE SERVICIO
-- Timestamp: 20260819140000_t2c_service_execution_hardening.sql
-- ============================================================================
-- 1. register_service_part_usage: Lock concurrente de stock (product_inventory FOR UPDATE),
--    validación canónica de stock disponible (current_stock - active_reservations >= quantity),
--    descuento explícito de current_stock (alineado con admin_fulfill/register),
--    y registro en service_parts_used + inventory_movements.
-- 2. start_service_order: Advisory lock por ticket, validación post-pago,
--    fail-closed si existen múltiples órdenes activas, preservación de started_at en reintentos,
--    protección contra reasignación no autorizada entre técnicos y control de eventos duplicados.
-- 3. complete_service_order: Idempotencia estricta comparando diagnosis, solution y recommendations,
--    sin reescribir completed_at ni duplicar eventos en reintentos.
-- 4. close_service_ticket: Idempotencia sobre tickets ya cerrados, validación de orden completada
--    y persistencia de p_reason en service_ticket_events.
-- 5. guard_service_orders_immutability: Trigger que congela diagnosis, solution, recommendations,
--    completed_at, started_at, scheduled_at, technician_id y ticket_id en órdenes resueltas/cerradas.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. HARDENING DE register_service_part_usage (STOCK SEGURO Y CONCURRENTE)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_service_part_usage(
    p_service_order_id uuid,
    p_product_id uuid,
    p_warehouse_id uuid,
    p_quantity numeric,
    p_unit_cost numeric DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_order record;
    v_inventory public.product_inventory%rowtype;
    v_previous numeric;
    v_resulting numeric;
    v_reserved_stock numeric := 0;
    v_available_stock numeric;
    v_typed_movement public.inventory_movements%rowtype;
    v_inventory_has_warehouse boolean := false;
    v_reservations_table_exists boolean := false;
    v_reservations_has_warehouse boolean := false;
BEGIN
    -- 1. Autorización
    IF NOT public.is_technician_or_admin() THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: No autorizado.' USING ERRCODE = '42501';
    END IF;

    -- 2. Validaciones de entrada
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: La cantidad debe ser mayor a 0.' USING ERRCODE = '22023';
    END IF;

    IF p_product_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_PRODUCT_ID: Se requiere p_product_id.' USING ERRCODE = '22023';
    END IF;

    IF p_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_WAREHOUSE_ID: Se requiere p_warehouse_id.' USING ERRCODE = '22023';
    END IF;

    -- 3. Validar que la orden de servicio existe y está en ejecución activa
    SELECT id, status INTO v_order
    FROM public.service_orders
    WHERE id = p_service_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SERVICE_ORDER_NOT_FOUND: La orden de servicio no existe.' USING ERRCODE = '02000';
    END IF;

    IF v_order.status IN ('resolved'::public.ticket_status, 'closed'::public.ticket_status, 'cancelled'::public.ticket_status) THEN
        RAISE EXCEPTION 'INVALID_ORDER_STATUS: No se pueden registrar refacciones en una orden finalizada o cancelada (%).', v_order.status USING ERRCODE = '23514';
    END IF;

    -- 4. Validar existencia del almacén
    PERFORM 1 FROM public.warehouses WHERE id = p_warehouse_id AND is_active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'WAREHOUSE_NOT_FOUND: El almacén especificado no existe o está inactivo.' USING ERRCODE = '02000';
    END IF;

    -- 5. Bloqueo advisory y fila de inventario.
    -- Si product_inventory tiene warehouse_id, el stock se trata por almacén;
    -- si no, se trata como stock global por producto.
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'product_inventory'
          AND column_name = 'warehouse_id'
    ) INTO v_inventory_has_warehouse;

    IF v_inventory_has_warehouse THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(p_product_id::text || ':' || p_warehouse_id::text, 0));
        EXECUTE
            'SELECT * FROM public.product_inventory WHERE product_id = $1 AND warehouse_id = $2 FOR UPDATE'
        INTO v_inventory
        USING p_product_id, p_warehouse_id;
    ELSE
        PERFORM pg_advisory_xact_lock(hashtextextended(p_product_id::text, 0));
        EXECUTE
            'SELECT * FROM public.product_inventory WHERE product_id = $1 FOR UPDATE'
        INTO v_inventory
        USING p_product_id;
    END IF;

    IF v_inventory.id IS NULL THEN
        IF v_inventory_has_warehouse THEN
            RAISE EXCEPTION 'PRODUCT_NOT_IN_WAREHOUSE_INVENTORY: El producto no cuenta con inventario en el almacén seleccionado.' USING ERRCODE = '02000';
        ELSE
            RAISE EXCEPTION 'PRODUCT_NOT_IN_INVENTORY: El producto no cuenta con registro de inventario físico.' USING ERRCODE = '02000';
        END IF;
    END IF;

    -- 6. Calcular stock disponible canónico (current_stock - active unexpired reservations)
    v_reservations_table_exists := to_regclass('public.inventory_reservations') IS NOT NULL;
    IF v_reservations_table_exists THEN
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'inventory_reservations'
              AND column_name = 'warehouse_id'
        ) INTO v_reservations_has_warehouse;

        IF v_inventory_has_warehouse AND v_reservations_has_warehouse THEN
            EXECUTE
                'SELECT COALESCE(sum(quantity_reserved), 0)
                   FROM public.inventory_reservations
                  WHERE product_id = $1
                    AND warehouse_id = $2
                    AND status = ''active''
                    AND (expires_at IS NULL OR expires_at > now())'
            INTO v_reserved_stock
            USING p_product_id, p_warehouse_id;
        ELSE
            EXECUTE
                'SELECT COALESCE(sum(quantity_reserved), 0)
                   FROM public.inventory_reservations
                  WHERE product_id = $1
                    AND status = ''active''
                    AND (expires_at IS NULL OR expires_at > now())'
            INTO v_reserved_stock
            USING p_product_id;
        END IF;
    END IF;

    v_previous := COALESCE(v_inventory.current_stock, 0);
    v_available_stock := GREATEST(0, v_previous - v_reserved_stock);

    IF v_available_stock < p_quantity THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK: Stock disponible insuficiente (Disponible: %, Solicitado: %).', v_available_stock, p_quantity
            USING ERRCODE = 'P0001';
    END IF;

    v_resulting := round(v_previous - p_quantity, 2);
    IF v_resulting < 0 THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK: La operación dejaría stock físico negativo.' USING ERRCODE = 'P0001';
    END IF;

    -- 7. Registrar consumo de refacción en la orden de servicio
    INSERT INTO public.service_parts_used (
        service_order_id,
        product_id,
        warehouse_id,
        quantity,
        unit_cost
    ) VALUES (
        p_service_order_id,
        p_product_id,
        p_warehouse_id,
        p_quantity,
        COALESCE(p_unit_cost, 0)
    );

    -- 8. Registrar movimiento de inventario con tipado seguro
    SELECT * INTO v_typed_movement
    FROM jsonb_populate_record(
        null::public.inventory_movements,
        jsonb_build_object(
            'movement_type', 'service_usage',
            'reference_type', 'service'
        )
    );

    INSERT INTO public.inventory_movements (
        warehouse_id,
        product_id,
        movement_type,
        quantity,
        previous_stock,
        resulting_stock,
        reference_type,
        reference_id,
        notes,
        created_by,
        created_at
    ) VALUES (
        p_warehouse_id,
        p_product_id,
        v_typed_movement.movement_type,
        p_quantity * -1,
        v_previous,
        v_resulting,
        v_typed_movement.reference_type,
        p_service_order_id,
        'Consumo de refacción en servicio técnico',
        auth.uid(),
        now()
    );

    -- 9. Actualizar current_stock en product_inventory (patrón canónico)
    UPDATE public.product_inventory
    SET current_stock = v_resulting,
        updated_by = auth.uid(),
        updated_at = now()
    WHERE id = v_inventory.id;
END;
$$;
-- ----------------------------------------------------------------------------
-- 2. RPC start_service_order (COORDINACIÓN SEGURA, REUTILIZACIÓN Y FAIL-CLOSED)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_service_order(
    p_ticket_id uuid,
    p_technician_id uuid DEFAULT NULL,
    p_scheduled_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id uuid;
    v_ticket record;
    v_order record;
    v_order_id uuid;
    v_tech_id uuid;
    v_has_quote boolean;
    v_quote_converted boolean;
    v_active_count integer;
    v_started_at timestamptz;
    v_was_already_in_progress boolean := false;
BEGIN
    -- 1. Autenticación y Autorización
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED: Debes iniciar sesión.' USING ERRCODE = '42501';
    END IF;

    IF NOT (public.is_staff_or_admin() OR public.is_technician_or_admin()) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Solo el personal técnico o administrativo puede iniciar órdenes de servicio.' USING ERRCODE = '42501';
    END IF;

    IF p_ticket_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_TICKET_ID: Se requiere p_ticket_id.' USING ERRCODE = '22023';
    END IF;

    -- 2. Bloqueo advisory transaccional coordinado por ticket
    PERFORM pg_advisory_xact_lock(hashtextextended(p_ticket_id::text, 0));

    -- 3. Cargar ticket con FOR UPDATE
    SELECT *
    INTO v_ticket
    FROM public.service_tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TICKET_NOT_FOUND: El ticket de servicio no existe.' USING ERRCODE = '02000';
    END IF;

    IF v_ticket.status IN ('resolved'::public.ticket_status, 'closed'::public.ticket_status, 'cancelled'::public.ticket_status) THEN
        RAISE EXCEPTION 'INVALID_TICKET_STATUS: No se puede iniciar un servicio en un ticket finalizado o cancelado (%).', v_ticket.status USING ERRCODE = '23514';
    END IF;

    -- 4. Verificación comercial post-pago
    SELECT EXISTS (
        SELECT 1 FROM public.quotes WHERE service_ticket_id = p_ticket_id
    ) INTO v_has_quote;

    IF v_has_quote THEN
        SELECT EXISTS (
            SELECT 1 
            FROM public.quotes q
            JOIN public.orders o ON o.id = q.converted_order_id
            WHERE q.service_ticket_id = p_ticket_id
              AND q.status = 'converted'::public.quote_status
              AND o.payment_status = 'approved'
        ) INTO v_quote_converted;

        IF NOT v_quote_converted THEN
            RAISE EXCEPTION 'PAYMENT_REQUIRED: El ticket tiene una cotización que aún no ha sido pagada/aprobada.' USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 5. Contar órdenes de servicio activas (Fail-Closed si hay inconsistencia de datos históricos)
    SELECT count(*)
    INTO v_active_count
    FROM public.service_orders
    WHERE service_ticket_id = p_ticket_id
      AND status IN ('assigned'::public.ticket_status, 'in_progress'::public.ticket_status, 'waiting_parts'::public.ticket_status, 'paused'::public.ticket_status);

    IF v_active_count > 1 THEN
        RAISE EXCEPTION 'MULTIPLE_ACTIVE_SERVICE_ORDERS: Se encontraron múltiples órdenes de servicio activas para este ticket. Requiere revisión administrativa.' USING ERRCODE = '23514';
    END IF;

    -- 6. Buscar orden de servicio activa si existe
    IF v_active_count = 1 THEN
        SELECT *
        INTO v_order
        FROM public.service_orders
        WHERE service_ticket_id = p_ticket_id
          AND status IN ('assigned'::public.ticket_status, 'in_progress'::public.ticket_status, 'waiting_parts'::public.ticket_status, 'paused'::public.ticket_status)
        FOR UPDATE;

        -- Validación de técnico: Un técnico no puede reasignarse una orden activa asignada a otro técnico
        IF NOT public.is_staff_or_admin() THEN
            IF v_order.assigned_technician_id IS NOT NULL AND v_order.assigned_technician_id <> v_user_id THEN
                RAISE EXCEPTION 'NOT_AUTHORIZED: La orden activa está asignada a otro técnico.' USING ERRCODE = '42501';
            END IF;
            v_tech_id := COALESCE(v_order.assigned_technician_id, v_user_id);
        ELSE
            v_tech_id := COALESCE(p_technician_id, v_order.assigned_technician_id, v_user_id);
        END IF;

        v_order_id := v_order.id;
        v_started_at := COALESCE(v_order.started_at, now());
        v_was_already_in_progress := (v_order.status = 'in_progress'::public.ticket_status AND v_ticket.status = 'in_progress'::public.ticket_status);

        UPDATE public.service_orders
        SET 
            assigned_technician_id = v_tech_id,
            status = 'in_progress'::public.ticket_status,
            started_at = v_started_at,
            scheduled_at = COALESCE(p_scheduled_at, scheduled_at),
            updated_at = now()
        WHERE id = v_order_id;
    ELSE
        -- No hay orden activa: crear una nueva
        IF NOT public.is_staff_or_admin() THEN
            v_tech_id := v_user_id;
        ELSE
            v_tech_id := COALESCE(p_technician_id, v_ticket.assigned_technician_id, v_user_id);
        END IF;

        v_started_at := now();

        INSERT INTO public.service_orders (
            service_ticket_id,
            assigned_technician_id,
            status,
            scheduled_at,
            started_at
        ) VALUES (
            p_ticket_id,
            v_tech_id,
            'in_progress'::public.ticket_status,
            p_scheduled_at,
            v_started_at
        )
        RETURNING id INTO v_order_id;
    END IF;

    -- 7. Actualizar status del ticket a in_progress
    UPDATE public.service_tickets
    SET 
        status = 'in_progress'::public.ticket_status,
        assigned_technician_id = v_tech_id,
        updated_at = now()
    WHERE id = p_ticket_id;

    -- 8. Registrar evento de auditoría solo si hubo transición real
    IF NOT v_was_already_in_progress THEN
        INSERT INTO public.service_ticket_events (
            ticket_id,
            event_type,
            from_status,
            to_status,
            actor_profile_id
        ) VALUES (
            p_ticket_id,
            'started',
            v_ticket.status,
            'in_progress'::public.ticket_status,
            v_user_id
        );
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'service_order_id', v_order_id,
        'ticket_id', p_ticket_id,
        'status', 'in_progress',
        'assigned_technician_id', v_tech_id,
        'started_at', v_started_at
    );
END;
$$;
REVOKE ALL ON FUNCTION public.start_service_order(uuid, uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_service_order(uuid, uuid, timestamptz) TO authenticated;
-- ----------------------------------------------------------------------------
-- 3. RPC complete_service_order (IDEMPOTENCIA ESTRICTA CON RECOMMENDATIONS)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_service_order(
    p_service_order_id uuid,
    p_diagnosis text,
    p_solution text,
    p_recommendations text DEFAULT NULL
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
           AND nullif(trim(v_order.recommendations), '') IS NOT DISTINCT FROM v_recommendations THEN
            -- Reintento idéntico: devolver datos existentes sin reescribir completed_at ni duplicar evento
            RETURN jsonb_build_object(
                'ok', true,
                'service_order_id', p_service_order_id,
                'ticket_id', v_order.service_ticket_id,
                'status', v_order.status,
                'diagnosis', v_order.diagnosis,
                'solution', v_order.solution,
                'recommendations', v_order.recommendations,
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
        'completed_at', v_completed_at
    );
END;
$$;
REVOKE ALL ON FUNCTION public.complete_service_order(uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_service_order(uuid, text, text, text) TO authenticated;
-- ----------------------------------------------------------------------------
-- 4. RPC close_service_ticket (IDEMPOTENCIA ESTRICTA Y EVENTO ÚNICO)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_service_ticket(
    p_ticket_id uuid,
    p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id uuid;
    v_ticket record;
    v_order record;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED: Debes iniciar sesión.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_staff_or_admin() THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Solo el personal administrativo puede cerrar definitivamente un ticket.' USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_ticket
    FROM public.service_tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TICKET_NOT_FOUND: El ticket no existe.' USING ERRCODE = '02000';
    END IF;

    -- Si ya está cerrado, retornar estado actual sin duplicar eventos
    IF v_ticket.status = 'closed'::public.ticket_status THEN
        RETURN jsonb_build_object(
            'ok', true,
            'ticket_id', p_ticket_id,
            'status', 'closed',
            'closed_at', v_ticket.updated_at
        );
    END IF;

    IF v_ticket.status != 'resolved'::public.ticket_status THEN
        RAISE EXCEPTION 'INVALID_TICKET_STATUS: Solo se pueden cerrar tickets previamente resueltos (resolved). Estado actual: %', v_ticket.status USING ERRCODE = '23514';
    END IF;

    -- Verificar que exista al menos una orden de servicio completada
    SELECT *
    INTO v_order
    FROM public.service_orders
    WHERE service_ticket_id = p_ticket_id
      AND completed_at IS NOT NULL
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SERVICE_ORDER_INCOMPLETE: No se puede cerrar el ticket porque no cuenta con una orden de servicio completada.' USING ERRCODE = '23514';
    END IF;

    -- Actualizar ticket y órdenes resueltas a closed
    UPDATE public.service_tickets
    SET 
        status = 'closed'::public.ticket_status,
        updated_at = now()
    WHERE id = p_ticket_id;

    UPDATE public.service_orders
    SET 
        status = 'closed'::public.ticket_status,
        updated_at = now()
    WHERE service_ticket_id = p_ticket_id
      AND status = 'resolved'::public.ticket_status;

    INSERT INTO public.service_ticket_events (
        ticket_id,
        event_type,
        from_status,
        to_status,
        reason,
        actor_profile_id
    ) VALUES (
        p_ticket_id,
        'closed',
        'resolved'::public.ticket_status,
        'closed'::public.ticket_status,
        trim(p_reason),
        v_user_id
    );

    RETURN jsonb_build_object(
        'ok', true,
        'ticket_id', p_ticket_id,
        'status', 'closed',
        'closed_at', now()
    );
END;
$$;
REVOKE ALL ON FUNCTION public.close_service_ticket(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_service_ticket(uuid, text) TO authenticated;
-- ----------------------------------------------------------------------------
-- 5. TRIGGER DE INMUTABILIDAD TOTAL PARA service_orders FINALIZADAS
-- ----------------------------------------------------------------------------
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
DROP TRIGGER IF EXISTS trg_guard_service_orders_immutability ON public.service_orders;
CREATE TRIGGER trg_guard_service_orders_immutability
BEFORE UPDATE ON public.service_orders
FOR EACH ROW
EXECUTE FUNCTION public.guard_service_orders_immutability();
