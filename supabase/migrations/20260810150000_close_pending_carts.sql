-- Migration: Close Pending Carts and Allow Closed Cart Conversion

CREATE OR REPLACE FUNCTION public.reconcile_mp_web_order_payment(
    p_external_reference text,
    p_payment_id text,
    p_amount numeric,
    p_currency_id text,
    p_status text,
    p_status_detail text,
    p_payment_method_id text,
    p_payment_type_id text,
    p_installments integer,
    p_live_mode boolean,
    p_date_approved timestamptz,
    p_provider_created_at timestamptz,
    p_provider_updated_at timestamptz,
    p_environment text,
    p_raw_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
SET search_path = public, pg_temp
SECURITY DEFINER
AS $$
DECLARE
    v_payment record;
    v_order record;
    v_cart record;
    v_payment_status text;
    v_mapped_status public.payment_record_status;
    v_is_primary boolean := false;
BEGIN
    -- Buscar el intento por referencia (el webhook lo localiza así)
    SELECT * INTO v_payment 
    FROM public.order_payments 
    WHERE external_reference = p_external_reference 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment attempt with external_reference % not found', p_external_reference;
    END IF;

    -- Buscar la orden utilizando el id del intento (NO por external_reference de orders)
    SELECT * INTO v_order 
    FROM public.orders 
    WHERE id = v_payment.order_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', v_payment.order_id;
    END IF;

    IF v_order.client_id <> v_payment.client_id THEN
        RAISE EXCEPTION 'Order and payment client mismatch';
    END IF;

    IF p_payment_id IS NULL OR btrim(p_payment_id) = '' THEN
        RAISE EXCEPTION 'Payment ID is required';
    END IF;

    -- La referencia de un intento no puede cambiar de payment_id.
    IF v_payment.payment_id IS NOT NULL
       AND v_payment.payment_id <> p_payment_id THEN
        RAISE EXCEPTION 'Payment attempt is already associated with a different payment ID';
    END IF;

    -- Verificar que el payment_id no pertenezca a otro registro, incluso dentro de la misma orden.
    IF p_payment_id IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.order_payments 
            WHERE payment_id = p_payment_id AND id <> v_payment.id
        ) THEN
            RAISE EXCEPTION 'Payment ID % is used in another order or attempt', p_payment_id;
        END IF;
    END IF;

    -- Validar montos y moneda 
    IF v_payment.amount <> p_amount OR v_order.total <> p_amount THEN
        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments 
            SET status = 'error', status_detail = 'amount_mismatch', updated_at = now()
            WHERE id = v_payment.id;
        END IF;
        RETURN jsonb_build_object('success', false, 'error', 'amount_mismatch');
    END IF;

    IF p_currency_id <> 'MXN' THEN
        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments 
            SET status = 'error', status_detail = 'currency_mismatch', updated_at = now()
            WHERE id = v_payment.id;
        END IF;
        RETURN jsonb_build_object('success', false, 'error', 'currency_mismatch');
    END IF;

    -- Validar ambiente
    IF p_environment NOT IN ('test', 'production') OR p_environment <> v_payment.environment THEN
        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments 
            SET status = 'error', status_detail = 'environment_mismatch', updated_at = now()
            WHERE id = v_payment.id;
        END IF;
        RETURN jsonb_build_object('success', false, 'error', 'environment_mismatch');
    END IF;

    IF p_environment = 'production' AND p_live_mode IS DISTINCT FROM TRUE THEN
        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments 
            SET status = 'error', status_detail = 'live_mode_mismatch', updated_at = now()
            WHERE id = v_payment.id;
        END IF;
        RETURN jsonb_build_object('success', false, 'error', 'live_mode_mismatch');
    END IF;

    IF p_environment = 'test' AND p_live_mode IS DISTINCT FROM FALSE THEN
        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments 
            SET status = 'error', status_detail = 'live_mode_mismatch', updated_at = now()
            WHERE id = v_payment.id;
        END IF;
        RETURN jsonb_build_object('success', false, 'error', 'live_mode_mismatch');
    END IF;

    -- Mapeo de estados de MP al ENUM payment_record_status
    v_mapped_status := CASE p_status
        WHEN 'approved' THEN 'approved'::public.payment_record_status
        WHEN 'accredited' THEN 'approved'::public.payment_record_status
        WHEN 'pending' THEN 'pending'::public.payment_record_status
        WHEN 'in_process' THEN 'pending'::public.payment_record_status
        WHEN 'in_mediation' THEN 'pending'::public.payment_record_status
        WHEN 'rejected' THEN 'rejected'::public.payment_record_status
        WHEN 'cancelled' THEN 'cancelled'::public.payment_record_status
        WHEN 'canceled' THEN 'cancelled'::public.payment_record_status
        WHEN 'refunded' THEN 'refunded'::public.payment_record_status
        WHEN 'charged_back' THEN 'charged_back'::public.payment_record_status
        ELSE 'error'::public.payment_record_status
    END;

    -- PROTECCIÓN CONTRA REGRESIÓN: si ya estaba aprobado, y el webhook trae estado distinto, no retroceder
    IF v_payment.status = 'approved' AND v_mapped_status <> 'approved' THEN
        v_mapped_status := 'approved'::public.payment_record_status;
        v_is_primary := v_payment.is_primary;

        -- Solo actualizamos metadatos seguros sin tocar payment_id ni date_approved.
        UPDATE public.order_payments
        SET last_webhook_at = now(),
            provider_updated_at = COALESCE(p_provider_updated_at, v_payment.provider_updated_at),
            raw_metadata = COALESCE(v_payment.raw_metadata, '{}'::jsonb) || COALESCE(p_raw_metadata, '{}'::jsonb),
            updated_at = now()
        WHERE id = v_payment.id;

        -- Una repetición idempotente también repara la orden si el pago primario
        -- quedó aprobado pero la actualización de orders no se completó antes.
        IF v_payment.is_primary AND v_order.payment_status <> 'approved' THEN
            UPDATE public.orders
            SET payment_status = 'approved',
                status = 'paid',
                paid_at = COALESCE(v_order.paid_at, v_payment.date_approved, p_date_approved, now()),
                updated_at = now()
            WHERE id = v_order.id;
        END IF;

        IF v_is_primary AND v_order.source_cart_id IS NOT NULL THEN
            SELECT * INTO v_cart FROM public.carts WHERE id = v_order.source_cart_id FOR UPDATE;
            IF FOUND THEN
                IF v_cart.status IN ('active', 'closed') AND v_cart.converted_order_id IS NULL THEN
                    UPDATE public.carts
                    SET status = 'converted_to_order',
                        converted_order_id = v_order.id,
                        updated_at = now()
                    WHERE id = v_order.source_cart_id;
                ELSIF v_cart.converted_order_id IS NOT NULL AND v_cart.converted_order_id <> v_order.id THEN
                    RAISE EXCEPTION 'Cart % is already converted to a different order %', v_cart.id, v_cart.converted_order_id;
                END IF;
            END IF;
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'order_id', v_order.id,
            'payment_status', 'approved'
        );
    END IF;

    -- Si llega aprobado, validamos primario
    IF v_mapped_status = 'approved' THEN
        IF NOT EXISTS (SELECT 1 FROM public.order_payments WHERE order_id = v_order.id AND is_primary = true AND id <> v_payment.id) THEN
            v_is_primary := true;
        END IF;
    END IF;

    -- Actualizar el intento
    UPDATE public.order_payments 
    SET 
        payment_id = p_payment_id,
        status = v_mapped_status,
        status_detail = p_status_detail,
        payment_method_id = p_payment_method_id,
        payment_type_id = p_payment_type_id,
        installments = p_installments,
        live_mode = p_live_mode,
        date_approved = COALESCE(p_date_approved, v_payment.date_approved),
        provider_created_at = COALESCE(p_provider_created_at, v_payment.provider_created_at),
        provider_updated_at = COALESCE(p_provider_updated_at, v_payment.provider_updated_at),
        last_webhook_at = now(),
        raw_metadata = COALESCE(v_payment.raw_metadata, '{}'::jsonb) || COALESCE(p_raw_metadata, '{}'::jsonb),
        is_primary = v_is_primary,
        updated_at = now()
    WHERE id = v_payment.id;

    -- Si el intento es primario y aprobado, actualizamos Orders
    IF v_is_primary THEN
        UPDATE public.orders 
        SET 
            payment_status = 'approved',
            status = 'paid',
            paid_at = COALESCE(v_order.paid_at, p_date_approved, now()),
            updated_at = now()
        WHERE id = v_order.id;

        IF v_order.source_cart_id IS NOT NULL THEN
            SELECT * INTO v_cart FROM public.carts WHERE id = v_order.source_cart_id FOR UPDATE;
            IF FOUND THEN
                IF v_cart.status IN ('active', 'closed') AND v_cart.converted_order_id IS NULL THEN
                    UPDATE public.carts
                    SET status = 'converted_to_order',
                        converted_order_id = v_order.id,
                        updated_at = now()
                    WHERE id = v_order.source_cart_id;
                ELSIF v_cart.converted_order_id IS NOT NULL AND v_cart.converted_order_id <> v_order.id THEN
                    RAISE EXCEPTION 'Cart % is already converted to a different order %', v_cart.id, v_cart.converted_order_id;
                END IF;
            END IF;
        END IF;
    ELSIF v_mapped_status = 'pending' THEN
        -- Si el pago está en pending y tenemos carrito activo sin convertir, lo cerramos
        IF v_order.source_cart_id IS NOT NULL THEN
            SELECT * INTO v_cart FROM public.carts WHERE id = v_order.source_cart_id FOR UPDATE;
            IF FOUND THEN
                IF v_cart.status = 'active' AND v_cart.converted_order_id IS NULL THEN
                    UPDATE public.carts
                    SET status = 'closed',
                        updated_at = now()
                    WHERE id = v_order.source_cart_id;
                END IF;
            END IF;
        END IF;
    ELSIF v_mapped_status IN ('rejected', 'cancelled', 'error') THEN
        -- Si falló y la orden no estaba pagada
        IF v_order.payment_status <> 'approved' THEN
            UPDATE public.orders 
            SET 
                payment_status = v_mapped_status,
                updated_at = now()
            WHERE id = v_order.id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order.id,
        'payment_status', (CASE WHEN v_is_primary THEN 'approved' ELSE v_order.payment_status END)
    );
END;
$$ LANGUAGE plpgsql;
REVOKE EXECUTE ON FUNCTION public.reconcile_mp_web_order_payment(text, text, numeric, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, timestamptz, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reconcile_mp_web_order_payment(text, text, numeric, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, timestamptz, text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.reconcile_mp_web_order_payment(text, text, numeric, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, timestamptz, text, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_mp_web_order_payment(text, text, numeric, text, text, text, text, text, integer, boolean, timestamptz, timestamptz, timestamptz, text, jsonb) TO service_role;
