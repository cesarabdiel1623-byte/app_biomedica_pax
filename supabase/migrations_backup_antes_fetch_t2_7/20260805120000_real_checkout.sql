-- Migration: Real Checkout and Reusable Order Payments (Fase 2A) - Segunda Corrección

-- Adición de idempotency_key de forma segura y aditiva (UUID)
ALTER TABLE public.order_payments ADD COLUMN IF NOT EXISTS idempotency_key uuid;
CREATE UNIQUE INDEX IF NOT EXISTS order_payments_idempotency_key_uidx 
ON public.order_payments (idempotency_key) 
WHERE idempotency_key IS NOT NULL;
-- Función de preparación de la orden web
CREATE OR REPLACE FUNCTION public.prepare_web_checkout_order(
    p_cart_id uuid,
    p_address_id uuid DEFAULT NULL
)
RETURNS jsonb
SET search_path = public, pg_temp
SECURITY DEFINER
AS $$
DECLARE
    v_user_id uuid;
    v_client_id uuid;
    v_order_id uuid;
    v_subtotal numeric(12,2) := 0;
    v_tax numeric(12,2) := 0;
    v_total numeric(12,2) := 0;
    v_order_number text;
    v_existing_order record;
    v_item record;
    v_cart_count int;
    v_cart_active boolean;
    v_has_coupon boolean;
    v_address text;
    v_reused boolean := false;
    v_mismatch boolean;
