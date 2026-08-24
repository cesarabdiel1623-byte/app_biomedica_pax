-- ============================================================================
-- MIGRACIÓN T2B-H1: HARDENING BACKEND DE COTIZACIONES DE SERVICIO
-- Timestamp: 20260819130000_t2b_service_quote_hardening.sql
-- ============================================================================
-- 1. ÍNDICE PARCIAL DE UNICIDAD: Máximo una cotización activa (sent o approved) por service_ticket_id.
-- 2. TRIGGER INMUTABILIDAD quote_items: Bloquea modificaciones a partidas cuando la cotización ya no es 'draft'.
-- 3. TRIGGER INMUTABILIDAD quotes: Bloquea modificaciones a montos financieros y datos estructurales fuera de 'draft',
--    preservando transiciones autoritativas legítimas (respond_to_quote, trg_sync_source_quote_after_payment).
-- 4. RPC create_service_quote: Creación atómica y validada de cotización + partidas de servicio.
-- 5. RPC send_service_quote: Envío autoritativo draft -> sent con validaciones de items, vigencia y exclusividad.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ÍNDICE PARCIAL DE UNICIDAD DE COTIZACIÓN ACTIVA POR TICKET
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_service_ticket_quote
ON public.quotes (service_ticket_id)
WHERE service_ticket_id IS NOT NULL AND status IN ('sent'::public.quote_status, 'approved'::public.quote_status);
-- ----------------------------------------------------------------------------
-- 2. TRIGGER DE INMUTABILIDAD PARA quote_items
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_quote_items_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_quote_status public.quote_status;
    v_quote_id uuid;
BEGIN
    v_quote_id := COALESCE(NEW.quote_id, OLD.quote_id);
    
    SELECT status INTO v_quote_status
    FROM public.quotes
    WHERE id = v_quote_id;

    IF v_quote_status IS NOT NULL AND v_quote_status != 'draft'::public.quote_status THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se pueden modificar conceptos de una cotización con estado %', v_quote_status
            USING ERRCODE = '23514';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_quote_items_immutability ON public.quote_items;
