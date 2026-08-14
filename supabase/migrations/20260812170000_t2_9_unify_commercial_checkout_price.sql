-- Migration: T2.9 unify commercial payable product price.
-- NO ejecutar db push sin autorización.
--
-- Regla única:
-- - Con promoción activa: ROUND(active_product_promotions.promotional_price_mxn, 0)
-- - Sin promoción: ROUND(products.unit_price_mxn, 0)
-- Ese precio comercial efectivo se usa para subtotal, order_items y payment_total.

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
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
    v_user_id uuid;
    v_client_id uuid;
    v_order_id uuid;
    v_order_number text;
    v_effective_product_subtotal numeric(12,2) := 0;
    v_payable_product_amount numeric(12,2) := 0;
    v_coupon_discount_amount numeric(12,2) := 0;
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
    v_applied_coupon_code text;
    v_coupon_pricing jsonb;
    v_coupon_free_shipping boolean := false;
    v_address text;
    v_reused boolean := false;
    v_mismatch boolean;
    v_base_unit numeric(12,2);
    v_effective_unit numeric(12,2);
    v_commercial_unit_price numeric(12,2);
BEGIN
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

    PERFORM pg_advisory_xact_lock(hashtext(p_cart_id::text));

    SELECT
        c.status = 'active',
        COALESCE(
            NULLIF(BTRIM(c.applied_coupon_code), ''),
            (
                SELECT cp.code
                FROM public.coupons cp
                WHERE cp.id = c.applied_coupon_id
            )
        )
    INTO v_cart_active, v_applied_coupon_code
    FROM public.carts c
    WHERE c.id = p_cart_id AND c.client_id = v_client_id
    FOR UPDATE;

    IF NOT FOUND OR NOT v_cart_active THEN
        RAISE EXCEPTION 'Cart not found or not active';
    END IF;

    SELECT COUNT(*) INTO v_cart_count FROM public.cart_items WHERE cart_id = p_cart_id;
    IF v_cart_count = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    IF p_address_id IS NOT NULL THEN
        SELECT concat_ws(', ', nullif(btrim(address), ''), nullif(btrim(city), ''), nullif(btrim(state), ''), nullif(btrim(postal_code), ''))
        INTO v_address
        FROM public.client_addresses
        WHERE id = p_address_id AND client_id = v_client_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Address not found or unauthorized';
        END IF;
    END IF;

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

        v_base_unit := ROUND(GREATEST(v_item.unit_price_mxn, 0), 0);

        SELECT LEAST(
            v_base_unit,
            COALESCE(MIN(ROUND(GREATEST(0, app.promotional_price_mxn), 0)), v_base_unit)
        )
        INTO v_effective_unit
        FROM public.active_product_promotions app
        WHERE app.product_id = v_item.product_id;

        v_commercial_unit_price := ROUND(COALESCE(v_effective_unit, v_base_unit), 2);

        IF v_commercial_unit_price <= 0 THEN
            RAISE EXCEPTION 'Product % has invalid payable price', v_item.product_id;
        END IF;

        v_effective_product_subtotal := v_effective_product_subtotal
            + ROUND(v_commercial_unit_price * v_item.total_qty, 2);
    END LOOP;

    v_effective_product_subtotal := ROUND(v_effective_product_subtotal, 2);

    IF v_applied_coupon_code IS NOT NULL THEN
        v_coupon_pricing := public.coupon_calculate_cart_pricing(
            p_cart_id,
            v_applied_coupon_code,
            false
        );

        IF COALESCE((v_coupon_pricing ->> 'valid')::boolean, false) IS NOT TRUE THEN
            RAISE EXCEPTION 'Applied coupon is no longer valid';
        END IF;

        v_coupon_discount_amount := ROUND(
            GREATEST(
                COALESCE(
                    (v_coupon_pricing -> 'amounts' ->> 'coupon_discount')::numeric,
                    0
                ),
                0
            ),
            2
        );
        v_coupon_free_shipping := COALESCE(
            v_coupon_pricing -> 'coupon' ->> 'discount_type',
            ''
        ) = 'free_shipping';
    END IF;

    v_payable_product_amount := ROUND(
        GREATEST(v_effective_product_subtotal - v_coupon_discount_amount, 0),
        2
    );
    v_tax := ROUND(v_payable_product_amount - (v_payable_product_amount / 1.16), 2);

    SELECT COALESCE(free_shipping_threshold, 5000)
    INTO v_threshold
    FROM public.store_settings
    LIMIT 1;

    IF v_threshold IS NULL THEN
        v_threshold := 5000;
    END IF;

    IF COALESCE(p_selected_rate_total, 0) > 0 THEN
        IF v_effective_product_subtotal >= v_threshold THEN
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

    IF v_coupon_free_shipping THEN
        v_shipping_discount_amount := ROUND(
            GREATEST(COALESCE(p_selected_rate_total, 0), 0),
            2
        );
        v_customer_shipping_amount := 0;
    END IF;

    v_payment_total := ROUND(v_payable_product_amount + v_customer_shipping_amount, 2);

    IF v_payment_total <= 0 THEN
        RAISE EXCEPTION 'Payment total must be greater than zero';
    END IF;

    SELECT
        id,
        order_number,
        subtotal,
        tax,
        total,
        coupon_discount_amount,
        customer_shipping_amount,
        status,
        payment_status
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
                    SELECT
                        c.product_id,
                        SUM(c.quantity) AS qty,
                        MAX(ROUND(COALESCE(prom.effective_unit_price, ROUND(GREATEST(p.unit_price_mxn, 0), 0)), 2)) AS price
                    FROM public.cart_items c
                    JOIN public.products p ON p.id = c.product_id
                    LEFT JOIN LATERAL (
                        SELECT LEAST(
                            ROUND(GREATEST(p.unit_price_mxn, 0), 0),
                            MIN(ROUND(GREATEST(0, app.promotional_price_mxn), 0))
                        ) AS effective_unit_price
                        FROM public.active_product_promotions app
                        WHERE app.product_id = p.id
                    ) prom ON true
                    WHERE c.cart_id = p_cart_id
                    GROUP BY c.product_id
                )
                UNION ALL
                (
                    SELECT
                        c.product_id,
                        SUM(c.quantity) AS qty,
                        MAX(ROUND(COALESCE(prom.effective_unit_price, ROUND(GREATEST(p.unit_price_mxn, 0), 0)), 2)) AS price
                    FROM public.cart_items c
                    JOIN public.products p ON p.id = c.product_id
                    LEFT JOIN LATERAL (
                        SELECT LEAST(
                            ROUND(GREATEST(p.unit_price_mxn, 0), 0),
                            MIN(ROUND(GREATEST(0, app.promotional_price_mxn), 0))
                        ) AS effective_unit_price
                        FROM public.active_product_promotions app
                        WHERE app.product_id = p.id
                    ) prom ON true
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
               AND v_existing_order.subtotal = v_effective_product_subtotal
               AND COALESCE(v_existing_order.coupon_discount_amount, 0) = v_coupon_discount_amount
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
            shipping_discount_amount, coupon_discount_amount, created_by, payment_status, source_cart_id, payment_method,
            shipping_address, notes
        ) VALUES (
            v_order_number, v_client_id, 'pending_payment', v_effective_product_subtotal, 0.16, false, v_tax, v_payment_total,
            v_customer_shipping_amount, COALESCE(p_selected_rate_total, 0), p_skydropx_quotation_id, p_skydropx_rate_id,
            v_shipping_discount_amount, v_coupon_discount_amount, v_user_id, 'pending', p_cart_id, 'card',
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
            v_base_unit := ROUND(GREATEST(v_item.unit_price_mxn, 0), 0);

            SELECT LEAST(
                v_base_unit,
                COALESCE(MIN(ROUND(GREATEST(0, app.promotional_price_mxn), 0)), v_base_unit)
            )
            INTO v_effective_unit
            FROM public.active_product_promotions app
            WHERE app.product_id = v_item.product_id;

            v_commercial_unit_price := ROUND(COALESCE(v_effective_unit, v_base_unit), 2);

            INSERT INTO public.order_items (
                order_id, product_id, sku_snapshot, product_name_snapshot,
                product_category_snapshot, quantity, unit_price, total_line_price
            ) VALUES (
                v_order_id, v_item.product_id, v_item.sku, v_item.name,
                v_item.category, v_item.total_qty, v_commercial_unit_price,
                ROUND(v_commercial_unit_price * v_item.total_qty, 2)
            );
        END LOOP;
    END IF;

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
        'product_subtotal', v_effective_product_subtotal,
        'coupon_discount_amount', v_coupon_discount_amount,
        'tax_breakdown', v_tax,
        'customer_shipping_amount', v_customer_shipping_amount,
        'skydropx_shipping_cost', COALESCE(p_selected_rate_total, 0),
        'shipping_discount_amount', v_shipping_discount_amount,
        'payment_total', v_payment_total,
        'reused', v_reused,
        'pricing_source', 't2_9_commercial_price_0dp'
    );
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) TO service_role;
