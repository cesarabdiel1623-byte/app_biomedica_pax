-- Migration: H5 Checkout SkydropX Coupons
-- Removes the artificial block on coupons in the web checkout and adds the transactional semantics from prepare_mp_order
-- Corrige el cart_fingerprint para mantener compatibilidad con la Edge Function desplegada (ROUND 0, toFixed 6)
-- Utiliza coupon_calculate_cart_pricing de forma autoritativa SIEMPRE
-- Conserva centavos en cálculos financieros

CREATE OR REPLACE FUNCTION public.prepare_web_checkout_order_with_shipping(
    p_cart_id uuid,
    p_address_id uuid,
    p_shipping_quote_id uuid
)
RETURNS jsonb
SET search_path = pg_catalog, public
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
    
    v_cart_count int;
    v_cart_active boolean;
    v_has_coupon boolean;
    v_applied_coupon_code text;
    v_cart_applied_coupon_id uuid;
    v_cart_tax_pct numeric;
    v_cart_tax_exempt boolean;
    
    v_address_raw text;
    v_address text;
    v_dest_country_code text := 'MX';
    v_dest_postal_code text;
    v_dest_state text;
    v_dest_city text;
    v_destination_fingerprint text;

    v_item record;
    v_effective_product_subtotal numeric(12,2) := 0;
    v_payable_product_amount numeric(12,2) := 0;
    v_tax numeric(12,2) := 0;
    v_total numeric(12,2) := 0;
    v_base_unit numeric(12,2);
    v_promo_unit numeric(12,2);
    v_commercial_unit numeric(12,2);
    
    v_fingerprint_base_unit numeric(12,2);
    v_fingerprint_promo_unit numeric(12,2);
    v_fingerprint_commercial_unit numeric(12,2);
    
    v_coupon_pricing jsonb;
    v_coupon_discount_amount numeric(12,2) := 0;
    v_coupon_free_shipping boolean := false;
    v_coupon_snapshot jsonb;
    v_coupon_id uuid;

    v_order_id uuid;
    v_order_number text;
    v_existing_order record;
    v_mismatch boolean;
    v_reused boolean := false;
    
    -- Lógica Logística
    v_quote record;
    v_cart_fingerprint text := '';
    v_shipping_discount_amount numeric(12,2) := 0;
    v_customer_shipping_amount numeric(12,2) := 0;
    
    v_loop_subtotal numeric(12,2) := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Resolución EXACTA de la versión estable actual
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
      AND p.is_active = true
      AND p.client_id IS NOT NULL;

    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Client profile not found, inactive or client_id is null';
    END IF;

    -- Cálculo del snapshot comercial
    v_client_name_snapshot := COALESCE(
        NULLIF(btrim(v_business_name), ''),
        NULLIF(btrim(v_contact_name), ''),
        NULLIF(btrim(v_profile_full_name), ''),
        NULLIF(btrim(v_profile_email), '')
    );

    IF v_client_name_snapshot IS NULL THEN
        RAISE EXCEPTION 'No se pudo determinar un nombre o correo válido para el cliente';
    END IF;

    -- Bloqueo transaccional
    PERFORM pg_advisory_xact_lock(hashtext(p_cart_id::text));

    -- Validar carrito
    SELECT 
        status = 'active', 
        (applied_coupon_id IS NOT NULL OR applied_coupon_code IS NOT NULL),
        COALESCE(
            NULLIF(btrim(applied_coupon_code), ''),
            (SELECT code FROM public.coupons WHERE id = carts.applied_coupon_id)
        ),
        tax_pct,
        tax_exempt,
        applied_coupon_id
    INTO v_cart_active, v_has_coupon, v_applied_coupon_code, v_cart_tax_pct, v_cart_tax_exempt, v_cart_applied_coupon_id
    FROM public.carts 
    WHERE id = p_cart_id AND client_id = v_client_id 
    FOR UPDATE;

    IF NOT FOUND OR NOT v_cart_active THEN
        RAISE EXCEPTION 'Cart not found, unauthorized or not active';
    END IF;

    SELECT COUNT(*) INTO v_cart_count FROM public.cart_items WHERE cart_id = p_cart_id;
    IF v_cart_count = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    -- Validar dirección de envío
    SELECT 
        concat_ws(', ', nullif(btrim(address), ''), nullif(btrim(city), ''), nullif(btrim(state), ''), nullif(btrim(postal_code), '')),
        nullif(btrim(address), ''),
        nullif(btrim(postal_code), ''),
        nullif(btrim(state), ''),
        nullif(btrim(city), '')
    INTO v_address, v_address_raw, v_dest_postal_code, v_dest_state, v_dest_city
    FROM public.client_addresses
    WHERE id = p_address_id AND client_id = v_client_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Address not found or unauthorized';
    END IF;
    
    -- Destination fingerprint: formato exacto del quote
    v_destination_fingerprint := v_dest_country_code || '|' || COALESCE(btrim(v_dest_postal_code), '') || '|' || COALESCE(btrim(v_dest_state), '') || '|' || COALESCE(btrim(v_dest_city), '') || '|' || COALESCE(btrim(v_address_raw), '');

    -- Validar existencia del id de quote
    IF p_shipping_quote_id IS NULL THEN
        RAISE EXCEPTION 'Un pedido con dirección de entrega requiere seleccionar una tarifa de envío (ID de quote requerido).';
    END IF;

    -- Búsqueda segura del quote usando su id interno y validando su scope real
    SELECT * INTO v_quote
    FROM public.cart_shipping_quotes
    WHERE id = p_shipping_quote_id
      AND cart_id = p_cart_id
      AND client_id = v_client_id
      AND address_id = p_address_id
      AND expires_at > now()
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tarifa de envío no encontrada o expirada. Por favor, cotiza nuevamente.';
    END IF;

    -- Calcular Logistics-Aware Cart Fingerprint manteniendo compatibilidad con la EF (ROUND 0, toFixed 6)
    v_cart_fingerprint := '';
    FOR v_item IN 
        SELECT 
            c.product_id, 
            SUM(c.quantity) as total_qty,
            MAX(p.unit_price_mxn) as unit_price_mxn,
            ld.package_length,
            ld.package_width,
            ld.package_height,
            ld.package_weight
        FROM public.cart_items c
        JOIN public.products p ON c.product_id = p.id
        JOIN public.product_logistics_data ld ON c.product_id = ld.product_id
        WHERE c.cart_id = p_cart_id
        GROUP BY c.product_id, ld.package_length, ld.package_width, ld.package_height, ld.package_weight
        ORDER BY c.product_id
    LOOP
        IF v_item.total_qty <= 0 OR v_item.total_qty <> trunc(v_item.total_qty) THEN
            RAISE EXCEPTION 'Invalid quantity for product %', v_item.product_id;
        END IF;

        -- Compatibilidad exacta con skydropx-web-quote: Math.round(Math.max(val, 0))
        v_fingerprint_base_unit := ROUND(GREATEST(v_item.unit_price_mxn, 0), 0);
        
        SELECT MIN(ROUND(GREATEST(0, promotional_price_mxn), 0))
        INTO v_fingerprint_promo_unit
        FROM public.active_product_promotions
        WHERE product_id = v_item.product_id;
        
        IF v_fingerprint_promo_unit IS NOT NULL THEN
            v_fingerprint_commercial_unit := LEAST(v_fingerprint_base_unit, v_fingerprint_promo_unit);
        ELSE
            v_fingerprint_commercial_unit := v_fingerprint_base_unit;
        END IF;

        v_cart_fingerprint := v_cart_fingerprint || 
            v_item.product_id::text || ':' || 
            v_item.total_qty::bigint::text || ':' || 
            TO_CHAR(v_fingerprint_commercial_unit::numeric, 'FM9999999990.000000') || ':' ||
            TO_CHAR(v_item.package_length::numeric, 'FM9999999990.000000') || ':' ||
            TO_CHAR(v_item.package_width::numeric, 'FM9999999990.000000') || ':' ||
            TO_CHAR(v_item.package_height::numeric, 'FM9999999990.000000') || ':' ||
            TO_CHAR(v_item.package_weight::numeric, 'FM9999999990.000000') || '|';
    END LOOP;

    IF v_quote.cart_fingerprint != v_cart_fingerprint THEN
        RAISE EXCEPTION 'La composición logística o precios del carrito han cambiado. Por favor, cotiza nuevamente.';
    END IF;
    
    IF v_quote.destination_fingerprint != v_destination_fingerprint THEN
        RAISE EXCEPTION 'La dirección de entrega ha cambiado. Por favor, cotiza nuevamente.';
    END IF;

    -- Iterar items para validaciones de disponibilidad e integridad (subtotal)
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

        -- Financiero: Conservar centavos
        v_base_unit := ROUND(GREATEST(v_item.unit_price_mxn, 0), 2);
        
        SELECT MIN(ROUND(GREATEST(0, promotional_price_mxn), 2))
        INTO v_promo_unit
        FROM public.active_product_promotions
        WHERE product_id = v_item.product_id;
        
        IF v_promo_unit IS NOT NULL THEN
            v_commercial_unit := LEAST(v_base_unit, v_promo_unit);
        ELSE
            v_commercial_unit := v_base_unit;
        END IF;
        
        v_commercial_unit := ROUND(v_commercial_unit, 2);
        v_loop_subtotal := v_loop_subtotal + ROUND(v_commercial_unit * v_item.total_qty, 2);
    END LOOP;
    
    v_loop_subtotal := ROUND(v_loop_subtotal, 2);

    -- Pricing Autoritativo para TODO carrito
    v_coupon_pricing := public.coupon_calculate_cart_pricing(
        p_cart_id,
        v_applied_coupon_code,
        true -- p_enforce_owner
    );

    IF COALESCE((v_coupon_pricing ->> 'valid')::boolean, false) IS NOT TRUE THEN
        IF v_has_coupon THEN
            RAISE EXCEPTION 'El cupón aplicado ya no es válido o aplicable a este carrito.';
        ELSE
            RAISE EXCEPTION 'Error validando precios del carrito.';
        END IF;
    END IF;

    -- Procesamiento de Cupón Canónico
    IF jsonb_typeof(v_coupon_pricing -> 'coupon') = 'object' THEN
        v_coupon_id := (v_coupon_pricing -> 'coupon' ->> 'id')::uuid;
        v_coupon_snapshot := v_coupon_pricing -> 'coupon';
        
        -- Validación de consistencia del ID
        IF v_cart_applied_coupon_id IS NOT NULL AND v_cart_applied_coupon_id != v_coupon_id THEN
            RAISE EXCEPTION 'Inconsistencia de cupón: el ID canónico difiere del carrito.';
        END IF;

        -- Validación de consistencia del código ignorando normalización
        IF v_applied_coupon_code IS NOT NULL AND lower(btrim(v_applied_coupon_code)) != lower(btrim(v_coupon_pricing -> 'coupon' ->> 'code')) THEN
            RAISE EXCEPTION 'Inconsistencia de cupón: el código canónico difiere del carrito.';
        END IF;

        -- Asignación final autoritativa
        v_applied_coupon_code := v_coupon_pricing -> 'coupon' ->> 'code';
        
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
    ELSE
        IF v_has_coupon THEN
            RAISE EXCEPTION 'Inconsistencia en el cupón: no se pudo resolver el cupón aplicado de forma segura.';
        END IF;

        -- Reset estricto para carritos sin cupón
        v_coupon_id := NULL;
        v_applied_coupon_code := NULL;
        v_coupon_snapshot := NULL;
        v_coupon_discount_amount := 0;
        v_coupon_free_shipping := false;
    END IF;

    -- Extraer valores autoritativos
    v_effective_product_subtotal := ROUND(
        COALESCE((v_coupon_pricing -> 'amounts' ->> 'items_subtotal')::numeric, 0) - 
        COALESCE((v_coupon_pricing -> 'amounts' ->> 'product_discount')::numeric, 0), 2
    );
    
    IF v_effective_product_subtotal != v_loop_subtotal THEN
        RAISE EXCEPTION 'Discrepancia detectada en los precios de los productos.';
    END IF;

    v_payable_product_amount := ROUND(GREATEST(v_effective_product_subtotal - v_coupon_discount_amount, 0), 2);
    v_tax := ROUND(COALESCE((v_coupon_pricing -> 'amounts' ->> 'tax')::numeric, 0), 2);

    -- Shipping processing
    v_customer_shipping_amount := ROUND(COALESCE(v_quote.customer_shipping_amount, 0), 2);
    v_shipping_discount_amount := ROUND(COALESCE(v_quote.shipping_discount_amount, 0), 2);
    
    IF v_coupon_free_shipping THEN
        v_shipping_discount_amount := ROUND(COALESCE(v_quote.provider_total, 0), 2);
        v_customer_shipping_amount := 0;
    END IF;

    -- Total final
    v_total := ROUND(GREATEST(v_payable_product_amount + v_customer_shipping_amount, 0), 2);

    IF v_total <= 0 THEN
        RAISE EXCEPTION 'Order total must be greater than zero. El checkout no admite órdenes 100%% gratuitas.';
    END IF;

    -- Buscar orden existente
    SELECT id, order_number, subtotal, tax, total, status, payment_status, client_name_snapshot,
           skydropx_quotation_id, skydropx_rate_id, skydropx_shipping_cost, shipping_discount_amount, customer_shipping_amount,
           coupon_id, coupon_code, coupon_discount_amount
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
                    SELECT c.product_id, SUM(c.quantity) AS qty, 
                        MAX(ROUND(
                            COALESCE(
                                LEAST(
                                    ROUND(GREATEST(p.unit_price_mxn, 0), 2),
                                    (SELECT MIN(ROUND(GREATEST(0, promotional_price_mxn), 2)) FROM public.active_product_promotions WHERE product_id = p.id)
                                ),
                                ROUND(GREATEST(p.unit_price_mxn, 0), 2)
                            ), 2
                        )) AS price
                    FROM public.cart_items c
                    JOIN public.products p ON p.id = c.product_id
                    WHERE c.cart_id = p_cart_id
                    GROUP BY c.product_id
                )
                UNION ALL
                (
                    SELECT c.product_id, SUM(c.quantity) AS qty, 
                        MAX(ROUND(
                            COALESCE(
                                LEAST(
                                    ROUND(GREATEST(p.unit_price_mxn, 0), 2),
                                    (SELECT MIN(ROUND(GREATEST(0, promotional_price_mxn), 2)) FROM public.active_product_promotions WHERE product_id = p.id)
                                ),
                                ROUND(GREATEST(p.unit_price_mxn, 0), 2)
                            ), 2
                        )) AS price
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
               AND v_existing_order.subtotal = v_effective_product_subtotal
               AND v_existing_order.tax = v_tax 
               AND COALESCE(v_existing_order.coupon_discount_amount, 0) = v_coupon_discount_amount
               AND COALESCE(v_existing_order.shipping_discount_amount, 0) = v_shipping_discount_amount
               AND COALESCE(v_existing_order.customer_shipping_amount, 0) = v_customer_shipping_amount
               AND v_existing_order.total = v_total
               AND COALESCE(v_existing_order.coupon_id::text, '') = COALESCE(v_coupon_id::text, '')
               AND COALESCE(v_existing_order.coupon_code, '') = COALESCE(v_applied_coupon_code, '') THEN
               
                -- Validar inmutabilidad si ya hay un pago en vuelo (NO CAMBIAR SNAPSHOT TRAS PAYMENT ATTEMPT)
                IF EXISTS (
                    SELECT 1 FROM public.order_payments WHERE order_id = v_existing_order.id
                ) THEN
                    IF v_existing_order.skydropx_quotation_id IS DISTINCT FROM v_quote.quotation_id OR
                       v_existing_order.skydropx_rate_id IS DISTINCT FROM v_quote.rate_id OR
                       v_existing_order.skydropx_shipping_cost IS DISTINCT FROM v_quote.provider_total THEN
                        RAISE EXCEPTION 'No se puede modificar el tipo de envío porque ya existe un intento de pago activo.';
                    END IF;
                    
                    v_order_id := v_existing_order.id;
                    v_order_number := v_existing_order.order_number;
                    v_reused := true;
                    
                    -- Reutilizar sin mutar snapshot original
                    UPDATE public.orders
                    SET client_name_snapshot = COALESCE(NULLIF(btrim(v_existing_order.client_name_snapshot), ''), v_client_name_snapshot),
                        updated_at = now()
                    WHERE id = v_order_id;
                ELSE
                    v_order_id := v_existing_order.id;
                    v_order_number := v_existing_order.order_number;
                    v_reused := true;
                    
                    -- Actualizar porque aún no hay intentos de pago
                    UPDATE public.orders
                    SET client_name_snapshot = COALESCE(NULLIF(btrim(v_existing_order.client_name_snapshot), ''), v_client_name_snapshot),
                        skydropx_quotation_id = v_quote.quotation_id,
                        skydropx_rate_id = v_quote.rate_id,
                        skydropx_shipping_cost = v_quote.provider_total,
                        shipping_discount_amount = v_shipping_discount_amount,
                        customer_shipping_amount = v_customer_shipping_amount,
                        coupon_id = v_coupon_id,
                        coupon_code = v_applied_coupon_code,
                        coupon_discount_amount = v_coupon_discount_amount,
                        coupon_snapshot = v_coupon_snapshot,
                        tax = v_tax,
                        tax_pct = COALESCE(v_cart_tax_pct, 0.16),
                        tax_exempt = COALESCE(v_cart_tax_exempt, false),
                        total = v_total,
                        updated_at = now()
                    WHERE id = v_order_id;
                END IF;
            ELSE
                IF EXISTS (
                    SELECT 1 FROM public.order_payments WHERE order_id = v_existing_order.id
                ) THEN
                    RAISE EXCEPTION 'El carrito o promociones cambiaron después de iniciar un intento de pago. Crea un carrito nuevo para continuar.';
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
            created_by, payment_status, source_cart_id, payment_method, shipping_address, client_name_snapshot,
            customer_shipping_amount, skydropx_shipping_cost, skydropx_quotation_id, skydropx_rate_id, shipping_discount_amount,
            coupon_id, coupon_code, coupon_discount_amount, coupon_snapshot
        ) VALUES (
            v_order_number, v_client_id, 'pending_payment', v_effective_product_subtotal, COALESCE(v_cart_tax_pct, 0.16), COALESCE(v_cart_tax_exempt, false), v_tax, v_total,
            v_user_id, 'pending', p_cart_id, 'card', v_address, v_client_name_snapshot,
            v_customer_shipping_amount, v_quote.provider_total, v_quote.quotation_id, v_quote.rate_id, v_shipping_discount_amount,
            v_coupon_id, v_applied_coupon_code, v_coupon_discount_amount, v_coupon_snapshot
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
            v_base_unit := ROUND(GREATEST(v_item.unit_price_mxn, 0), 2);
            
            SELECT MIN(ROUND(GREATEST(0, promotional_price_mxn), 2))
            INTO v_promo_unit
            FROM public.active_product_promotions
            WHERE product_id = v_item.product_id;
            
            IF v_promo_unit IS NOT NULL THEN
                v_commercial_unit := LEAST(v_base_unit, v_promo_unit);
            ELSE
                v_commercial_unit := v_base_unit;
            END IF;
            
            v_commercial_unit := ROUND(v_commercial_unit, 2);

            INSERT INTO public.order_items (
                order_id, product_id, sku_snapshot, product_name_snapshot, 
                product_category_snapshot, quantity, unit_price, total_line_price
            ) VALUES (
                v_order_id, v_item.product_id, v_item.sku, v_item.name,
                v_item.category, v_item.total_qty, v_commercial_unit, 
                ROUND(v_commercial_unit * v_item.total_qty, 2)
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'total', v_total,
        'subtotal', v_effective_product_subtotal,
        'tax', v_tax,
        'shipping', v_customer_shipping_amount,
        'reused', v_reused,
        'coupon_code', v_applied_coupon_code,
        'coupon_discount_amount', v_coupon_discount_amount,
        'shipping_discount_amount', v_shipping_discount_amount
    );
END;
$$ LANGUAGE plpgsql;
REVOKE EXECUTE ON FUNCTION public.prepare_web_checkout_order_with_shipping(uuid, uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_web_checkout_order_with_shipping(uuid, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.prepare_web_checkout_order_with_shipping(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_web_checkout_order_with_shipping(uuid, uuid, uuid) TO service_role;
