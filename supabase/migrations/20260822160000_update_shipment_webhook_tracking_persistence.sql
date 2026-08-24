-- Migration: Update record_skydropx_shipment_event to persist tracking_number, tracking_url, and label_url
CREATE OR REPLACE FUNCTION public.record_skydropx_shipment_event(
  p_skydropx_shipment_id text DEFAULT NULL,
  p_tracking_number text DEFAULT NULL,
  p_tracking_url text DEFAULT NULL,
  p_label_url text DEFAULT NULL,
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

  UPDATE public.order_shipments
  SET shipping_status = COALESCE(v_local_status, shipping_status),
      tracking_number = COALESCE(NULLIF(btrim(p_tracking_number), ''), tracking_number),
      tracking_url = COALESCE(NULLIF(btrim(p_tracking_url), ''), tracking_url),
      label_url = COALESCE(NULLIF(btrim(p_label_url), ''), label_url),
      updated_at = now()
  WHERE id = v_shipment.id
  RETURNING * INTO v_shipment;

  IF v_local_status IS NOT NULL THEN
    v_sync_result := public.sync_order_status_from_shipping(v_shipment.id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'shipment_id', v_shipment.id,
    'inserted', v_inserted,
    'provider_status', v_provider_status,
    'local_status', v_local_status,
    'tracking_number', v_shipment.tracking_number,
    'tracking_url', v_shipment.tracking_url,
    'label_url', v_shipment.label_url,
    'sync_result', v_sync_result
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, text, text, timestamptz, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, text, text, timestamptz, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, text, text, timestamptz, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.record_skydropx_shipment_event(text, text, text, text, text, text, text, timestamptz, jsonb) TO service_role;
