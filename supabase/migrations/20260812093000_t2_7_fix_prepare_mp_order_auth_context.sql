-- Migration: T2.7 fix prepare_mp_order backend auth context
-- Archivo local preparado para revisión. NO ejecutar db push.

CREATE OR REPLACE FUNCTION public.prepare_mp_order(
    p_user_id uuid,
    p_cart_id uuid,
    p_address_id uuid DEFAULT NULL,
    p_skydropx_quotation_id text DEFAULT NULL,
    p_skydropx_rate_id text DEFAULT NULL,
    p_selected_rate_total numeric DEFAULT 0,
    p_cheapest_valid_rate_total numeric DEFAULT 0,
    p_notes text DEFAULT NULL
)
RETURNS jsonb
SET search_path = pg_catalog, public, pg_temp
SECURITY DEFINER
AS $$
DECLARE
    v_user_id uuid;
    v_client_id uuid;
    v_order_id uuid;
    v_order_number text;
    v_payable_product_amount numeric(12,2) := 0;
    v_tax numeric(12,2) := 0;
    v_threshold numeric(12,2) := 5000;
    v_shipping_discount_amount numeric(12,2) := 0;
    v_customer_shipping_amount numeric(12,2) := 0;
    v_payment_total numeric(12,2) := 0;
    v_existing_order record;
    v_existing_payment record;
    v_item record;
    v_cart_count int;
    v_cart_active boolean;
    v_address text;
    v_reused boolean := false;
    v_mismatch boolean;
