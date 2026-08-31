-- PARTE 1: prepare_web_quote_order
CREATE OR REPLACE FUNCTION public.prepare_web_quote_order(
  p_quote_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_user_id uuid;
  v_client_id uuid;
  v_quote record;
  v_order record;
  v_new_order_id uuid;
  v_order_number text;
  v_item record;
  v_reused boolean := false;
  v_already_paid boolean := false;
  v_expiration timestamptz := now() + interval '30 minutes';
  v_has_physical_stock boolean := false;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT client_id INTO v_client_id
  FROM public.profiles
  WHERE id = v_user_id AND is_active = true
  LIMIT 1;

  IF v_client_id IS NULL THEN
    RAISE EXCEPTION 'Client profile not found or inactive';
  END IF;

  -- Advisory lock for this quote
  PERFORM pg_advisory_xact_lock(hashtext('quote_' || p_quote_id::text));

  -- Get quote
  SELECT * INTO v_quote
  FROM public.quotes
  WHERE id = p_quote_id AND client_id = v_client_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quote not found or access denied';
  END IF;

  -- 1. Idempotency: converted quote
  IF v_quote.status = 'converted' AND v_quote.converted_order_id IS NOT NULL THEN
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = v_quote.converted_order_id AND client_id = v_client_id;
    
    IF FOUND THEN
      RETURN jsonb_build_object(
        'order_id', v_order.id,
        'order_number', v_order.order_number,
        'source_quote_id', v_order.source_quote_id,
        'service_ticket_id', v_quote.service_ticket_id,
        'subtotal', v_order.subtotal,
        'tax', v_order.tax,
        'total', v_order.total,
        'currency_id', 'MXN',
        'reused', true,
        'already_paid', v_order.payment_status = 'approved'
      );
    END IF;
  END IF;

  -- 2. Check if ready to prepare
  IF v_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'Quote must be approved';
  END IF;
  IF v_quote.valid_until < CURRENT_DATE THEN
    RAISE EXCEPTION 'Quote has expired';
  END IF;
  IF v_quote.total <= 0 THEN
    RAISE EXCEPTION 'Quote total must be greater than 0';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quote_items WHERE quote_id = v_quote.id) THEN
    RAISE EXCEPTION 'Quote has no items';
  END IF;

  -- 4. Search existing order
  SELECT * INTO v_order
  FROM public.orders
  WHERE source_quote_id = p_quote_id
    AND client_id = v_client_id
    AND status <> 'canceled'
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    IF v_order.payment_status = 'approved' OR v_order.status IN ('paid', 'processing', 'shipped', 'delivered') THEN
      v_already_paid := true;
      v_reused := true;
    ELSIF v_order.payment_status IN ('pending', 'rejected', 'cancelled', 'error') THEN
      -- Validate financial identity for reuse
      DECLARE
        v_order_sum_line numeric;
        v_order_sum_disc numeric;
      BEGIN
        SELECT COALESCE(SUM(total_line_price), 0), COALESCE(SUM(discount), 0)
        INTO v_order_sum_line, v_order_sum_disc
        FROM public.order_items
        WHERE order_id = v_order.id;

        IF v_order.subtotal = v_quote.subtotal AND
           v_order.tax_pct = v_quote.tax_pct AND
           v_order.tax_exempt = v_quote.tax_exempt AND
           v_order.tax = v_quote.tax AND
           v_order.total = v_quote.total AND
           ROUND(v_order_sum_line, 2) = ROUND(v_quote.subtotal, 2) THEN
          v_reused := true;
        ELSE
          RAISE EXCEPTION 'Existing order has different financial values';
        END IF;
      END;
    ELSE
      RAISE EXCEPTION 'Existing order in unexpected state';
    END IF;

    IF v_reused THEN
      RETURN jsonb_build_object(
        'order_id', v_order.id,
        'order_number', v_order.order_number,
        'source_quote_id', v_order.source_quote_id,
        'service_ticket_id', v_quote.service_ticket_id,
        'subtotal', v_order.subtotal,
        'tax', v_order.tax,
        'total', v_order.total,
        'currency_id', 'MXN',
        'reused', v_reused,
        'already_paid', v_already_paid
      );
    END IF;
  END IF;

  -- 6. Create new order
  -- financial validations
  DECLARE
    v_sum_line_price numeric;
    v_sum_discount numeric;
  BEGIN
    SELECT COALESCE(SUM(total_line_price), 0), COALESCE(SUM(discount), 0)
    INTO v_sum_line_price, v_sum_discount
    FROM public.quote_items
    WHERE quote_id = p_quote_id;

    IF ROUND(v_sum_line_price, 2) <> ROUND(v_quote.subtotal, 2) THEN
      RAISE EXCEPTION 'Items line price sum does not match quote subtotal';
    END IF;
    IF ROUND(v_quote.subtotal + v_quote.tax, 2) <> ROUND(v_quote.total, 2) THEN
      RAISE EXCEPTION 'Quote total does not match subtotal + tax';
    END IF;
  END;

  -- Use sequence for order number
  v_order_number := 'ORD-' || to_char(CURRENT_DATE, 'YYYYMMDD') || '-' || upper(substring(md5(random()::text) from 1 for 8));
  
  INSERT INTO public.orders (
    client_id,
    order_number,
    client_name_snapshot,
    subtotal,
    tax_pct,
    tax_exempt,
    tax,
    total,
    notes,
    source_quote_id,
    source_cart_id,
    payment_method,
    payment_status,
    status,
    customer_shipping_amount,
    skydropx_shipping_cost,
    coupon_discount_amount,
    shipping_discount_amount,
    created_by
  ) VALUES (
    v_client_id,
    v_order_number,
    COALESCE(v_quote.client_name_snapshot, ''),
    v_quote.subtotal,
    v_quote.tax_pct,
    v_quote.tax_exempt,
    v_quote.tax,
    v_quote.total,
    COALESCE(p_notes, v_quote.notes),
    v_quote.id,
    NULL,
    'card',
    'pending',
    'pending_payment',
    0,
    0,
    0,
    0,
    v_user_id
  ) RETURNING id INTO v_new_order_id;

  -- Items
  FOR v_item IN (SELECT * FROM public.quote_items WHERE quote_id = p_quote_id)
  LOOP
    INSERT INTO public.order_items (
      order_id,
      product_id,
      sku_snapshot,
      product_name_snapshot,
      product_category_snapshot,
      quantity,
      unit_price,
      discount,
      total_line_price,
      supply_status
    ) VALUES (
      v_new_order_id,
      v_item.product_id,
      v_item.sku_snapshot,
      v_item.product_name_snapshot,
      v_item.product_category_snapshot,
      v_item.quantity,
      v_item.unit_price,
      v_item.discount,
      v_item.total_line_price,
      CASE WHEN v_item.product_id IS NULL THEN 'service_no_stock' ELSE 'pending_review' END
    );
  END LOOP;

  -- Validate order items sum after insertion
  DECLARE
    v_final_order_line_sum numeric;
    v_final_order_disc_sum numeric;
  BEGIN
    SELECT COALESCE(SUM(total_line_price), 0), COALESCE(SUM(discount), 0)
    INTO v_final_order_line_sum, v_final_order_disc_sum
    FROM public.order_items
    WHERE order_id = v_new_order_id;

    IF ROUND(v_final_order_line_sum, 2) <> ROUND(v_quote.subtotal, 2) THEN
      RAISE EXCEPTION 'Order items line price sum does not match quote subtotal';
    END IF;
    IF ROUND(v_quote.total, 2) <> ROUND(v_quote.subtotal + v_quote.tax, 2) THEN
      RAISE EXCEPTION 'Order total does not match subtotal + tax';
    END IF;
    
    DECLARE
      v_quote_disc_sum numeric;
    BEGIN
      SELECT COALESCE(SUM(discount), 0) INTO v_quote_disc_sum FROM public.quote_items WHERE quote_id = p_quote_id;
      IF ROUND(v_final_order_disc_sum, 2) <> ROUND(v_quote_disc_sum, 2) THEN
        RAISE EXCEPTION 'Order discount sum does not match quote discount sum';
      END IF;
    END;
  END;

  -- Reserve physical inventory if there are products
  SELECT EXISTS (
    SELECT 1
    FROM public.order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.order_id = v_new_order_id
      AND oi.product_id IS NOT NULL
      AND p.track_inventory = true
  )
  INTO v_has_physical_stock;

  IF v_has_physical_stock THEN
    PERFORM public.reserve_order_stock_for_payment(
      v_new_order_id,
      v_expiration
    );
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_new_order_id,
    'order_number', v_order_number,
    'source_quote_id', p_quote_id,
    'service_ticket_id', v_quote.service_ticket_id,
    'subtotal', v_quote.subtotal,
    'tax', v_quote.tax,
    'total', v_quote.total,
    'currency_id', 'MXN',
    'reused', false,
    'already_paid', false
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.prepare_web_quote_order(uuid, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.prepare_web_quote_order(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.prepare_web_quote_order(uuid, text) TO authenticated;
-- PARTE 2: claim_mp_web_order_payment_attempt
CREATE OR REPLACE FUNCTION public.claim_mp_web_order_payment_attempt(
  p_order_id uuid,
  p_client_id uuid,
  p_environment text,
  p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_order record;
  v_existing_attempt record;
  v_active_attempt record;
  v_new_attempt_id uuid;
  v_external_ref text;
BEGIN
  IF p_environment NOT IN ('test', 'production') THEN
    RAISE EXCEPTION 'Invalid environment';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('claim_web_payment_' || p_order_id::text));

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.client_id <> p_client_id THEN
    RAISE EXCEPTION 'Order belongs to another client';
  END IF;

  IF v_order.status IN ('canceled', 'shipped', 'delivered') THEN
    RAISE EXCEPTION 'Order status not compatible with payment';
  END IF;

  IF v_order.payment_status = 'approved' THEN
    RAISE EXCEPTION 'Order already approved';
  END IF;

  IF v_order.total <= 0 THEN
    RAISE EXCEPTION 'Order total must be greater than 0';
  END IF;

  -- 5. Primero buscar p_idempotency_key
  SELECT * INTO v_existing_attempt
  FROM public.order_payments
  WHERE idempotency_key = p_idempotency_key;

  IF FOUND THEN
    IF v_existing_attempt.order_id <> p_order_id OR v_existing_attempt.amount <> v_order.total OR v_existing_attempt.environment <> p_environment OR v_existing_attempt.client_id <> p_client_id OR v_existing_attempt.currency_id <> 'MXN' THEN
      RAISE EXCEPTION 'Idempotency key mismatch with order details';
    END IF;

    IF v_existing_attempt.payment_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'claimed', false,
        'reason', 'already_processed',
        'payment_record_id', v_existing_attempt.id,
        'payment_id', v_existing_attempt.payment_id,
        'external_reference', v_existing_attempt.external_reference,
        'status', v_existing_attempt.status
      );
    END IF;

    IF v_existing_attempt.status = 'error' AND v_existing_attempt.status_detail = 'provider_http_error' THEN
      RETURN jsonb_build_object(
        'claimed', false,
        'reason', 'terminal_attempt_requires_new_key',
        'payment_record_id', v_existing_attempt.id,
        'external_reference', v_existing_attempt.external_reference,
        'status', v_existing_attempt.status,
        'safe_to_retry_with_new_attempt', true
      );
    ELSIF v_existing_attempt.status IN ('error', 'rejected', 'cancelled') THEN
      RETURN jsonb_build_object(
        'claimed', false,
        'reason', 'terminal_attempt_not_retryable',
        'payment_record_id', v_existing_attempt.id,
        'external_reference', v_existing_attempt.external_reference,
        'status', v_existing_attempt.status,
        'safe_to_retry_with_new_attempt', false
      );
    END IF;

    IF v_existing_attempt.status IN ('created', 'pending') THEN
      RETURN jsonb_build_object(
        'claimed', true,
        'payment_record_id', v_existing_attempt.id,
        'external_reference', v_existing_attempt.external_reference,
        'status', v_existing_attempt.status
      );
    END IF;
  END IF;

  -- 6. Si es nueva key, buscar si hay otra activa web attempt
  SELECT * INTO v_active_attempt
  FROM public.order_payments
  WHERE order_id = p_order_id
    AND provider = 'mercado_pago'
    AND left(external_reference, 10) = 'web_order_'
    AND status IN ('created', 'pending', 'approved');
  
  IF FOUND THEN
    RETURN jsonb_build_object(
      'claimed', false,
      'reason', 'payment_attempt_in_progress',
      'payment_record_id', v_active_attempt.id,
      'payment_id', v_active_attempt.payment_id,
      'external_reference', v_active_attempt.external_reference,
      'status', v_active_attempt.status
    );
  END IF;

  -- 6.5 Defensa: buscar error no-retryable existente
  DECLARE
    v_terminal_error record;
  BEGIN
    SELECT * INTO v_terminal_error
    FROM public.order_payments
    WHERE order_id = p_order_id
      AND provider = 'mercado_pago'
      AND left(external_reference, 10) = 'web_order_'
      AND status = 'error'
      AND status_detail IS DISTINCT FROM 'provider_http_error'
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'claimed', false,
        'reason', 'payment_attempt_requires_review',
        'payment_record_id', v_terminal_error.id,
        'external_reference', v_terminal_error.external_reference,
        'status', v_terminal_error.status,
        'safe_to_retry_with_new_attempt', false
      );
    END IF;
  END;

  -- 7. Crear intento
  IF v_order.payment_status IN ('rejected', 'cancelled', 'error') THEN
    UPDATE public.orders SET payment_status = 'pending', status = 'pending_payment', updated_at = now() WHERE id = p_order_id;
  END IF;

  v_new_attempt_id := gen_random_uuid();
  v_external_ref := 'web_order_' || p_order_id || '_' || v_new_attempt_id;

  INSERT INTO public.order_payments (
    id,
    order_id,
    client_id,
    provider,
    environment,
    external_reference,
    status,
    amount,
    currency_id,
    idempotency_key,
    raw_metadata,
    is_primary
  ) VALUES (
    v_new_attempt_id,
    p_order_id,
    p_client_id,
    'mercado_pago',
    p_environment,
    v_external_ref,
    'created',
    v_order.total,
    'MXN',
    p_idempotency_key,
    '{"source": "web_payment_brick"}'::jsonb,
    false
  );

  RETURN jsonb_build_object(
    'claimed', true,
    'payment_record_id', v_new_attempt_id,
    'external_reference', v_external_ref,
    'status', 'created'
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.claim_mp_web_order_payment_attempt(uuid, uuid, text, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.claim_mp_web_order_payment_attempt(uuid, uuid, text, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.claim_mp_web_order_payment_attempt(uuid, uuid, text, uuid) FROM authenticated;
-- Only service_role can call this (usually handled via Supabase keys not roles here directly, but the search path and revoke setup is standard)
GRANT EXECUTE ON FUNCTION public.claim_mp_web_order_payment_attempt(uuid, uuid, text, uuid) TO service_role;
-- PARTE 3: UNIQUE INDEX PARCIAL
CREATE UNIQUE INDEX IF NOT EXISTS order_payments_one_active_web_attempt_per_order_uidx
ON public.order_payments (order_id)
WHERE provider = 'mercado_pago' AND left(external_reference, 10) = 'web_order_' AND status IN ('created', 'pending');
