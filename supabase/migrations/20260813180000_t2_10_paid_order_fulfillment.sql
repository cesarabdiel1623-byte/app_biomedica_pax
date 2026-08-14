-- T2.10: Fulfillment post-pago idempotente.
-- Local solamente. No ejecutar db push sin autorizacion.

BEGIN;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS stock_status text;
ALTER TABLE public.shipment_events
  ADD COLUMN IF NOT EXISTS provider_status text,
  ADD COLUMN IF NOT EXISTS event_key text,
  ADD COLUMN IF NOT EXISTS raw_payload jsonb;
CREATE UNIQUE INDEX IF NOT EXISTS idx_order_shipments_skydropx_id_unique
  ON public.order_shipments (skydropx_shipment_id)
  WHERE skydropx_shipment_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_shipment_events_event_key_unique
  ON public.shipment_events (shipment_id, event_key)
  WHERE event_key IS NOT NULL;
CREATE OR REPLACE FUNCTION public.apply_paid_order_post_payment(
  p_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
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
      RETURN jsonb_build_object(
        'success', false,
        'error', 'order_has_no_stock_items',
        'order_id', v_order.id,
        'stock_deducted', false
      );
    END IF;

    PERFORM 1
    FROM public.product_inventory pi
    JOIN (
      SELECT oi.product_id, sum(greatest(coalesce(oi.quantity, 0), 0)) AS qty
      FROM public.order_items oi
      WHERE oi.order_id = v_order.id
        AND oi.product_id IS NOT NULL
      GROUP BY oi.product_id
    ) items ON items.product_id = pi.product_id
    ORDER BY pi.product_id
    FOR UPDATE;

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
      WHERE pi.product_id = v_item.product_id
      FOR UPDATE;

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
$$;
CREATE OR REPLACE FUNCTION public.record_skydropx_order_shipment(
  p_order_id uuid,
  p_skydropx_shipment_id text,
  p_carrier text DEFAULT NULL,
  p_service_name text DEFAULT NULL,
  p_tracking_number text DEFAULT NULL,
  p_tracking_url text DEFAULT NULL,
  p_label_url text DEFAULT NULL,
  p_shipping_status text DEFAULT 'pending',
  p_estimated_delivery timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
  v_order_id uuid;
  v_existing public.order_shipments%rowtype;
  v_status text;
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'order_id_required';
  END IF;

  IF p_skydropx_shipment_id IS NULL OR btrim(p_skydropx_shipment_id) = '' THEN
    RAISE EXCEPTION 'skydropx_shipment_id_required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_order_id::text));

  SELECT id INTO v_order_id
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  v_status := lower(btrim(COALESCE(p_shipping_status, 'pending')));
  IF v_status = 'created' THEN
    v_status := 'label_created';
  END IF;
  IF v_status NOT IN (
    'pending',
    'label_created',
    'ready_to_ship',
    'picked_up',
    'in_transit',
    'out_for_delivery',
    'delivered',
    'exception',
    'canceled'
  ) THEN
    v_status := 'pending';
  END IF;

  SELECT *
  INTO v_existing
  FROM public.order_shipments
  WHERE skydropx_shipment_id = p_skydropx_shipment_id
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.order_shipments
    SET carrier = COALESCE(NULLIF(btrim(p_carrier), ''), carrier),
        service_name = COALESCE(NULLIF(btrim(p_service_name), ''), service_name),
        tracking_number = COALESCE(NULLIF(btrim(p_tracking_number), ''), tracking_number),
        tracking_url = COALESCE(NULLIF(btrim(p_tracking_url), ''), tracking_url),
        label_url = COALESCE(NULLIF(btrim(p_label_url), ''), label_url),
        shipping_status = COALESCE(v_status, shipping_status),
        estimated_delivery = COALESCE(p_estimated_delivery, estimated_delivery),
        updated_at = now()
    WHERE id = v_existing.id
    RETURNING * INTO v_existing;

    RETURN jsonb_build_object(
      'success', true,
      'shipment_id', v_existing.id,
      'skydropx_shipment_id', v_existing.skydropx_shipment_id,
      'reused', true
    );
  END IF;

  SELECT *
  INTO v_existing
  FROM public.order_shipments
  WHERE order_id = p_order_id
    AND skydropx_shipment_id IS NOT NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'shipment_id', v_existing.id,
      'skydropx_shipment_id', v_existing.skydropx_shipment_id,
      'reused', true,
      'reason', 'order_already_has_shipment'
    );
  END IF;

  INSERT INTO public.order_shipments (
    order_id,
    skydropx_shipment_id,
    carrier,
    service_name,
    tracking_number,
    tracking_url,
    label_url,
    shipping_status,
    estimated_delivery
  ) VALUES (
    p_order_id,
    btrim(p_skydropx_shipment_id),
    NULLIF(btrim(p_carrier), ''),
    NULLIF(btrim(p_service_name), ''),
    NULLIF(btrim(p_tracking_number), ''),
    NULLIF(btrim(p_tracking_url), ''),
    NULLIF(btrim(p_label_url), ''),
    v_status,
    p_estimated_delivery
  )
  RETURNING * INTO v_existing;

  RETURN jsonb_build_object(
    'success', true,
    'shipment_id', v_existing.id,
    'skydropx_shipment_id', v_existing.skydropx_shipment_id,
    'reused', false
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.record_skydropx_shipment_event(
  p_skydropx_shipment_id text DEFAULT NULL,
  p_tracking_number text DEFAULT NULL,
  p_provider_status text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_event_at timestamptz DEFAULT NULL,
  p_raw_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
  v_shipment public.order_shipments%rowtype;
  v_provider_status text;
  v_local_status text;
  v_event_status text;
  v_event_at timestamptz;
  v_event_key text;
  v_inserted boolean := false;
  v_inserted_count integer := 0;
  v_sync_result jsonb;
BEGIN
  IF (p_skydropx_shipment_id IS NULL OR btrim(p_skydropx_shipment_id) = '')
     AND (p_tracking_number IS NULL OR btrim(p_tracking_number) = '') THEN
    RAISE EXCEPTION 'shipment_identifier_required';
  END IF;

  v_provider_status := lower(btrim(COALESCE(p_provider_status, '')));
  IF v_provider_status = '' THEN
    RAISE EXCEPTION 'provider_status_required';
  END IF;

  SELECT *
  INTO v_shipment
  FROM public.order_shipments
  WHERE (p_skydropx_shipment_id IS NOT NULL AND skydropx_shipment_id = btrim(p_skydropx_shipment_id))
     OR (p_tracking_number IS NOT NULL AND tracking_number = btrim(p_tracking_number))
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'ignored', true,
      'reason', 'shipment_not_found'
    );
  END IF;

  v_local_status := CASE v_provider_status
    WHEN 'created' THEN 'label_created'
    WHEN 'picked_up' THEN 'picked_up'
    WHEN 'in_transit' THEN 'in_transit'
    WHEN 'last_mile' THEN 'out_for_delivery'
    WHEN 'delivered' THEN 'delivered'
    WHEN 'exception' THEN 'exception'
    WHEN 'retained' THEN 'exception'
    WHEN 'delivery_attempt' THEN 'exception'
    WHEN 'canceled' THEN 'canceled'
    ELSE NULL
  END;

  v_event_status := COALESCE(v_local_status, v_provider_status);
  v_event_at := COALESCE(p_event_at, now());
  v_event_key := md5(
    v_shipment.id::text || '|' ||
    v_event_status || '|' ||
    COALESCE(v_event_at::text, '') || '|' ||
    COALESCE(v_shipment.tracking_number, btrim(COALESCE(p_tracking_number, '')))
  );

  INSERT INTO public.shipment_events (
    shipment_id,
    status,
    provider_status,
    description,
    location,
    event_at,
    event_key,
    raw_payload
  ) VALUES (
    v_shipment.id,
    v_event_status,
    v_provider_status,
    NULLIF(btrim(p_description), ''),
    NULLIF(btrim(p_location), ''),
    v_event_at,
    v_event_key,
    COALESCE(p_raw_payload, '{}'::jsonb)
  )
  ON CONFLICT (shipment_id, event_key) WHERE event_key IS NOT NULL DO NOTHING;

  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;
  v_inserted := v_inserted_count > 0;

  IF v_local_status IS NOT NULL THEN
    UPDATE public.order_shipments
    SET shipping_status = v_local_status,
        updated_at = now()
    WHERE id = v_shipment.id
    RETURNING * INTO v_shipment;

    v_sync_result := public.sync_order_status_from_shipping(v_shipment.id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'shipment_id', v_shipment.id,
    'inserted', v_inserted,
    'provider_status', v_provider_status,
    'local_status', v_local_status,
    'sync_result', v_sync_result
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_order_shipment(uuid, text, text, text, text, text, text, text, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_order_shipment(uuid, text, text, text, text, text, text, text, timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_order_shipment(uuid, text, text, text, text, text, text, text, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.record_skydropx_order_shipment(uuid, text, text, text, text, text, text, text, timestamptz) TO service_role;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, timestamptz, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, timestamptz, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, timestamptz, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, timestamptz, jsonb) TO service_role;
GRANT SELECT (
  id,
  shipment_id,
  status,
  description,
  location,
  event_at,
  created_at
) ON public.shipment_events TO authenticated;
CREATE OR REPLACE VIEW public.customer_shipment_events
WITH (security_invoker = true) AS
SELECT
  e.id,
  e.shipment_id,
  e.status,
  e.description,
  e.location,
  e.event_at,
  e.created_at
FROM public.shipment_events e;
GRANT SELECT ON public.customer_shipment_events TO authenticated;
REVOKE ALL ON public.customer_shipment_events FROM anon, PUBLIC;
COMMIT;
