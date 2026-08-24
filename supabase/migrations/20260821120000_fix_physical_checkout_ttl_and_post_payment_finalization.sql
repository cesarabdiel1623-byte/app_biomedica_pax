-- Migration: 20260821120000_fix_physical_checkout_ttl_and_post_payment_finalization.sql
-- Description:
-- 1. Self-contained preference columns guarantee in order_payments.
-- 2. Creates order_fulfillment_jobs outbox table with atomic claim/complete/fail RPCs.
-- 3. Updates prepare_mp_order with 60-minute TTL for pending physical orders (stale orders auto-cancelled and not reused).
-- 4. Updates reconcile_mercado_pago_payment to atomically execute apply_paid_order_post_payment, validate success, and idempotently enqueue fulfillment job.
-- 5. Handles insufficient stock gracefully without losing payment approval or creating invalid shipments.
-- 6. Real automated scheduler definition via pg_cron + pg_net + Vault to trigger process-order-fulfillment-jobs every 1 minute.

-- -----------------------------------------------------------------------------
-- 1. Self-contained Columns in order_payments
-- -----------------------------------------------------------------------------

ALTER TABLE public.order_payments 
ADD COLUMN IF NOT EXISTS preference_id TEXT,
ADD COLUMN IF NOT EXISTS checkout_url TEXT,
ADD COLUMN IF NOT EXISTS preference_expires_at TIMESTAMPTZ;
-- -----------------------------------------------------------------------------
-- 2. Outbox Table and Worker Claim RPCs for Post-Payment Fulfillment
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.order_fulfillment_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    last_error TEXT,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_fulfillment_jobs_pending 
ON public.order_fulfillment_jobs(status, next_attempt_at) 
WHERE status IN ('pending', 'failed');
ALTER TABLE public.order_fulfillment_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.order_fulfillment_jobs FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.order_fulfillment_jobs TO service_role;
-- Worker atomic claim function with FOR UPDATE SKIP LOCKED
CREATE OR REPLACE FUNCTION public.claim_next_fulfillment_job()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_job public.order_fulfillment_jobs%rowtype;
BEGIN
  SELECT *
  INTO v_job
  FROM public.order_fulfillment_jobs
  WHERE status IN ('pending', 'failed')
    AND next_attempt_at <= now()
    AND attempts < max_attempts
  ORDER BY next_attempt_at ASC, created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.order_fulfillment_jobs
  SET status = 'processing',
      attempts = attempts + 1,
      updated_at = now()
  WHERE id = v_job.id
  RETURNING * INTO v_job;

  RETURN jsonb_build_object(
    'job_id', v_job.id,
    'order_id', v_job.order_id,
    'attempts', v_job.attempts,
    'max_attempts', v_job.max_attempts
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_next_fulfillment_job() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_next_fulfillment_job() TO service_role;
-- Worker job completion helper
CREATE OR REPLACE FUNCTION public.complete_fulfillment_job(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  UPDATE public.order_fulfillment_jobs
  SET status = 'completed',
      last_error = NULL,
      updated_at = now()
  WHERE id = p_job_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.complete_fulfillment_job(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_fulfillment_job(uuid) TO service_role;
-- Worker job failure with exponential backoff and terminal max attempts
CREATE OR REPLACE FUNCTION public.fail_fulfillment_job(
  p_job_id uuid,
  p_error text,
  p_backoff_minutes int DEFAULT 5
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  UPDATE public.order_fulfillment_jobs
  SET status = 'failed',
      last_error = left(coalesce(p_error, 'unknown_error'), 1000),
      next_attempt_at = CASE 
        WHEN attempts >= max_attempts THEN now() + interval '100 years'
        ELSE now() + (greatest(coalesce(p_backoff_minutes, 5), 1) || ' minutes')::interval 
      END,
      updated_at = now()
  WHERE id = p_job_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.fail_fulfillment_job(uuid, text, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_fulfillment_job(uuid, text, int) TO service_role;
-- -----------------------------------------------------------------------------
-- 3. prepare_mp_order with 60-Minute TTL for Physical Orders
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prepare_mp_order(
    p_user_id uuid,
    p_cart_id uuid,
    p_address_id uuid DEFAULT NULL::uuid,
    p_skydropx_quotation_id text DEFAULT NULL::text,
    p_skydropx_rate_id text DEFAULT NULL::text,
    p_selected_rate_total numeric DEFAULT 0,
    p_cheapest_valid_rate_total numeric DEFAULT 0,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_user_id uuid;
    v_client_id uuid;
    v_order_id uuid;
    v_order_number text;
    v_payment_record_id uuid;
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
        payment_status,
        created_at
    INTO v_existing_order
    FROM public.orders
    WHERE source_cart_id = p_cart_id
      AND client_id = v_client_id
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing_order.payment_status = 'approved'
           OR v_existing_order.status IN ('paid', 'processing', 'shipped', 'delivered') THEN
            RAISE EXCEPTION 'El carrito ya está vinculado a una orden pagada.';
        ELSIF v_existing_order.status = 'pending_payment' THEN
            -- Check 60-minute TTL for pending order reuse
            IF v_existing_order.created_at >= now() - interval '60 minutes' THEN
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
                    UPDATE public.orders
                    SET source_cart_id = NULL,
                        status = 'canceled',
                        updated_at = now()
                    WHERE id = v_existing_order.id;

                    UPDATE public.order_payments
                    SET status = 'cancelled'::public.payment_record_status,
                        status_detail = 'superseded_by_cart_change',
                        updated_at = now()
                    WHERE order_id = v_existing_order.id
                      AND status IN ('created', 'pending');
                END IF;
            ELSE
                -- Stale order (> 60 minutes): cancel auditable order and payment drafts
                UPDATE public.orders
                SET source_cart_id = NULL,
                    status = 'canceled',
                    updated_at = now()
                WHERE id = v_existing_order.id;

                UPDATE public.order_payments
                SET status = 'cancelled'::public.payment_record_status,
                    status_detail = 'superseded_by_ttl_expiry',
                    updated_at = now()
                WHERE order_id = v_existing_order.id
                  AND status IN ('created', 'pending');
            END IF;
        ELSE
            UPDATE public.orders
            SET source_cart_id = NULL,
                updated_at = now()
            WHERE id = v_existing_order.id;
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
        v_payment_record_id := v_existing_payment.id;
    ELSE
        INSERT INTO public.order_payments (
            order_id, client_id, provider, environment, external_reference,
            status, amount, currency_id, raw_metadata, is_primary
        ) VALUES (
            v_order_id, v_client_id, 'mercado_pago', 'test', v_order_number,
            'pending'::public.payment_record_status, v_payment_total, 'MXN', '{}'::jsonb, true
        ) RETURNING id INTO v_payment_record_id;
    END IF;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'payment_record_id', v_payment_record_id,
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
$function$;
REVOKE ALL ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, uuid, text, text, numeric, numeric, text) TO service_role;
-- -----------------------------------------------------------------------------
-- 4. apply_paid_order_post_payment (Idempotent Stock Deduction & Cart Conversion)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_paid_order_post_payment(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_order public.orders%rowtype;
  v_cart public.carts%rowtype;
  v_item record;
  v_previous_stock numeric;
  v_resulting_stock numeric;
  v_stock_errors jsonb;
  v_stock_already_deducted boolean := false;
  v_cart_converted boolean := false;
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'order_id_required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_order_id::text));

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.payment_status IS DISTINCT FROM 'approved'::public.payment_record_status THEN
    RAISE EXCEPTION 'order_not_approved';
  END IF;

  IF v_order.status NOT IN (
    'paid'::public.order_status,
    'processing'::public.order_status,
    'shipped'::public.order_status,
    'delivered'::public.order_status
  ) THEN
    RAISE EXCEPTION 'order_status_not_fulfillable';
  END IF;

  IF v_order.source_cart_id IS NOT NULL THEN
    SELECT *
    INTO v_cart
    FROM public.carts
    WHERE id = v_order.source_cart_id
    FOR UPDATE;

    IF FOUND THEN
      IF v_cart.client_id IS DISTINCT FROM v_order.client_id THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'cart_client_mismatch',
          'order_id', v_order.id,
          'stock_deducted', false
        );
      END IF;

      IF v_cart.status = 'converted_to_order'
         AND v_cart.converted_order_id IS DISTINCT FROM v_order.id THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'cart_converted_to_different_order',
          'order_id', v_order.id,
          'stock_deducted', false
        );
      END IF;

      IF v_cart.status NOT IN ('active', 'converted_to_order') THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'cart_status_not_convertible',
          'cart_status', v_cart.status,
          'order_id', v_order.id,
          'stock_deducted', false
        );
      END IF;
    END IF;
  END IF;

  IF COALESCE(v_order.stock_status, '') = 'deducted' THEN
    v_stock_already_deducted := true;
  ELSE
    IF NOT EXISTS (
      SELECT 1
      FROM public.order_items oi
      WHERE oi.order_id = v_order.id
        AND oi.product_id IS NOT NULL
        AND COALESCE(oi.quantity, 0) > 0
    ) THEN
      IF v_order.source_quote_id IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.quotes q
        WHERE q.id = v_order.source_quote_id
          AND q.service_ticket_id IS NOT NULL
      ) THEN
        UPDATE public.orders
        SET stock_status = 'service_no_stock',
            updated_at = now()
        WHERE id = v_order.id;

        RETURN jsonb_build_object(
          'success', true,
          'order_id', v_order.id,
          'stock_deducted', false,
          'stock_already_deducted', false,
          'service_only', true,
          'cart_converted', false,
          'source_cart_id', v_order.source_cart_id
        );
      END IF;

      RETURN jsonb_build_object(
        'success', false,
        'error', 'order_has_no_stock_items',
        'order_id', v_order.id,
        'stock_deducted', false
      );
    END IF;

    -- Lock determinista de filas de inventario sin GROUP BY en el SELECT de locking.
    PERFORM 1
    FROM public.product_inventory pi
    WHERE pi.product_id IN (
      SELECT DISTINCT oi.product_id
      FROM public.order_items oi
      WHERE oi.order_id = v_order.id
        AND oi.product_id IS NOT NULL
    )
    ORDER BY pi.product_id
    FOR UPDATE;

    -- Validar disponibilidad de todas las partidas antes de descontar alguna.
    SELECT jsonb_agg(
      jsonb_build_object(
        'product_id', items.product_id,
        'required_quantity', items.qty,
        'available_stock', COALESCE(pi.current_stock, 0)
      )
    )
    INTO v_stock_errors
    FROM (
      SELECT oi.product_id, sum(greatest(coalesce(oi.quantity, 0), 0)) AS qty
      FROM public.order_items oi
      WHERE oi.order_id = v_order.id
        AND oi.product_id IS NOT NULL
      GROUP BY oi.product_id
    ) items
    LEFT JOIN public.product_inventory pi ON pi.product_id = items.product_id
    WHERE pi.product_id IS NULL
       OR COALESCE(pi.current_stock, 0) < items.qty;

    IF v_stock_errors IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'insufficient_stock',
        'order_id', v_order.id,
        'stock_deducted', false,
        'stock_errors', v_stock_errors
      );
    END IF;

    FOR v_item IN
      SELECT oi.product_id, sum(greatest(coalesce(oi.quantity, 0), 0)) AS qty
      FROM public.order_items oi
      WHERE oi.order_id = v_order.id
        AND oi.product_id IS NOT NULL
      GROUP BY oi.product_id
      ORDER BY oi.product_id
    LOOP
      SELECT pi.current_stock
      INTO v_previous_stock
      FROM public.product_inventory pi
      WHERE pi.product_id = v_item.product_id;

      v_resulting_stock := v_previous_stock - v_item.qty;

      UPDATE public.product_inventory
      SET current_stock = v_resulting_stock
      WHERE product_id = v_item.product_id;

      INSERT INTO public.inventory_movements (
        product_id,
        movement_type,
        quantity,
        previous_stock,
        resulting_stock,
        reference_type,
        reference_id,
        notes,
        created_by
      ) VALUES (
        v_item.product_id,
        'exit'::public.inventory_movement_type,
        -v_item.qty,
        v_previous_stock,
        v_resulting_stock,
        'order'::public.reference_type,
        v_order.id,
        'Salida automatica por orden pagada',
        NULL
      );
    END LOOP;

    UPDATE public.orders
    SET stock_status = 'deducted',
        updated_at = now()
    WHERE id = v_order.id;
  END IF;

  IF v_order.source_cart_id IS NOT NULL AND v_cart.id IS NOT NULL THEN
    IF v_cart.status = 'converted_to_order'
       AND v_cart.converted_order_id = v_order.id THEN
      v_cart_converted := true;
    ELSE
      UPDATE public.carts
      SET status = 'converted_to_order',
          converted_order_id = v_order.id,
          updated_at = now()
      WHERE id = v_order.source_cart_id
        AND client_id = v_order.client_id
        AND status = 'active'
        AND converted_order_id IS NULL;

      v_cart_converted := FOUND;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'stock_deducted', true,
    'stock_already_deducted', v_stock_already_deducted,
    'cart_converted', v_cart_converted,
    'source_cart_id', v_order.source_cart_id
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paid_order_post_payment TO service_role;
-- -----------------------------------------------------------------------------
-- 5. reconcile_mercado_pago_payment with Atomic Post-Payment DB Finalization
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reconcile_mercado_pago_payment(
    p_payment_id text,
    p_external_reference text,
    p_status text,
    p_status_detail text,
    p_amount numeric,
    p_currency_id text,
    p_payment_method_id text,
    p_payment_type_id text,
    p_installments integer,
    p_live_mode boolean,
    p_date_approved timestamp with time zone,
    p_provider_created_at timestamp with time zone,
    p_provider_updated_at timestamp with time zone,
    p_raw_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), current_user);
  v_payment public.order_payments%rowtype;
  v_order public.orders%rowtype;
  v_new_status public.payment_record_status;
  v_sale_id uuid;
  v_existing_primary_id uuid;
  v_duplicate_approved boolean := false;
  v_was_primary boolean := false;
  v_configured_environment text;
  v_post_payment_result jsonb;
  v_stock_success boolean := false;
