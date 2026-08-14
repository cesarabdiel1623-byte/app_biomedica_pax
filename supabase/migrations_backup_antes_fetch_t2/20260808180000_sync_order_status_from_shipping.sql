-- S1: Sincronizacion explicita de estado comercial desde estado logistico persistido.
-- No crea triggers automaticos; debe ser invocada por backend confiable/service_role.

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_order_status_from_shipping(
  p_shipment_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_order_id UUID;
  v_shipment RECORD;
  v_order public.orders%ROWTYPE;
  v_shipping_status TEXT;
  v_target_status public.order_status;
  v_blocked_reason TEXT;
  v_reason TEXT;
  v_total_shipments INTEGER;
  v_delivered_shipments INTEGER;
BEGIN
  IF p_shipment_id IS NULL THEN
    RAISE EXCEPTION 'p_shipment_id is required';
  END IF;

  SELECT s.order_id
  INTO v_order_id
  FROM public.order_shipments s
  WHERE s.id = p_shipment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Shipment % not found', p_shipment_id;
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = v_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order % not found for shipment %', v_order_id, p_shipment_id;
  END IF;

  PERFORM 1
  FROM public.order_shipments s
  WHERE s.order_id = v_order.id
  ORDER BY s.id
  FOR UPDATE;

  SELECT
    s.id,
    s.order_id,
    s.shipping_status
  INTO v_shipment
  FROM public.order_shipments s
  WHERE s.id = p_shipment_id
    AND s.order_id = v_order.id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Shipment % no longer belongs to order %', p_shipment_id, v_order.id;
  END IF;

  v_shipping_status := lower(trim(COALESCE(v_shipment.shipping_status, '')));

  IF v_shipping_status = '' THEN
    RAISE EXCEPTION 'Shipment % has empty shipping_status', p_shipment_id;
  END IF;

  IF v_shipping_status NOT IN (
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
    RAISE EXCEPTION 'Unsupported shipping_status for shipment %: %', p_shipment_id, v_shipment.shipping_status;
  END IF;

  SELECT
    count(*)::INTEGER,
    count(*) FILTER (
      WHERE lower(trim(COALESCE(s.shipping_status, ''))) = 'delivered'
    )::INTEGER
  INTO v_total_shipments, v_delivered_shipments
  FROM public.order_shipments s
  WHERE s.order_id = v_order.id;

  IF v_shipping_status IN ('picked_up', 'in_transit', 'out_for_delivery') THEN
    v_target_status := 'shipped'::public.order_status;
  ELSIF v_shipping_status = 'delivered' THEN
    IF v_delivered_shipments = v_total_shipments THEN
      v_target_status := 'delivered'::public.order_status;
    ELSIF v_order.status IN ('paid'::public.order_status, 'processing'::public.order_status) THEN
      v_target_status := 'shipped'::public.order_status;
      v_reason := 'waiting_for_remaining_shipments';
    ELSE
      v_target_status := NULL;
      v_reason := 'waiting_for_remaining_shipments';
    END IF;
  ELSE
    v_target_status := NULL;
  END IF;

  IF v_target_status IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'changed', false,
      'shipment_id', v_shipment.id,
      'order_id', v_order.id,
      'shipping_status', v_shipping_status,
      'order_status', v_order.status,
      'reason', COALESCE(v_reason, 'shipping_status_does_not_change_order_status'),
      'total_shipments', v_total_shipments,
      'delivered_shipments', v_delivered_shipments
    );
  END IF;

  IF v_order.status = v_target_status THEN
    RETURN jsonb_build_object(
      'success', true,
      'changed', false,
      'shipment_id', v_shipment.id,
      'order_id', v_order.id,
      'shipping_status', v_shipping_status,
      'order_status', v_order.status,
      'reason', COALESCE(v_reason, 'already_in_target_status'),
      'total_shipments', v_total_shipments,
      'delivered_shipments', v_delivered_shipments
    );
  END IF;

  IF v_order.status = 'delivered'::public.order_status
     AND v_target_status = 'shipped'::public.order_status THEN
    v_blocked_reason := 'delivered_to_shipped_prohibited';
  ELSIF v_order.status = 'canceled'::public.order_status
        AND v_target_status IN ('shipped'::public.order_status, 'delivered'::public.order_status) THEN
    v_blocked_reason := 'canceled_order_never_revives';
  ELSIF v_target_status = 'shipped'::public.order_status
        AND v_order.status NOT IN ('paid'::public.order_status, 'processing'::public.order_status) THEN
    v_blocked_reason := 'invalid_transition_to_shipped';
  ELSIF v_target_status = 'delivered'::public.order_status
        AND v_order.status NOT IN ('paid'::public.order_status, 'processing'::public.order_status, 'shipped'::public.order_status) THEN
    v_blocked_reason := 'invalid_transition_to_delivered';
  END IF;

  IF v_blocked_reason IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'changed', false,
      'blocked', true,
      'shipment_id', v_shipment.id,
      'order_id', v_order.id,
      'shipping_status', v_shipping_status,
      'order_status', v_order.status,
      'target_status', v_target_status,
      'reason', COALESCE(v_reason, v_blocked_reason),
      'blocked_reason', v_blocked_reason,
      'total_shipments', v_total_shipments,
      'delivered_shipments', v_delivered_shipments
    );
  END IF;

  UPDATE public.orders
  SET status = v_target_status,
      updated_at = now()
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  RETURN jsonb_build_object(
    'success', true,
    'changed', true,
    'shipment_id', v_shipment.id,
    'order_id', v_order.id,
    'shipping_status', v_shipping_status,
    'order_status', v_order.status,
    'reason', v_reason,
    'total_shipments', v_total_shipments,
    'delivered_shipments', v_delivered_shipments
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sync_order_status_from_shipping(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sync_order_status_from_shipping(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.sync_order_status_from_shipping(UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.sync_order_status_from_shipping(UUID) TO service_role;

COMMIT;