BEGIN
    -- 1. Identidad backend-only: la Edge Function debe pasar user.id verificado por getUser().
    v_user_id := p_user_id;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated user id required';
    END IF;

    SELECT client_id INTO v_client_id
    FROM public.profiles
    WHERE id = v_user_id
      AND is_active = true
      AND client_id IS NOT NULL;

    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Client profile not found or inactive';
    END IF;

    -- 2. Advisory lock transaccional por carrito
    PERFORM pg_advisory_xact_lock(hashtext(p_cart_id::text));

    -- 3. Validar carrito
    SELECT status = 'active'
    INTO v_cart_active
    FROM public.carts
    WHERE id = p_cart_id AND client_id = v_client_id
    FOR UPDATE;

    IF NOT FOUND OR NOT v_cart_active THEN
        RAISE EXCEPTION 'Cart not found or not active';
    END IF;

    SELECT COUNT(*) INTO v_cart_count FROM public.cart_items WHERE cart_id = p_cart_id;
    IF v_cart_count = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    -- 4. Obtener dirección
    IF p_address_id IS NOT NULL THEN
        SELECT concat_ws(', ', nullif(btrim(address), ''), nullif(btrim(city), ''), nullif(btrim(state), ''), nullif(btrim(postal_code), ''))
        INTO v_address
        FROM public.client_addresses
        WHERE id = p_address_id AND client_id = v_client_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Address not found or unauthorized';
        END IF;
    END IF;

    -- 5. Recalcular subtotal de productos desde catálogo BD
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

        IF NOT v_item.is_active OR NOT v_item.visible_in_app THEN
            RAISE EXCEPTION 'Product % is not active or visible', v_item.product_id;
        END IF;

        v_payable_product_amount := v_payable_product_amount + ROUND(v_item.unit_price_mxn * v_item.total_qty, 2);
    END LOOP;

    -- 6. IVA Desglose (16% incluido en precio de catálogo, NO recargado)
    v_tax := ROUND(v_payable_product_amount - (v_payable_product_amount / 1.16), 2);

    -- 7. Obtener umbral de envío gratis desde store_settings
    SELECT COALESCE(free_shipping_threshold, 5000)
    INTO v_threshold
    FROM public.store_settings
    LIMIT 1;

    IF v_threshold IS NULL THEN
        v_threshold := 5000;
    END IF;

    -- 8. Política Comercial de Envío Gratis
    IF COALESCE(p_selected_rate_total, 0) > 0 THEN
        IF v_payable_product_amount >= v_threshold THEN
            v_shipping_discount_amount := GREATEST(0, COALESCE(p_cheapest_valid_rate_total, p_selected_rate_total));
            v_customer_shipping_amount := GREATEST(0, ROUND(p_selected_rate_total - v_shipping_discount_amount, 2));
        ELSE
            v_shipping_discount_amount := 0;
            v_customer_shipping_amount := ROUND(p_selected_rate_total, 2);
        END IF;
    ELSE
        v_customer_shipping_amount := 0;
        v_shipping_discount_amount := 0;
    END IF;

    v_payment_total := v_payable_product_amount + v_customer_shipping_amount;

    IF v_payment_total <= 0 THEN
        RAISE EXCEPTION 'Payment total must be greater than zero';
    END IF;

    -- 9. Idempotencia y Reutilización de Orden
    SELECT id, order_number, subtotal, tax, total, customer_shipping_amount, status, payment_status
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
               AND v_existing_order.total = v_payment_total
               AND v_existing_order.subtotal = v_payable_product_amount
               AND COALESCE(v_existing_order.customer_shipping_amount, 0) = v_customer_shipping_amount THEN
                v_order_id := v_existing_order.id;
                v_order_number := v_existing_order.order_number;
                v_reused := true;
            ELSE
                IF EXISTS (
                    SELECT 1
                    FROM public.order_payments
                    WHERE order_id = v_existing_order.id
                      AND status = 'approved'::public.payment_record_status
                ) THEN
                    RAISE EXCEPTION 'El carrito cambió después de un pago aprobado.';
                END IF;

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
        v_order_number := 'ORD-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substring(md5(random()::text) from 1 for 8));

        INSERT INTO public.orders (
            order_number, client_id, status, subtotal, tax_pct, tax_exempt, tax, total,
            customer_shipping_amount, skydropx_shipping_cost, skydropx_quotation_id, skydropx_rate_id,
            shipping_discount_amount, created_by, payment_status, source_cart_id, payment_method,
            shipping_address, notes
        ) VALUES (
            v_order_number, v_client_id, 'pending_payment', v_payable_product_amount, 0.16, false, v_tax, v_payment_total,
            v_customer_shipping_amount, COALESCE(p_selected_rate_total, 0), p_skydropx_quotation_id, p_skydropx_rate_id,
            v_shipping_discount_amount, v_user_id, 'pending', p_cart_id, 'card',
            v_address, p_notes
        ) RETURNING id INTO v_order_id;

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

    -- 10. Idempotencia en order_payments (Reutilizar fila 'pending' para no duplicar ni causar error)
    SELECT id INTO v_existing_payment
    FROM public.order_payments
    WHERE order_id = v_order_id
      AND status = 'pending'::public.payment_record_status
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_existing_payment.id IS NOT NULL THEN
        UPDATE public.order_payments
        SET amount = v_payment_total,
            updated_at = now()
        WHERE id = v_existing_payment.id;
    ELSE
        INSERT INTO public.order_payments (
            order_id, client_id, provider, environment, external_reference,
            status, amount, currency_id, raw_metadata, is_primary
        ) VALUES (
            v_order_id, v_client_id, 'mercado_pago', 'test', v_order_number,
            'pending'::public.payment_record_status, v_payment_total, 'MXN', '{}'::jsonb, true
        );
    END IF;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'product_subtotal', v_payable_product_amount,
        'tax_breakdown', v_tax,
        'customer_shipping_amount', v_customer_shipping_amount,
        'skydropx_shipping_cost', COALESCE(p_selected_rate_total, 0),
        'shipping_discount_amount', v_shipping_discount_amount,
        'payment_total', v_payment_total,
        'reused', v_reused
    );
END;
$$ LANGUAGE plpgsql;
-- Restricción estricta de permisos: Solo ejecutable por service_role (Edge Functions backend).
REVOKE ALL ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) TO service_role;
-- La firma T2.6 dependía de auth.uid() bajo service_role y queda retirada para evitar overloads rotos.
DROP FUNCTION IF EXISTS public.prepare_mp_order(uuid, uuid, text, text, numeric, numeric, text);
