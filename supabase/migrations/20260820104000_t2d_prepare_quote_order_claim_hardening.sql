-- ============================================================================
-- MIGRACIÓN T2D: HARDENING DE CONCURRENCIA Y CLAIMS EN PREPARE_QUOTE_ORDER
-- Timestamp: 20260820104000_t2d_prepare_quote_order_claim_hardening.sql
-- ============================================================================
-- Redefine public.prepare_quote_order(uuid, text) para proteger intentos de pago
-- en vuelo (pending claim) creados por la Edge Function create-mp-quote-order-preference.
-- Evita que solicitudes concurrentes cancelen un intento activo antes de que Mercado Pago
-- devuelva la preferencia, y recicla intentos stale de forma segura.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.prepare_quote_order(
  p_quote_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_client_id uuid;
  v_quote public.quotes%rowtype;
  v_order public.orders%rowtype;
  v_payment public.order_payments%rowtype;
  v_existing_payment public.order_payments%rowtype;
  v_existing_order public.orders%rowtype;
  v_order_number text;
  v_external_reference text;
  v_expiration timestamptz := now() + interval '30 minutes';
  v_inserted_items integer := 0;
  v_has_physical_stock boolean := false;
  v_items_total numeric(12,2) := 0;
  v_items_discount numeric(12,2) := 0;
  v_quote_items_discount numeric(12,2) := 0;
  v_payment_environment text := 'test';
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'Usuario no autenticado.';
  END IF;

  SELECT p.client_id INTO v_client_id
  FROM public.profiles p
  WHERE p.id = v_user_id AND p.is_active = true;

  IF v_client_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'Cliente no encontrado o inactivo.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_quote_id::text, 0));

  SELECT * INTO v_quote
  FROM public.quotes
  WHERE id = p_quote_id AND client_id = v_client_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'Cotización no encontrada o no autorizada.';
  END IF;

  -- Si ya está convertida formalmente
  IF v_quote.status = 'converted' AND v_quote.converted_order_id IS NOT NULL THEN
    SELECT * INTO v_existing_order
    FROM public.orders
    WHERE id = v_quote.converted_order_id AND client_id = v_client_id;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'already_paid', v_existing_order.payment_status = 'approved',
        'order_id', v_existing_order.id,
        'order_number', v_existing_order.order_number,
        'amount', v_existing_order.total,
        'currency_id', 'MXN',
        'source_quote_id', v_quote.id
      );
    END IF;
  END IF;

  IF v_quote.status <> 'approved' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'La cotización debe ser aceptada antes de proceder al pago.';
  END IF;

  IF v_quote.valid_until IS NOT NULL AND v_quote.valid_until < CURRENT_DATE THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'La cotización ha expirado. Solicita una nueva cotización.';
  END IF;

  IF v_quote.total <= 0 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'El monto total de la cotización debe ser mayor a cero.';
  END IF;

  -- Idempotencia exhaustiva: Buscar CUALQUIER orden activa no cancelada ligada a esta cotización
  SELECT * INTO v_existing_order
  FROM public.orders
  WHERE source_quote_id = p_quote_id
    AND client_id = v_client_id
    AND status <> 'canceled'::public.order_status
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    -- Si la orden ya está pagada o en procesamiento/entrega
    IF v_existing_order.payment_status = 'approved'
       OR v_existing_order.status IN ('paid', 'processing', 'shipped', 'delivered') THEN
      RETURN jsonb_build_object(
        'already_paid', true,
        'order_id', v_existing_order.id,
        'order_number', v_existing_order.order_number,
        'amount', v_existing_order.total,
        'currency_id', 'MXN',
        'source_quote_id', v_quote.id
      );
    END IF;

    v_order := v_existing_order;
  ELSE
    v_order_number := 'ORD-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substring(md5(random()::text) from 1 for 8));

    INSERT INTO public.orders (
      order_number,
      client_id,
      client_name_snapshot,
      status,
      payment_method,
      subtotal,
      tax_pct,
      tax_exempt,
      tax,
      total,
      notes,
      created_by,
      source_quote_id,
      source_cart_id,
      payment_status,
      supply_status,
      customer_shipping_amount,
      skydropx_shipping_cost,
      coupon_discount_amount,
      shipping_discount_amount
    ) VALUES (
      v_order_number,
      v_client_id,
      v_quote.client_name_snapshot,
      'pending_payment',
      'card',
      v_quote.subtotal,
      v_quote.tax_pct,
      v_quote.tax_exempt,
      v_quote.tax,
      v_quote.total,
      COALESCE(p_notes, v_quote.notes),
      v_user_id,
      v_quote.id,
      NULL,
      'pending',
      'ready_to_fulfill',
      0,
      0,
      0,
      0
    ) RETURNING * INTO v_order;

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
    )
    SELECT
      v_order.id,
      qi.product_id,
      qi.sku_snapshot,
      qi.product_name_snapshot,
      qi.product_category_snapshot,
      qi.quantity,
      qi.unit_price,
      COALESCE(qi.discount, 0),
      qi.total_line_price,
      CASE WHEN qi.product_id IS NULL THEN 'service_no_stock' ELSE 'pending_review' END
    FROM public.quote_items qi
    WHERE qi.quote_id = v_quote.id;

    GET DIAGNOSTICS v_inserted_items = row_count;
    IF v_inserted_items = 0 THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'La cotización no contiene partidas para generar el pedido.';
    END IF;

    -- Los triggers trg_order_items_recalculate ejecutan recalculate_order_totals,
    -- el cual gracias a la rama source_quote_id preserva subtotal, tax y total exactos de quotes.
    SELECT * INTO v_order FROM public.orders WHERE id = v_order.id;

    -- Validaciones estrictas de identidad financiera post-triggers (FAIL-CLOSED)
    SELECT
      COALESCE(SUM(oi.total_line_price), 0),
      COALESCE(SUM(oi.discount), 0)
    INTO v_items_total, v_items_discount
    FROM public.order_items oi
    WHERE oi.order_id = v_order.id;

    SELECT
      COALESCE(SUM(qi.discount), 0)
    INTO v_quote_items_discount
    FROM public.quote_items qi
    WHERE qi.quote_id = v_quote.id;

    -- A) SUM(order_items.total_line_price) = quotes.subtotal
    IF ROUND(v_items_total, 2) <> ROUND(v_quote.subtotal, 2) THEN
      RAISE EXCEPTION USING
        errcode = '23514',
        message = 'INTEGRITY_MISMATCH: SUM(order_items.total_line_price) (' || v_items_total || ') <> quotes.subtotal (' || v_quote.subtotal || ')';
    END IF;

    -- B) orders.total = quotes.total
    IF ROUND(v_order.total, 2) <> ROUND(v_quote.total, 2) THEN
      RAISE EXCEPTION USING
        errcode = '23514',
        message = 'INTEGRITY_MISMATCH: orders.total (' || v_order.total || ') <> quotes.total (' || v_quote.total || ')';
    END IF;

    -- C) SUM(order_items.discount) = SUM(quote_items.discount)
    IF ROUND(v_items_discount, 2) <> ROUND(v_quote_items_discount, 2) THEN
      RAISE EXCEPTION USING
        errcode = '23514',
        message = 'INTEGRITY_MISMATCH: SUM(order_items.discount) (' || v_items_discount || ') <> SUM(quote_items.discount) (' || v_quote_items_discount || ')';
    END IF;

    -- Si existen productos físicos que controlen inventario, reservar
    SELECT EXISTS (
      SELECT 1
      FROM public.order_items oi
      JOIN public.products p ON p.id = oi.product_id
      WHERE oi.order_id = v_order.id
        AND oi.product_id IS NOT NULL
        AND p.track_inventory = true
    ) INTO v_has_physical_stock;

    IF v_has_physical_stock THEN
      PERFORM public.reserve_order_stock_for_payment(v_order.id, v_expiration);
    END IF;
  END IF;

  -- Reutilizar intento de pago con preferencia vigente si existe
  SELECT * INTO v_existing_payment
  FROM public.order_payments
  WHERE order_id = v_order.id
    AND status IN ('created', 'pending')
    AND preference_id IS NOT NULL
    AND checkout_url IS NOT NULL
    AND preference_expires_at IS NOT NULL
    AND preference_expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'already_paid', false,
      'reuse_preference', true,
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'payment_record_id', v_existing_payment.id,
      'external_reference', v_existing_payment.external_reference,
      'preference_id', v_existing_payment.preference_id,
      'checkout_url', v_existing_payment.checkout_url,
      'amount', v_existing_payment.amount,
      'currency_id', v_existing_payment.currency_id,
      'source_quote_id', v_quote.id,
      'expires_at', v_existing_payment.preference_expires_at
    );
  END IF;

  -- Si otra Edge Function ya reclamó este intento y está creando la preferencia (claim reciente),
  -- no cancelar ni insertar otro intento: el cliente debe esperar/reintentar.
  SELECT * INTO v_existing_payment
  FROM public.order_payments
  WHERE order_id = v_order.id
    AND status = 'pending'
    AND preference_id IS NULL
    AND checkout_url IS NULL
    AND payment_id IS NULL
    AND updated_at > now() - interval '2 minutes'
  ORDER BY updated_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'already_paid', false,
      'reuse_preference', false,
      'preference_creation_in_progress', true,
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'payment_record_id', v_existing_payment.id,
      'external_reference', v_existing_payment.external_reference,
      'amount', v_existing_payment.amount,
      'currency_id', v_existing_payment.currency_id,
      'source_quote_id', v_quote.id
    );
  END IF;

  -- Cancelar intentos previos no completados o expirados (> 2 minutos)
  UPDATE public.order_payments
  SET status = 'cancelled'::public.payment_record_status,
      status_detail = 'superseded_or_expired',
      updated_at = now()
  WHERE order_id = v_order.id
    AND status IN ('created', 'pending', 'error', 'rejected')
    AND payment_id IS NULL;

  v_external_reference := 'gom_' || replace(v_order.id::text, '-', '') || '_' || replace(gen_random_uuid()::text, '-', '');

  INSERT INTO public.order_payments (
    order_id,
    client_id,
    provider,
    environment,
    external_reference,
    status,
    amount,
    currency_id,
    raw_metadata,
    is_primary
  ) VALUES (
    v_order.id,
    v_client_id,
    'mercado_pago',
    v_payment_environment,
    v_external_reference,
    'created'::public.payment_record_status,
    v_order.total,
    'MXN',
    '{}'::jsonb,
    true
  ) RETURNING * INTO v_payment;

  RETURN jsonb_build_object(
    'already_paid', false,
    'reuse_preference', false,
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'payment_record_id', v_payment.id,
    'external_reference', v_payment.external_reference,
    'amount', v_order.total,
    'currency_id', 'MXN',
    'source_quote_id', v_quote.id,
    'expires_at', v_expiration,
    'items', jsonb_build_array(
      jsonb_build_object(
        'id', v_order.id::text,
        'title', 'Servicio/Cotización Go Medical ' || v_order.order_number,
        'quantity', 1,
        'unit_price', v_order.total,
        'currency_id', 'MXN'
      )
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_quote_order(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_quote_order(uuid, text) TO authenticated, service_role;
