-- Migration: Fix Order Client Name Snapshot

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
    v_profile_full_name text;
    v_profile_email text;
    v_business_name text;
    v_contact_name text;
    v_client_name_snapshot text;
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
    -- 1 & 2. Autenticación y client_id con datos para snapshot
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT 
        p.client_id, 
        p.full_name, 
        p.email, 
        c.business_name, 
        c.contact_name 
    INTO 
        v_client_id, 
        v_profile_full_name, 
        v_profile_email, 
        v_business_name, 
        v_contact_name
    FROM public.profiles p
    LEFT JOIN public.clients c ON p.client_id = c.id
    WHERE p.id = v_user_id 
      AND p.is_active = true;

    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Client profile not found, inactive or client_id is null';
    END IF;

    -- Cálculo del snapshot
    v_client_name_snapshot := COALESCE(
        NULLIF(btrim(v_business_name), ''),
        NULLIF(btrim(v_contact_name), ''),
        NULLIF(btrim(v_profile_full_name), ''),
        NULLIF(btrim(v_profile_email), '')
    );

    IF v_client_name_snapshot IS NULL THEN
        RAISE EXCEPTION 'No se pudo determinar un nombre o correo válido para el cliente';
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
    SELECT id, order_number, subtotal, tax, total, status, payment_status, client_name_snapshot
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
                
                -- Si la orden reutilizada no tiene snapshot, completarlo
                IF NULLIF(btrim(v_existing_order.client_name_snapshot), '') IS NULL THEN
                    UPDATE public.orders
                    SET client_name_snapshot = v_client_name_snapshot,
                        updated_at = now()
                    WHERE id = v_order_id;
                END IF;
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
            created_by, payment_status, source_cart_id, payment_method, shipping_address, client_name_snapshot
        ) VALUES (
            v_order_number, v_client_id, 'pending_payment', v_subtotal, 0.16, false, v_tax, v_total,
            v_user_id, 'pending', p_cart_id, 'card', v_address, v_client_name_snapshot
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