BEGIN
    -- 1 & 2. Autenticación y client_id
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT client_id INTO v_client_id 
    FROM public.profiles 
    WHERE id = v_user_id 
      AND is_active = true 
      AND client_id IS NOT NULL;

    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Client profile not found, inactive or client_id is null';
    END IF;

    -- 4. Bloqueo transaccional
    PERFORM pg_advisory_xact_lock(hashtext(p_cart_id::text));

    -- 5. Validar carrito
    SELECT status = 'active', (applied_coupon_id IS NOT NULL OR applied_coupon_code IS NOT NULL)
    INTO v_cart_active, v_has_coupon
    FROM public.carts 
    WHERE id = p_cart_id AND client_id = v_client_id 
    FOR UPDATE;

    IF NOT FOUND OR NOT v_cart_active THEN
        RAISE EXCEPTION 'Cart not found, unauthorized or not active';
    END IF;
    
    IF v_has_coupon THEN
        RAISE EXCEPTION 'El checkout web todavía no admite cupones aplicados. Retira el cupón para continuar.';
    END IF;

    SELECT COUNT(*) INTO v_cart_count FROM public.cart_items WHERE cart_id = p_cart_id;
    IF v_cart_count = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    -- Dirección opcional
    IF p_address_id IS NOT NULL THEN
        SELECT concat_ws(', ', nullif(btrim(address), ''), nullif(btrim(city), ''), nullif(btrim(state), ''), nullif(btrim(postal_code), ''))
        INTO v_address
        FROM public.client_addresses
        WHERE id = p_address_id AND client_id = v_client_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Address not found or unauthorized';
        END IF;
    END IF;

    -- 6 a 12. Agrupar productos y validar
    FOR v_item IN 
        SELECT 
            c.product_id, 
            SUM(c.quantity) as total_qty,
            p.sku,
            p.name,
            p.category,
            p.unit_price_mxn,
            p.is_active,
            p.sales_mode,
            p.visible_in_app
        FROM public.cart_items c
        JOIN public.products p ON c.product_id = p.id
        WHERE c.cart_id = p_cart_id
        GROUP BY c.product_id, p.sku, p.name, p.category, p.unit_price_mxn, p.is_active, p.sales_mode, p.visible_in_app
    LOOP
        IF v_item.total_qty <= 0 OR v_item.total_qty != TRUNC(v_item.total_qty) THEN
            RAISE EXCEPTION 'Invalid quantity for product %', v_item.product_id;
        END IF;

        IF v_item.unit_price_mxn IS NULL OR v_item.unit_price_mxn <= 0 THEN
            RAISE EXCEPTION 'Product % has invalid price', v_item.product_id;
        END IF;

        IF NOT v_item.is_active OR NOT v_item.visible_in_app OR v_item.sales_mode NOT IN ('direct_purchase', 'both') THEN
            RAISE EXCEPTION 'Product % is not available for direct purchase', v_item.product_id;
        END IF;
        
        v_subtotal := v_subtotal + ROUND(v_item.unit_price_mxn * v_item.total_qty, 2);
    END LOOP;

    v_tax := ROUND(v_subtotal * 0.16, 2);
    v_total := v_subtotal + v_tax;

    IF v_total <= 0 THEN
        RAISE EXCEPTION 'Order total must be greater than zero';
    END IF;

    -- Reutilización exacta de orden respetando orders_source_cart_uidx.
    -- Solo puede existir una orden con source_cart_id no nulo para este carrito.
    SELECT id, order_number, subtotal, tax, total, status, payment_status
    INTO v_existing_order
    FROM public.orders
    WHERE source_cart_id = p_cart_id
      AND client_id = v_client_id
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing_order.status = 'pending_payment'
           AND v_existing_order.payment_status <> 'approved' THEN

            -- Comparación simétrica de productos, cantidades agrupadas y precios.
            SELECT EXISTS (
                (
                    SELECT product_id, SUM(quantity) AS qty, MAX(unit_price) AS price
                    FROM public.order_items
                    WHERE order_id = v_existing_order.id
                    GROUP BY product_id
                    EXCEPT
                    SELECT c.product_id, SUM(c.quantity) AS qty, MAX(p.unit_price_mxn) AS price
                    FROM public.cart_items c
                    JOIN public.products p ON p.id = c.product_id
                    WHERE c.cart_id = p_cart_id
                    GROUP BY c.product_id
                )
                UNION ALL
                (
                    SELECT c.product_id, SUM(c.quantity) AS qty, MAX(p.unit_price_mxn) AS price
                    FROM public.cart_items c
                    JOIN public.products p ON p.id = c.product_id
                    WHERE c.cart_id = p_cart_id
                    GROUP BY c.product_id
                    EXCEPT
                    SELECT product_id, SUM(quantity) AS qty, MAX(unit_price) AS price
                    FROM public.order_items
                    WHERE order_id = v_existing_order.id
                    GROUP BY product_id
                )
            ) INTO v_mismatch;

            IF NOT v_mismatch
               AND v_existing_order.total = v_total
               AND v_existing_order.subtotal = v_subtotal
               AND v_existing_order.tax = v_tax THEN
                v_order_id := v_existing_order.id;
                v_order_number := v_existing_order.order_number;
                v_reused := true;
            ELSE
                -- No modificar una orden que ya tenga intentos de pago: un webhook tardío
                -- podría corresponder al monto anterior.
                IF EXISTS (
                    SELECT 1
                    FROM public.order_payments
                    WHERE order_id = v_existing_order.id
                ) THEN
                    RAISE EXCEPTION 'El carrito cambió después de iniciar un intento de pago. Crea un carrito nuevo para continuar.';
                END IF;

                -- Se conserva la orden anterior para auditoría, se libera la referencia única
                -- al carrito y se crea una orden nueva con la composición actual.
                UPDATE public.orders
                SET source_cart_id = NULL,
                    status = 'canceled',
                    updated_at = now()
                WHERE id = v_existing_order.id;
            END IF;
        ELSE
            RAISE EXCEPTION 'El carrito ya está vinculado a una orden que no puede reemplazarse.';
        END IF;
    END IF;

    IF NOT v_reused THEN
        -- Creación de orden nueva
        v_order_number := 'ORD-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substring(md5(random()::text) from 1 for 8));
        
        INSERT INTO public.orders (
            order_number, client_id, status, subtotal, tax_pct, tax_exempt, tax, total, 
            created_by, payment_status, source_cart_id, payment_method, shipping_address
        ) VALUES (
            v_order_number, v_client_id, 'pending_payment', v_subtotal, 0.16, false, v_tax, v_total,
            v_user_id, 'pending', p_cart_id, 'card', v_address
        ) RETURNING id INTO v_order_id;

        -- Inserción agrupada de order_items con snapshot seguro
        FOR v_item IN 
            SELECT 
                c.product_id, 
                SUM(c.quantity) as total_qty,
                p.sku,
                p.name,
                p.category,
                p.unit_price_mxn
            FROM public.cart_items c
            JOIN public.products p ON c.product_id = p.id
            WHERE c.cart_id = p_cart_id
            GROUP BY c.product_id, p.sku, p.name, p.category, p.unit_price_mxn
        LOOP
            INSERT INTO public.order_items (
                order_id, product_id, sku_snapshot, product_name_snapshot, 
                product_category_snapshot, quantity, unit_price, total_line_price
            ) VALUES (
                v_order_id, v_item.product_id, v_item.sku, v_item.name,
                v_item.category, v_item.total_qty, v_item.unit_price_mxn, 
                ROUND(v_item.unit_price_mxn * v_item.total_qty, 2)
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'total', v_total,
        'subtotal', v_subtotal,
        'tax', v_tax,
        'reused', v_reused
    );
END;
$$ LANGUAGE plpgsql;
REVOKE EXECUTE ON FUNCTION public.prepare_web_checkout_order(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_web_checkout_order(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.prepare_web_checkout_order(uuid, uuid) TO authenticated;
-- Función de reconciliación web que usa order_payments
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

    -- PROTECCIÓN CONTRA REGRESIÓN: si ya estaba aprobado, no retroceder
    IF v_payment.status = 'approved' THEN
        v_mapped_status := 'approved'::public.payment_record_status;
        v_is_primary := v_payment.is_primary;

        -- Solo actualizamos metadatos seguros sin tocar payment_id ni date_approved.
        UPDATE public.order_payments
        SET last_webhook_at = now(),
            provider_updated_at = COALESCE(p_provider_updated_at, v_payment.provider_updated_at),
            raw_metadata = COALESCE(p_raw_metadata, raw_metadata, '{}'::jsonb),
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

        RETURN jsonb_build_object(
            'success', true,
            'order_id', v_order.id,
            'payment_status', 'approved'
        );
    END IF;

    -- Si llega aprobado y no estaba aprobado, validamos primario
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
        raw_metadata = COALESCE(p_raw_metadata, '{}'::jsonb),
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