CREATE TRIGGER trg_guard_quote_items_immutability
BEFORE INSERT OR UPDATE OR DELETE ON public.quote_items
FOR EACH ROW
EXECUTE FUNCTION public.guard_quote_items_immutability();
-- ----------------------------------------------------------------------------
-- 3. TRIGGER DE INMUTABILIDAD PARA CABECERA quotes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_quotes_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    -- Mientras la cotización esté en borrador ('draft'), se permite editar todo libremente
    IF OLD.status = 'draft'::public.quote_status THEN
        RETURN NEW;
    END IF;

    -- Si ya no está en draft, proteger campos estructurales y financieros contra manipulaciones
    IF NEW.client_id IS DISTINCT FROM OLD.client_id THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar client_id en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.service_ticket_id IS DISTINCT FROM OLD.service_ticket_id THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar service_ticket_id en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.quote_number IS DISTINCT FROM OLD.quote_number THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar quote_number en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.subtotal IS DISTINCT FROM OLD.subtotal THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar subtotal en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.tax_pct IS DISTINCT FROM OLD.tax_pct THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar tax_pct en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.tax_exempt IS DISTINCT FROM OLD.tax_exempt THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar tax_exempt en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.tax IS DISTINCT FROM OLD.tax THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar tax en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.total IS DISTINCT FROM OLD.total THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar total en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.discount IS DISTINCT FROM OLD.discount THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar discount global en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.valid_until IS DISTINCT FROM OLD.valid_until THEN
        RAISE EXCEPTION 'IMMUTABLE_QUOTE: No se permite modificar valid_until en cotización con estado %', OLD.status
            USING ERRCODE = '23514';
    END IF;

    -- Validar transiciones de estado permitidas
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF OLD.status = 'sent'::public.quote_status AND NEW.status NOT IN ('approved'::public.quote_status, 'rejected'::public.quote_status, 'expired'::public.quote_status) THEN
            RAISE EXCEPTION 'INVALID_STATUS_TRANSITION: Una cotización enviada solo puede pasar a approved, rejected o expired. Intento: %', NEW.status
                USING ERRCODE = '23514';
        ELSIF OLD.status = 'approved'::public.quote_status AND NEW.status != 'converted'::public.quote_status THEN
            RAISE EXCEPTION 'INVALID_STATUS_TRANSITION: Una cotización aprobada solo puede pasar a converted tras el pago. Intento: %', NEW.status
                USING ERRCODE = '23514';
        ELSIF OLD.status IN ('rejected'::public.quote_status, 'expired'::public.quote_status, 'converted'::public.quote_status) THEN
            RAISE EXCEPTION 'INVALID_STATUS_TRANSITION: No se puede cambiar el estado de una cotización finalizada (%)', OLD.status
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_quotes_immutability ON public.quotes;
CREATE TRIGGER trg_guard_quotes_immutability
BEFORE UPDATE ON public.quotes
FOR EACH ROW
EXECUTE FUNCTION public.guard_quotes_immutability();
-- ----------------------------------------------------------------------------
-- 4. RPC TRANSACCIONAL: create_service_quote
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_service_quote(
    p_ticket_id uuid,
    p_items jsonb,
    p_valid_until date DEFAULT NULL,
    p_notes text DEFAULT NULL,
    p_tax_exempt boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id uuid;
    v_client_id uuid;
    v_ticket record;
    v_quote_id uuid;
    v_quote record;
    v_item jsonb;
    v_item_name text;
    v_quantity numeric;
    v_unit_price numeric;
    v_discount numeric;
    v_item_count integer := 0;
BEGIN
    -- 1. Autenticación y Autorización
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED: Debes iniciar sesión.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_staff_or_admin() THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Solo el personal administrativo puede crear cotizaciones de servicio.' USING ERRCODE = '42501';
    END IF;

    -- 2. Validar Ticket y derivar client_id exclusivamente del ticket
    IF p_ticket_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_TICKET_ID: Se requiere p_ticket_id.' USING ERRCODE = '22023';
    END IF;

    SELECT id, client_id, status, ticket_number
    INTO v_ticket
    FROM public.service_tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TICKET_NOT_FOUND: El ticket de servicio no existe.' USING ERRCODE = '02000';
    END IF;

    v_client_id := v_ticket.client_id;
    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_TICKET_CLIENT: El ticket no tiene un cliente asignado.' USING ERRCODE = '22023';
    END IF;

    -- 3. Validar Array de Conceptos
    IF p_items IS NULL OR jsonb_typeof(p_items) != 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'EMPTY_QUOTE_ITEMS: Debes incluir al menos un concepto en la cotización.' USING ERRCODE = '22023';
    END IF;

    -- 4. Insertar cabecera de cotización en 'draft'
    INSERT INTO public.quotes (
        client_id,
        service_ticket_id,
        status,
        valid_until,
        notes,
        tax_exempt,
        created_by
    ) VALUES (
        v_client_id,
        p_ticket_id,
        'draft'::public.quote_status,
        p_valid_until,
        trim(p_notes),
        COALESCE(p_tax_exempt, false),
        v_user_id
    )
    RETURNING id INTO v_quote_id;

    -- 5. Insertar y validar cada concepto en la misma transacción
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_item_name := trim(v_item->>'product_name_snapshot');
        v_quantity := (v_item->>'quantity')::numeric;
        v_unit_price := (v_item->>'unit_price')::numeric;
        v_discount := COALESCE((v_item->>'discount')::numeric, 0);

        IF v_item_name IS NULL OR v_item_name = '' THEN
            RAISE EXCEPTION 'INVALID_QUOTE_ITEM: La descripción del concepto no puede estar vacía.' USING ERRCODE = '22023';
        END IF;

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'INVALID_QUOTE_ITEM: La cantidad del concepto "%" debe ser mayor a 0.', v_item_name USING ERRCODE = '22023';
        END IF;

        IF v_unit_price IS NULL OR v_unit_price < 0 THEN
            RAISE EXCEPTION 'INVALID_QUOTE_ITEM: El precio unitario del concepto "%" no puede ser negativo.', v_item_name USING ERRCODE = '22023';
        END IF;

        IF v_discount < 0 THEN
            RAISE EXCEPTION 'INVALID_QUOTE_ITEM: El descuento del concepto "%" no puede ser negativo.', v_item_name USING ERRCODE = '22023';
        END IF;

        IF v_discount > (v_quantity * v_unit_price) THEN
            RAISE EXCEPTION 'INVALID_QUOTE_ITEM: El descuento del concepto "%" no puede superar su importe bruto.', v_item_name USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.quote_items (
            quote_id,
            product_id,
            product_name_snapshot,
            quantity,
            unit_price,
            discount
        ) VALUES (
            v_quote_id,
            NULL, -- Estrictamente NULL para conceptos de servicio
            v_item_name,
            v_quantity,
            v_unit_price,
            v_discount
        );

        v_item_count := v_item_count + 1;
    END LOOP;

    -- 6. Recalcular totales autoritativos en base de datos
    PERFORM public.recalculate_quote_totals(v_quote_id);

    -- 7. Obtener la fila recalculada
    SELECT 
        id,
        quote_number,
        client_id,
        service_ticket_id,
        status,
        subtotal,
        tax_pct,
        tax_exempt,
        tax,
        total,
        valid_until,
        notes,
        created_at
    INTO v_quote
    FROM public.quotes
    WHERE id = v_quote_id;

    RETURN jsonb_build_object(
        'ok', true,
        'quote_id', v_quote.id,
        'quote_number', v_quote.quote_number,
        'client_id', v_quote.client_id,
        'service_ticket_id', v_quote.service_ticket_id,
        'status', v_quote.status,
        'subtotal', v_quote.subtotal,
        'tax', v_quote.tax,
        'total', v_quote.total,
        'valid_until', v_quote.valid_until,
        'item_count', v_item_count
    );
END;
$$;
REVOKE ALL ON FUNCTION public.create_service_quote(uuid, jsonb, date, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_service_quote(uuid, jsonb, date, text, boolean) TO authenticated;
-- ----------------------------------------------------------------------------
-- 5. RPC AUTORITATIVA: send_service_quote
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_service_quote(
    p_quote_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id uuid;
    v_quote record;
    v_items_count integer;
    v_active_exists boolean;
BEGIN
    -- 1. Autenticación y Autorización
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED: Debes iniciar sesión.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_staff_or_admin() THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Solo el personal administrativo puede enviar cotizaciones.' USING ERRCODE = '42501';
    END IF;

    IF p_quote_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_QUOTE_ID: Se requiere p_quote_id.' USING ERRCODE = '22023';
    END IF;

    -- 2. Cargar y bloquear la cotización con FOR UPDATE
    SELECT *
    INTO v_quote
    FROM public.quotes
    WHERE id = p_quote_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'QUOTE_NOT_FOUND: La cotización no existe.' USING ERRCODE = '02000';
    END IF;

    IF v_quote.service_ticket_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_SERVICE_QUOTE: Esta función es exclusiva para cotizaciones de servicio vinculadas a un ticket.' USING ERRCODE = '22023';
    END IF;

    IF v_quote.status != 'draft'::public.quote_status THEN
        RAISE EXCEPTION 'QUOTE_NOT_DRAFT: Solo se pueden enviar cotizaciones en estado borrador (draft). Estado actual: %', v_quote.status USING ERRCODE = '23514';
    END IF;

    -- 3. Validar que tenga al menos un concepto registrado
    SELECT count(*) INTO v_items_count
    FROM public.quote_items
    WHERE quote_id = p_quote_id;

    IF v_items_count = 0 THEN
        RAISE EXCEPTION 'QUOTE_HAS_NO_ITEMS: No se puede enviar una cotización sin conceptos de servicio.' USING ERRCODE = '22023';
    END IF;

    -- 4. Validar vigencia
    IF v_quote.valid_until IS NOT NULL AND v_quote.valid_until < CURRENT_DATE THEN
        RAISE EXCEPTION 'QUOTE_EXPIRED: La fecha de vigencia de la cotización ya ha expirado (%).', v_quote.valid_until USING ERRCODE = '22023';
    END IF;

    -- 5. Validar que no exista otra cotización activa para el mismo ticket
    SELECT EXISTS (
        SELECT 1 FROM public.quotes
        WHERE service_ticket_id = v_quote.service_ticket_id
          AND id != p_quote_id
          AND status IN ('sent'::public.quote_status, 'approved'::public.quote_status)
    ) INTO v_active_exists;

    IF v_active_exists THEN
        RAISE EXCEPTION 'ACTIVE_SERVICE_QUOTE_EXISTS: Ya existe una cotización activa (enviada o aprobada) para este ticket. Cancela o rechaza la anterior antes de enviar una nueva.' USING ERRCODE = '23505';
    END IF;

    -- 6. Actualizar a 'sent'
    UPDATE public.quotes
    SET 
        status = 'sent'::public.quote_status,
        sent_at = now(),
        updated_at = now()
    WHERE id = p_quote_id;

    RETURN jsonb_build_object(
        'ok', true,
        'quote_id', v_quote.id,
        'quote_number', v_quote.quote_number,
        'status', 'sent',
        'subtotal', v_quote.subtotal,
        'tax', v_quote.tax,
        'total', v_quote.total,
        'sent_at', now()
    );
END;
$$;
REVOKE ALL ON FUNCTION public.send_service_quote(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_service_quote(uuid) TO authenticated;