BEGIN
  IF v_role <> 'service_role'
     AND current_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION USING
      errcode = '42501',
      message = 'Solo el backend puede conciliar pagos.';
  END IF;

  IF nullif(btrim(coalesce(p_payment_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_external_reference,'')),'') IS NULL THEN
    RAISE EXCEPTION USING
      errcode = '22023',
      message = 'El pago no contiene identificadores válidos.';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.order_payments
  WHERE external_reference = p_external_reference
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      errcode = 'P0002',
      message = 'No existe un intento de pago para la referencia.';
  END IF;

  v_was_primary := v_payment.is_primary;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_payment.order_id::text, 0)
  );

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = v_payment.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      errcode = 'P0002',
      message = 'La orden del pago no existe.';
  END IF;

  IF round(coalesce(p_amount,0),2) <> round(v_payment.amount,2)
     OR round(coalesce(p_amount,0),2) <> round(v_order.total,2) THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'PAYMENT_AMOUNT_MISMATCH';
  END IF;

  IF upper(coalesce(p_currency_id,'')) <> v_payment.currency_id THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'PAYMENT_CURRENCY_MISMATCH';
  END IF;

  v_configured_environment := lower(
    nullif(
      btrim(
        coalesce(
          p_raw_metadata->>'configured_environment',
          v_payment.environment
        )
      ),
      ''
    )
  );

  IF v_configured_environment NOT IN ('test','production') THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'PAYMENT_ENVIRONMENT_INVALID';
  END IF;

  IF coalesce(v_payment.environment,'') <> v_configured_environment THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'PAYMENT_ENVIRONMENT_MISMATCH';
  END IF;

  IF v_configured_environment = 'production'
     AND coalesce(p_live_mode,false) = false THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'PAYMENT_ENVIRONMENT_MISMATCH';
  END IF;

  IF v_payment.payment_id IS NOT NULL
     AND v_payment.payment_id <> p_payment_id THEN
    RAISE EXCEPTION USING
      errcode = '23505',
      message = 'La referencia ya está ligada a otro payment_id.';
  END IF;

  v_new_status := CASE lower(coalesce(p_status,''))
    WHEN 'approved' THEN 'approved'::public.payment_record_status
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

  IF v_payment.status = 'approved'
     AND v_new_status IN (
       'created','pending','rejected','cancelled','error'
     ) THEN
    v_new_status := 'approved';
  END IF;

  UPDATE public.order_payments
  SET payment_id = p_payment_id,
      status = v_new_status,
      status_detail = left(coalesce(p_status_detail,''),200),
      payment_method_id =
        nullif(left(coalesce(p_payment_method_id,''),80),''),
      payment_type_id =
        nullif(left(coalesce(p_payment_type_id,''),80),''),
      installments = p_installments,
      live_mode = p_live_mode,
      date_approved = p_date_approved,
      provider_created_at = p_provider_created_at,
      provider_updated_at = p_provider_updated_at,
      last_webhook_at = now(),
      raw_metadata = coalesce(p_raw_metadata,'{}'::jsonb),
      is_primary = CASE
        WHEN v_new_status IN ('refunded','charged_back') THEN false
        ELSE is_primary
      END,
      updated_at = now()
  WHERE id = v_payment.id;

  IF v_new_status = 'approved' THEN
    SELECT op.id
    INTO v_existing_primary_id
    FROM public.order_payments op
    WHERE op.order_id = v_order.id
      AND op.id <> v_payment.id
      AND op.status = 'approved'
      AND op.is_primary = true
    LIMIT 1
    FOR UPDATE;

    IF v_existing_primary_id IS NOT NULL THEN
      v_duplicate_approved := true;

      UPDATE public.order_payments
      SET is_primary = false,
          status_detail = left(
            concat_ws(
              ' | ',
              nullif(coalesce(p_status_detail,''),''),
              'duplicate_approved_requires_review'
            ),
            200
          ),
          raw_metadata =
            coalesce(p_raw_metadata,'{}'::jsonb)
            || jsonb_build_object(
              'duplicate_approved', true,
              'primary_payment_record_id', v_existing_primary_id
            ),
          updated_at = now()
      WHERE id = v_payment.id;
    ELSE
      UPDATE public.order_payments
      SET is_primary = true,
          updated_at = now()
      WHERE id = v_payment.id;

      UPDATE public.orders
      SET payment_status = 'approved',
          paid_at = coalesce(p_date_approved, paid_at, now()),
          status = CASE
            WHEN status IN (
              'draft','pending_review','pending_payment'
            ) THEN 'paid'
            ELSE status
          END,
          updated_at = now()
      WHERE id = v_order.id;

      SELECT id
      INTO v_sale_id
      FROM public.sales
      WHERE order_id = v_order.id
      FOR UPDATE;

      IF v_sale_id IS NULL THEN
        INSERT INTO public.sales(
          client_id,
          client_name_snapshot,
          order_id,
          status,
          payment_method,
          subtotal,
          tax_pct,
          tax_exempt,
          tax,
          total,
          amount_paid,
          created_by,
          paid_at,
          notes
        ) VALUES (
          v_order.client_id,
          v_order.client_name_snapshot,
          v_order.id,
          'paid',
          'card',
          v_order.subtotal,
          v_order.tax_pct,
          v_order.tax_exempt,
          v_order.tax,
          v_order.total,
          v_order.total,
          v_order.created_by,
          coalesce(p_date_approved,now()),
          'Venta creada automáticamente por pago Mercado Pago verificado'
        )
        RETURNING id INTO v_sale_id;

        INSERT INTO public.sale_items(
          sale_id,
          product_id,
          sku_snapshot,
          product_name_snapshot,
          product_category_snapshot,
          quantity,
          unit_price,
          discount,
          total_line_price
        )
        SELECT
          v_sale_id,
          oi.product_id,
          oi.sku_snapshot,
          oi.product_name_snapshot,
          oi.product_category_snapshot,
          oi.quantity,
          oi.unit_price,
          0,
          oi.total_line_price
        FROM public.order_items oi
        WHERE oi.order_id = v_order.id;
      ELSE
        UPDATE public.sales
        SET status = 'paid',
            amount_paid = total,
            paid_at = coalesce(
              paid_at,
              p_date_approved,
              now()
            ),
            updated_at = now()
        WHERE id = v_sale_id;
      END IF;

      IF v_order.coupon_id IS NOT NULL THEN
        INSERT INTO public.coupon_redemptions(
          coupon_id,
          client_id,
          cart_id,
          order_id,
          coupon_code,
          coupon_discount_amount,
          shipping_discount_amount,
          configuration_snapshot
        ) VALUES (
          v_order.coupon_id,
          v_order.client_id,
          v_order.source_cart_id,
          v_order.id,
          coalesce(v_order.coupon_code,''),
          v_order.coupon_discount_amount,
          v_order.shipping_discount_amount,
          coalesce(v_order.coupon_snapshot,'{}'::jsonb)
        )
        ON CONFLICT DO NOTHING;
      END IF;

      -- Atomic Post-Payment Execution: Deducts inventory and converts cart
      v_post_payment_result := public.apply_paid_order_post_payment(v_order.id);
      v_stock_success := coalesce((v_post_payment_result->>'success')::boolean, false);

      IF v_stock_success THEN
        -- Enqueue outbox job for SkyDropX shipment with idempotent UPSERT (does not revive completed jobs)
        INSERT INTO public.order_fulfillment_jobs (order_id, status, next_attempt_at)
        VALUES (v_order.id, 'pending', now())
        ON CONFLICT (order_id) DO UPDATE
        SET updated_at = now()
        WHERE public.order_fulfillment_jobs.status NOT IN ('completed', 'processing');
      ELSE
        -- Stock deduction failed (e.g. insufficient stock). 
        -- Record error state without losing external payment approval or enqueuing invalid shipment.
        UPDATE public.orders
        SET supply_status = 'pending_review',
            stock_status = 'stock_deduction_failed',
            notes = concat_ws(' | ', notes, 'FALLO EN DEDUCCION DE INVENTARIO: ' || coalesce(v_post_payment_result->>'error', 'unknown_stock_error')),
            updated_at = now()
        WHERE id = v_order.id;

        UPDATE public.order_payments
        SET status_detail = left(concat_ws(' | ', status_detail, 'stock_finalization_failed'), 200),
            raw_metadata = coalesce(raw_metadata, '{}'::jsonb) || jsonb_build_object(
              'post_payment_error', v_post_payment_result->>'error',
              'post_payment_details', v_post_payment_result
            ),
            updated_at = now()
        WHERE id = v_payment.id;

        -- Convert source cart so user cannot re-pay the same cart
        IF v_order.source_cart_id IS NOT NULL THEN
          UPDATE public.carts
          SET status = 'converted_to_order',
              converted_order_id = v_order.id,
              updated_at = now()
          WHERE id = v_order.source_cart_id
            AND client_id = v_order.client_id
            AND status = 'active';
        END IF;
      END IF;
    END IF;

  ELSIF v_new_status IN ('pending','created') THEN
    IF v_order.payment_status <> 'approved' THEN
      UPDATE public.orders
      SET payment_status = 'pending',
          updated_at = now()
      WHERE id = v_order.id;
    END IF;

  ELSIF v_new_status IN (
    'rejected','cancelled','error'
  ) THEN
    IF v_order.payment_status <> 'approved' THEN
      UPDATE public.orders
      SET payment_status = v_new_status,
          updated_at = now()
      WHERE id = v_order.id;

      UPDATE public.inventory_reservations
      SET status = 'released',
          released_at = now(),
          updated_at = now(),
          notes = concat_ws(
            ' | ',
            notes,
            'Liberada por pago no aprobado'
          )
      WHERE order_id = v_order.id
        AND status = 'active';

      UPDATE public.order_items
      SET quantity_reserved = 0,
          quantity_pending = quantity,
          supply_status = 'pending_supply'
      WHERE order_id = v_order.id
        AND supply_status <> 'service_no_stock';

      UPDATE public.orders
      SET supply_status = 'pending_supply',
          reserved_at = null,
          ready_at = null,
          updated_at = now()
      WHERE id = v_order.id;
    END IF;

  ELSIF v_new_status IN (
    'refunded','charged_back'
  ) THEN
    IF v_was_primary THEN
      UPDATE public.orders
      SET payment_status = v_new_status,
          status = CASE
            WHEN status IN ('paid','processing')
              THEN 'pending_review'
            ELSE status
          END,
          updated_at = now()
      WHERE id = v_order.id;

      UPDATE public.sales
      SET status = 'refunded',
          updated_at = now()
      WHERE order_id = v_order.id
        AND status <> 'cancelled';

      UPDATE public.inventory_reservations
      SET status = 'released',
          released_at = now(),
          updated_at = now(),
          notes = concat_ws(
            ' | ',
            notes,
            'Liberada por devolución/contracargo'
          )
      WHERE order_id = v_order.id
        AND status = 'active';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'processed', true,
    'payment_record_id', v_payment.id,
    'order_id', v_order.id,
    'payment_id', p_payment_id,
    'status', v_new_status,
    'duplicate_approved', v_duplicate_approved,
    'stock_finalized', v_stock_success,
    'post_payment_result', v_post_payment_result,
    'idempotent',
      v_payment.payment_id = p_payment_id
      and v_payment.status = v_new_status
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.reconcile_mercado_pago_payment FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_mercado_pago_payment TO service_role;
-- -----------------------------------------------------------------------------
-- 6. Automated Scheduler for order_fulfillment_jobs Outbox (Fail-Closed)
-- -----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;
DO $$
DECLARE
  v_base_url text;
  v_service_key text;
BEGIN
  -- Verify Vault secrets are present before creating schedule
  SELECT decrypted_secret INTO v_base_url
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_base_url'
  LIMIT 1;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF coalesce(btrim(v_base_url), '') = '' THEN
    RAISE EXCEPTION 'DEPLOY_PRECONDITION_MISSING: Vault secret "edge_function_base_url" is required for automated fulfillment scheduling';
  END IF;

  IF coalesce(btrim(v_service_key), '') = '' THEN
    RAISE EXCEPTION 'DEPLOY_PRECONDITION_MISSING: Vault secret "service_role_key" is required for automated fulfillment scheduling';
  END IF;

  -- Idempotent unschedule before scheduling
  PERFORM cron.unschedule('process-order-fulfillment-jobs')
  WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'process-order-fulfillment-jobs'
  );

  -- Schedule job to run every 1 minute dynamically querying Vault at runtime
  PERFORM cron.schedule(
      'process-order-fulfillment-jobs',
      '* * * * *',
      $cron$
      SELECT net.http_post(
          url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_function_base_url' LIMIT 1) || '/process-order-fulfillment-jobs',
          headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
          ),
          body := '{"batch_size": 10}'::jsonb
      );
      $cron$
  );
END;
$$;
