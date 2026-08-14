-- T2.10.1: Corrige lock de inventario en fulfillment post-pago.
-- Local solamente. No ejecutar db push sin autorizacion.
--
-- Causa corregida:
-- PostgreSQL no permite FOR UPDATE en una consulta cuya estructura incluye
-- GROUP BY. El bloqueo de product_inventory se separa del calculo agregado
-- de cantidades por producto.

BEGIN;
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
$$;
REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) TO service_role;
COMMIT;
