-- ============================================================================
-- Migration: 20260818170000_t7_service_quote_orders_foundation.sql
-- Description: FASE 1 (Minimalista Definitiva) — Fundación backend para cotizaciones pagables.
--              - quote_items, order_items, sale_items product_id nullable
--              - order_items.discount (preserva descuentos de línea)
--              - quotes.service_ticket_id (FK service_tickets)
--              - orders.source_quote_id (FK quotes + unique active index)
--              - quotes.converted_order_id formal FK
--              - calculate_line_total (incluye order_items en cálculo de línea)
--              - recalculate_order_totals (preserva integridad financiera de quotes)
--              - apply_paid_order_post_payment (excepción única y localizada para servicio)
--              - sync_source_quote_after_order_payment + trg_sync_source_quote_after_payment
--                (conversión desacoplada e idempotente de quotes tras pago aprobado)
--              - sync_quote_order_item_discount_to_sale_item + trg_sync_quote_discount_to_sale_item
--                (preserva order_items.discount -> sale_items.discount robusto a orden de triggers)
--              - respond_to_quote (RPC autoritativa e idempotente aceptar/rechazar)
--              - prepare_quote_order (RPC autoritativa e idempotente para checkout con 3 validaciones)
--
-- EXCLUSIONES EXPLÍCITAS (PRESERVACIÓN DEL FLUJO ACTUAL):
--              - NO redefine reconcile_mercado_pago_payment ni reconcile_mp_web_order_payment
--              - NO redefine reserve_order_stock_for_payment
--              - NO agrega columnas de descuento global (quote_discount_amount)
--              - NO modifica vw_sales_items_report
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ESQUEMA: Permitir product_id NULLABLE y columna de descuento en partidas
-- ----------------------------------------------------------------------------
ALTER TABLE public.quote_items ALTER COLUMN product_id DROP NOT NULL;
ALTER TABLE public.order_items ALTER COLUMN product_id DROP NOT NULL;
ALTER TABLE public.sale_items ALTER COLUMN product_id DROP NOT NULL;
-- Columna para preservar descuento de línea en pedidos
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS discount numeric NOT NULL DEFAULT 0;
-- ----------------------------------------------------------------------------
-- 2. RELACIONES: quotes -> service_tickets
-- ----------------------------------------------------------------------------
ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS service_ticket_id uuid NULL
  REFERENCES public.service_tickets(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_quotes_service_ticket_id
  ON public.quotes(service_ticket_id)
  WHERE service_ticket_id IS NOT NULL;
-- ----------------------------------------------------------------------------
-- 3. RELACIONES: orders -> quotes (source_quote_id) e ÍNDICE DE IDEMPOTENCIA
-- ----------------------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS source_quote_id uuid NULL
  REFERENCES public.quotes(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_source_quote_id_active
  ON public.orders (source_quote_id)
  WHERE source_quote_id IS NOT NULL AND status <> 'canceled'::public.order_status;
-- ----------------------------------------------------------------------------
-- 4. FK FORMAL: quotes.converted_order_id -> orders(id)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_quotes_converted_order' AND table_name = 'quotes'
  ) THEN
    ALTER TABLE public.quotes
      ADD CONSTRAINT fk_quotes_converted_order
      FOREIGN KEY (converted_order_id) REFERENCES public.orders(id) ON DELETE SET NULL;
  END IF;
END $$;
-- ----------------------------------------------------------------------------
-- 5. CÁLCULO DE LÍNEA: calculate_line_total (incluye order_items)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_line_total()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF tg_table_name IN ('quote_items', 'sale_items', 'order_items') THEN
    NEW.total_line_price := round((NEW.quantity * NEW.unit_price) - coalesce(NEW.discount, 0), 2);
  ELSE
    NEW.total_line_price := round(NEW.quantity * NEW.unit_price, 2);
  END IF;

  RETURN NEW;
END;
$function$;
-- ----------------------------------------------------------------------------
-- 6. INTEGRIDAD FINANCIERA: recalculate_order_totals
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recalculate_order_totals(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_order record;
  v_quote record;
  v_items_subtotal numeric(12,2) := 0;
  v_coupon_discount numeric(12,2) := 0;
  v_product_payable numeric(12,2) := 0;
  v_customer_shipping_amount numeric(12,2) := 0;
  v_tax_pct numeric := 0.16;
  v_tax numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN;
  END IF;

  SELECT
    id,
    source_quote_id,
    COALESCE(tax_exempt, false) AS tax_exempt,
    COALESCE(tax_pct, 0.16) AS tax_pct,
    COALESCE(coupon_discount_amount, 0) AS coupon_discount_amount,
    COALESCE(customer_shipping_amount, 0) AS customer_shipping_amount
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Si la orden proviene de una cotización, preservar la estructura financiera de la cotización
  IF v_order.source_quote_id IS NOT NULL THEN
    SELECT
      subtotal,
      tax_pct,
      tax_exempt,
      tax,
      total
    INTO v_quote
    FROM public.quotes
    WHERE id = v_order.source_quote_id;

    IF FOUND THEN
      v_customer_shipping_amount := ROUND(
        GREATEST(COALESCE(v_order.customer_shipping_amount, 0), 0),
        2
      );

      UPDATE public.orders
      SET subtotal = v_quote.subtotal,
          tax_pct = v_quote.tax_pct,
          tax_exempt = v_quote.tax_exempt,
          tax = v_quote.tax,
          total = ROUND(v_quote.total + v_customer_shipping_amount, 2),
          updated_at = now()
      WHERE id = p_order_id;
      RETURN;
    END IF;
  END IF;

  -- Flujo estándar para compras normales de catálogo desde carrito (precios ya incluyen IVA)
  SELECT COALESCE(
    ROUND(
      SUM(
        ROUND(
          GREATEST(
            COALESCE(
              oi.total_line_price,
              COALESCE(oi.unit_price, 0) * COALESCE(oi.quantity, 0) - COALESCE(oi.discount, 0),
              0
            ),
            0
          ),
          2
        )
      ),
      2
    ),
    0
  )
  INTO v_items_subtotal
  FROM public.order_items oi
  WHERE oi.order_id = p_order_id;

  v_coupon_discount := ROUND(
    GREATEST(COALESCE(v_order.coupon_discount_amount, 0), 0),
    2
  );
  v_product_payable := ROUND(
    GREATEST(v_items_subtotal - v_coupon_discount, 0),
    2
  );

  v_customer_shipping_amount := ROUND(
    GREATEST(COALESCE(v_order.customer_shipping_amount, 0), 0),
    2
  );

  IF COALESCE(v_order.tax_pct, 0.16) <= -1 THEN
    v_tax_pct := 0.16;
  ELSE
    v_tax_pct := COALESCE(v_order.tax_pct, 0.16);
  END IF;

  IF v_order.tax_exempt THEN
    v_tax := 0;
  ELSE
    v_tax := ROUND(
      v_product_payable - (v_product_payable / (1 + v_tax_pct)),
      2
    );
  END IF;

  v_total := ROUND(GREATEST(v_product_payable + v_customer_shipping_amount, 0), 2);

  UPDATE public.orders
  SET subtotal = v_items_subtotal,
      tax = v_tax,
      total = v_total,
      updated_at = now()
  WHERE id = p_order_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.recalculate_order_totals(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recalculate_order_totals(uuid) TO service_role;
-- ----------------------------------------------------------------------------
-- 7. ADAPTACIÓN DE POST-PAGO: apply_paid_order_post_payment
-- ----------------------------------------------------------------------------
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
      -- Excepción localizada ÚNICAMENTE para órdenes de servicio técnico confirmadas
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

      -- Pedidos normales de carrito sin ítems físicos: comportamiento 100% idéntico al original
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
REVOKE ALL ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) TO service_role;
-- ----------------------------------------------------------------------------
-- 8. TRIGGER DE CONVERSIÓN DE COTIZACIÓN TRAS PAGO APROBADO (DESACOPLADO)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_source_quote_after_order_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
BEGIN
  -- Solo actuar si la orden está ligada a una cotización y su payment_status cambió a approved
  IF NEW.source_quote_id IS NOT NULL
     AND NEW.payment_status = 'approved'::public.payment_record_status
     AND (TG_OP = 'INSERT' OR OLD.payment_status IS DISTINCT FROM NEW.payment_status) THEN

    UPDATE public.quotes
    SET status = 'converted'::public.quote_status,
        converted_order_id = NEW.id,
        updated_at = now()
    WHERE id = NEW.source_quote_id
      AND status = 'approved'::public.quote_status;
  END IF;

  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_source_quote_after_order_payment() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_source_quote_after_order_payment() TO service_role;
DROP TRIGGER IF EXISTS trg_sync_source_quote_after_payment ON public.orders;
CREATE TRIGGER trg_sync_source_quote_after_payment
  AFTER INSERT OR UPDATE OF payment_status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_source_quote_after_order_payment();
-- ----------------------------------------------------------------------------
-- 9. TRIGGER: Preservar order_items.discount -> sale_items.discount (DESACOPLADO)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_quote_order_item_discount_to_sale_item()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
  v_order_id uuid;
  v_source_quote_id uuid;
  v_distinct_discounts numeric(12,2)[];
  v_candidate_count integer;
BEGIN
  -- 1. Obtener el order_id y verificar si la venta proviene de una cotización
  SELECT s.order_id, o.source_quote_id
  INTO v_order_id, v_source_quote_id
  FROM public.sales s
  JOIN public.orders o ON o.id = s.order_id
  WHERE s.id = NEW.sale_id;

  -- 2. Si no proviene de cotización, retornar NEW inmediatamente (0 impacto en compras normales de carrito)
  IF v_source_quote_id IS NULL OR v_order_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 3. Localizar candidatos en order_items correlacionando por atributos estables
  SELECT
    array_agg(DISTINCT oi.discount),
    COUNT(*)
  INTO v_distinct_discounts, v_candidate_count
  FROM public.order_items oi
  WHERE oi.order_id = v_order_id
    AND oi.product_id IS NOT DISTINCT FROM NEW.product_id
    AND oi.sku_snapshot IS NOT DISTINCT FROM NEW.sku_snapshot
    AND oi.product_name_snapshot IS NOT DISTINCT FROM NEW.product_name_snapshot
    AND oi.product_category_snapshot IS NOT DISTINCT FROM NEW.product_category_snapshot
    AND oi.quantity = NEW.quantity
    AND oi.unit_price = NEW.unit_price;

  -- 4. Evaluar candidatos de forma determinista y fail-closed
  IF v_candidate_count = 0 OR v_distinct_discounts IS NULL OR array_length(v_distinct_discounts, 1) = 0 THEN
    RAISE EXCEPTION USING
      errcode = '22023',
      message = 'No se encontró la partida en la orden de cotización para calcular el descuento.';
  ELSIF array_length(v_distinct_discounts, 1) > 1 THEN
    RAISE EXCEPTION USING
      errcode = '22023',
      message = 'Partidas ambiguas con diferentes descuentos en la orden de cotización.';
  ELSE
    -- Un solo candidato o múltiples con el mismo descuento exacto
    NEW.discount := v_distinct_discounts[1];
    NEW.total_line_price := ROUND(
      (COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_price, 0)) - COALESCE(NEW.discount, 0),
      2
    );
  END IF;

  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_quote_order_item_discount_to_sale_item() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_quote_order_item_discount_to_sale_item() TO service_role;
DROP TRIGGER IF EXISTS trg_sync_quote_discount_to_sale_item ON public.sale_items;
CREATE TRIGGER trg_sync_quote_discount_to_sale_item
  BEFORE INSERT ON public.sale_items
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_quote_order_item_discount_to_sale_item();
-- ----------------------------------------------------------------------------
-- 10. RPC AUTORITATIVA: respond_to_quote (Aceptar o Rechazar cotización)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.respond_to_quote(
  p_quote_id uuid,
  p_accept boolean
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
  v_new_status public.quote_status;
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

  IF v_quote.status = 'converted' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'La cotización ya fue convertida en pedido.';
  END IF;

  IF v_quote.status = 'expired' OR (v_quote.valid_until IS NOT NULL AND v_quote.valid_until < CURRENT_DATE) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'La cotización ha vencido y no admite respuesta.';
  END IF;

  -- Idempotencia: Si ya estaba en el mismo estado, retornar éxito sin sobreescribir timestamp
  IF p_accept AND v_quote.status = 'approved' THEN
    RETURN jsonb_build_object(
      'success', true,
      'quote_id', v_quote.id,
      'quote_number', v_quote.quote_number,
      'status', 'approved',
      'approved_at', v_quote.approved_at,
      'rejected_at', NULL,
      'idempotent', true
    );
  END IF;

  IF NOT p_accept AND v_quote.status = 'rejected' THEN
    RETURN jsonb_build_object(
      'success', true,
      'quote_id', v_quote.id,
      'quote_number', v_quote.quote_number,
      'status', 'rejected',
      'approved_at', NULL,
      'rejected_at', v_quote.rejected_at,
      'idempotent', true
    );
  END IF;

  -- Transiciones conflictivas
  IF p_accept AND v_quote.status = 'rejected' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'La cotización ya fue rechazada previamente y no admite aprobación directa.';
  END IF;

  IF NOT p_accept AND v_quote.status = 'approved' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'La cotización ya fue aceptada previamente.';
  END IF;

  IF v_quote.status <> 'sent' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'La cotización no está en estado para responder.';
  END IF;

  IF p_accept THEN
    v_new_status := 'approved'::public.quote_status;
    UPDATE public.quotes
    SET status = v_new_status,
        approved_at = now(),
        rejected_at = NULL,
        updated_at = now()
    WHERE id = v_quote.id;
  ELSE
    v_new_status := 'rejected'::public.quote_status;
    UPDATE public.quotes
    SET status = v_new_status,
        rejected_at = now(),
        approved_at = NULL,
        updated_at = now()
    WHERE id = v_quote.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'quote_id', v_quote.id,
    'quote_number', v_quote.quote_number,
    'status', v_new_status::text,
    'approved_at', CASE WHEN p_accept THEN now() ELSE NULL END,
    'rejected_at', CASE WHEN NOT p_accept THEN now() ELSE NULL END,
    'idempotent', false
  );
END;
$$;
REVOKE ALL ON FUNCTION public.respond_to_quote(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_to_quote(uuid, boolean) TO authenticated, service_role;
-- ----------------------------------------------------------------------------
-- 11. RPC AUTORITATIVA: prepare_quote_order (Genera orden pagable desde cotización)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.prepare_quote_order(uuid, text, text);
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

  -- Cancelar intentos previos no completados
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
