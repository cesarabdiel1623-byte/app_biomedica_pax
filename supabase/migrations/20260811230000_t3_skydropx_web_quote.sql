-- T3 SKYDROPX WEB - HARDENING FINAL PRE-DEPLOY

-- 1. Crear tabla cart_shipping_quotes dedicada y segura
CREATE TABLE IF NOT EXISTS public.cart_shipping_quotes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id uuid NOT NULL REFERENCES public.carts(id) ON DELETE CASCADE,
    client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    address_id uuid NOT NULL REFERENCES public.client_addresses(id) ON DELETE CASCADE,
    
    quotation_id text NOT NULL,
    rate_id text NOT NULL,
    
    carrier text,
    service_name text,
    currency text NOT NULL CHECK (currency = 'MXN'),
    
    provider_total numeric NOT NULL CHECK (provider_total >= 0),
    customer_shipping_amount numeric NOT NULL CHECK (customer_shipping_amount >= 0),
    shipping_discount_amount numeric NOT NULL CHECK (shipping_discount_amount >= 0),
    
    cart_fingerprint text NOT NULL,
    destination_fingerprint text NOT NULL,
    
    quoted_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL CHECK (expires_at > quoted_at),
    created_at timestamptz NOT NULL DEFAULT now(),
    
    UNIQUE (quotation_id, rate_id)
);
-- Crear índice útil para lookup (asegura búsquedas por id y previene filas ambiguas)
CREATE INDEX IF NOT EXISTS idx_cart_shipping_quotes_lookup 
ON public.cart_shipping_quotes (id, cart_id, client_id, address_id, expires_at);
-- 2. RLS / GRANTS EXPLÍCITOS
ALTER TABLE public.cart_shipping_quotes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cart_shipping_quotes FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.cart_shipping_quotes FROM anon, authenticated;
GRANT SELECT ON public.cart_shipping_quotes TO authenticated;
-- Asumiendo que get_my_client_id existe y es la convención del proyecto
CREATE POLICY "Users can view their own quotes" 
ON public.cart_shipping_quotes
FOR SELECT
TO authenticated
USING (client_id = public.get_my_client_id());
-- 3. NUEVA RPC (NO ROMPER RPC ACTUAL)
-- public.prepare_web_checkout_order_with_shipping(p_cart_id uuid, p_address_id uuid, p_shipping_quote_id uuid)

CREATE OR REPLACE FUNCTION public.prepare_web_checkout_order_with_shipping(
    p_cart_id uuid,
    p_address_id uuid,
    p_shipping_quote_id uuid
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
    
    v_cart_count int;
    v_cart_active boolean;
    v_has_coupon boolean;
    
    v_address_raw text;
    v_address text;
    v_dest_country_code text := 'MX';
    v_dest_postal_code text;
    v_dest_state text;
    v_dest_city text;
    v_destination_fingerprint text;

    v_item record;
    v_subtotal numeric(12,2) := 0;
    v_tax numeric(12,2) := 0;
    v_total numeric(12,2) := 0;
    v_order_id uuid;
    v_order_number text;
    v_existing_order record;
    v_mismatch boolean;
    v_reused boolean := false;
    
    -- Lógica Logística
    v_quote record;
    v_cart_fingerprint text := '';
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Resolución EXACTA de la versión estable actual (Sin first_name ni last_name)
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

    -- Calcular Logistics-Aware Cart Fingerprint Financiero
    -- Formato: product_id:quantity:unit_price_mxn:package_length:package_width:package_height:package_weight|
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

        v_cart_fingerprint := v_cart_fingerprint || 
            v_item.product_id::text || ':' || 
            v_item.total_qty::bigint::text || ':' || 
            TO_CHAR(v_item.unit_price_mxn::numeric, 'FM9999999990.000000') || ':' ||
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

    -- Iterar items para el subtotal y validaciones de disponibilidad
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

    -- Total: subtotal + tax + customer_shipping_amount
    v_tax := ROUND(v_subtotal * 0.16, 2);
    v_total := v_subtotal + v_tax + v_quote.customer_shipping_amount;

    IF v_total <= 0 THEN
        RAISE EXCEPTION 'Order total must be greater than zero';
    END IF;

    -- Buscar orden existente
    SELECT id, order_number, subtotal, tax, total, status, payment_status, client_name_snapshot,
           skydropx_quotation_id, skydropx_rate_id, skydropx_shipping_cost, shipping_discount_amount, customer_shipping_amount
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
               AND v_existing_order.subtotal = v_subtotal
               AND v_existing_order.tax = v_tax THEN
               
                -- Validar logística inmutable si ya hay un pago en vuelo (NO CAMBIAR TRAS PAYMENT ATTEMPT)
                IF EXISTS (
                    SELECT 1 FROM public.order_payments WHERE order_id = v_existing_order.id
                ) THEN
                    IF v_existing_order.skydropx_quotation_id IS DISTINCT FROM v_quote.quotation_id OR
                       v_existing_order.skydropx_rate_id IS DISTINCT FROM v_quote.rate_id OR
                       v_existing_order.skydropx_shipping_cost IS DISTINCT FROM v_quote.provider_total OR
                       v_existing_order.shipping_discount_amount IS DISTINCT FROM v_quote.shipping_discount_amount OR
                       v_existing_order.customer_shipping_amount IS DISTINCT FROM v_quote.customer_shipping_amount THEN
                        RAISE EXCEPTION 'No se puede modificar el tipo de envío porque ya existe un intento de pago activo.';
                    END IF;
                END IF;
                
                v_order_id := v_existing_order.id;
                v_order_number := v_existing_order.order_number;
                v_reused := true;
                
                -- Actualizar logística si no rompió la validación anterior
                UPDATE public.orders
                SET client_name_snapshot = COALESCE(NULLIF(btrim(v_existing_order.client_name_snapshot), ''), v_client_name_snapshot),
                    skydropx_quotation_id = v_quote.quotation_id,
                    skydropx_rate_id = v_quote.rate_id,
                    skydropx_shipping_cost = v_quote.provider_total,
                    shipping_discount_amount = v_quote.shipping_discount_amount,
                    customer_shipping_amount = v_quote.customer_shipping_amount,
                    total = v_total,
                    updated_at = now()
                WHERE id = v_order_id;
            ELSE
                IF EXISTS (
                    SELECT 1 FROM public.order_payments WHERE order_id = v_existing_order.id
                ) THEN
                    RAISE EXCEPTION 'El carrito cambió después de iniciar un intento de pago. Crea un carrito nuevo para continuar.';
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
            customer_shipping_amount, skydropx_shipping_cost, skydropx_quotation_id, skydropx_rate_id, shipping_discount_amount
        ) VALUES (
            v_order_number, v_client_id, 'pending_payment', v_subtotal, 0.16, false, v_tax, v_total,
            v_user_id, 'pending', p_cart_id, 'card', v_address, v_client_name_snapshot,
            v_quote.customer_shipping_amount, v_quote.provider_total, v_quote.quotation_id, v_quote.rate_id, v_quote.shipping_discount_amount
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

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'total', v_total,
        'subtotal', v_subtotal,
        'tax', v_tax,
        'shipping', v_quote.customer_shipping_amount,
        'reused', v_reused
    );
END;
$$ LANGUAGE plpgsql;
REVOKE EXECUTE ON FUNCTION public.prepare_web_checkout_order_with_shipping(uuid, uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_web_checkout_order_with_shipping(uuid, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.prepare_web_checkout_order_with_shipping(uuid, uuid, uuid) TO authenticated;
