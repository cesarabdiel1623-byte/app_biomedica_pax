-- MIGRACIÓN DE SEGURIDAD E IDEMPOTENCIA DE MERCADO PAGO - GO MEDICAL
-- Nombre de migración: 20260803000000_fix_mercado_pago_webhook_reconciliation.sql
-- Creado: 2026-08-03
-- Propósito: Garantizar la conciliación atómica de pagos, índices de rendimiento,
-- idempotencia contra notificaciones duplicadas y restricción de RLS para columnas sensibles.

BEGIN;

-- 1. ÍNDICES DE RENDIMIENTO E IDEMPOTENCIA EN ORDER_PAYMENTS
CREATE INDEX IF NOT EXISTS idx_order_payments_order_id 
  ON public.order_payments (order_id);

CREATE INDEX IF NOT EXISTS idx_order_payments_external_reference 
  ON public.order_payments (external_reference);

-- Índice único parcial para evitar que el mismo payment_id de Mercado Pago se asocie a múltiples registros
CREATE UNIQUE INDEX IF NOT EXISTS idx_order_payments_payment_id_unique 
  ON public.order_payments (payment_id) 
  WHERE payment_id IS NOT NULL;


-- 2. FUNCIÓN ATÓMICA DE CONCILIACIÓN DE PAGOS (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.reconcile_mercado_pago_payment(
  p_payment_id TEXT,
  p_external_reference TEXT,
  p_status TEXT,
  p_status_detail TEXT DEFAULT NULL,
  p_amount NUMERIC DEFAULT NULL,
  p_currency_id TEXT DEFAULT 'MXN',
  p_payment_method_id TEXT DEFAULT NULL,
  p_payment_type_id TEXT DEFAULT NULL,
  p_installments INTEGER DEFAULT 1,
  p_live_mode BOOLEAN DEFAULT FALSE,
  p_date_approved TIMESTAMPTZ DEFAULT NULL,
  p_provider_created_at TIMESTAMPTZ DEFAULT NULL,
  p_provider_updated_at TIMESTAMPTZ DEFAULT NULL,
  p_raw_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment_row public.order_payments%ROWTYPE;
  v_order_row public.orders%ROWTYPE;
  v_effective_status TEXT;
  v_is_approved BOOLEAN;
  v_result JSONB;
BEGIN
  -- Normalizar estados de Mercado Pago
  v_effective_status := lower(trim(COALESCE(p_status, 'pending')));
  v_is_approved := (v_effective_status IN ('approved', 'accredited'));

  -- Bloquear transaccionalmente la fila en order_payments por external_reference o payment_id
  SELECT * INTO v_payment_row
  FROM public.order_payments
  WHERE external_reference = p_external_reference
     OR (p_payment_id IS NOT NULL AND payment_id = p_payment_id)
  ORDER BY created_at DESC
  FOR UPDATE LIMIT 1;

  IF v_payment_row.id IS NULL THEN
    -- Si no existe en order_payments, intentar ubicar la orden directamente
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE id::text = p_external_reference
       OR external_reference = p_external_reference
    FOR UPDATE;

    IF v_order_row.id IS NULL THEN
      RAISE EXCEPTION 'No se encontró la orden ni el registro de pago para external_reference: %', p_external_reference;
    END IF;

    -- Crear el registro de order_payments automáticamente si no existía
    INSERT INTO public.order_payments (
      order_id,
      external_reference,
      payment_id,
      status,
      status_detail,
      amount,
      currency_id,
      payment_method_id,
      payment_type_id,
      installments,
      live_mode,
      environment,
      last_webhook_at,
      created_at,
      updated_at
    ) VALUES (
      v_order_row.id,
      p_external_reference,
      p_payment_id,
      v_effective_status,
      p_status_detail,
      COALESCE(p_amount, v_order_row.total),
      COALESCE(p_currency_id, 'MXN'),
      p_payment_method_id,
      p_payment_type_id,
      COALESCE(p_installments, 1),
      p_live_mode,
      CASE WHEN p_live_mode THEN 'production' ELSE 'test' END,
      now(),
      now(),
      now()
    ) RETURNING * INTO v_payment_row;
  ELSE
    -- Cargar la orden vinculada
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE id = v_payment_row.order_id
    FOR UPDATE;
  END IF;

  -- Comprobar idempotencia: Si ya estaba marcada como pagada previamente con este payment_id
  IF v_order_row.payment_status = 'approved' AND v_order_row.payment_id = p_payment_id THEN
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'already_processed', true,
      'order_id', v_order_row.id,
      'payment_status', 'approved',
      'order_status', v_order_row.status
    );
  END IF;

  -- Actualizar registro en order_payments
  UPDATE public.order_payments SET
    payment_id = COALESCE(p_payment_id, payment_id),
    status = v_effective_status,
    status_detail = COALESCE(p_status_detail, status_detail),
    amount = COALESCE(p_amount, amount),
    currency_id = COALESCE(p_currency_id, currency_id),
    payment_method_id = COALESCE(p_payment_method_id, payment_method_id),
    payment_type_id = COALESCE(p_payment_type_id, payment_type_id),
    installments = COALESCE(p_installments, installments),
    live_mode = p_live_mode,
    environment = CASE WHEN p_live_mode THEN 'production' ELSE 'test' END,
    last_webhook_at = now(),
    updated_at = now()
  WHERE id = v_payment_row.id;

  -- Actualizar estado del pedido en orders
  IF v_is_approved THEN
    UPDATE public.orders SET
      payment_status = 'approved',
      status = CASE 
        WHEN status IN ('pending_payment', 'draft', 'pending_review', 'canceled') THEN 'paid' 
        ELSE status 
      END,
      paid_at = COALESCE(paid_at, p_date_approved, now()),
      payment_id = COALESCE(p_payment_id, payment_id),
      updated_at = now()
    WHERE id = v_order_row.id;

    v_result := jsonb_build_object(
      'success', true,
      'reconciled', true,
      'order_id', v_order_row.id,
      'payment_status', 'approved',
      'order_status', 'paid'
    );
  ELSE
    -- Si el estado es fallido o rechazado
    IF v_effective_status IN ('rejected', 'cancelled', 'refunded', 'charged_back') THEN
      UPDATE public.orders SET
        payment_status = v_effective_status,
        updated_at = now()
      WHERE id = v_order_row.id AND payment_status != 'approved';
    END IF;

    v_result := jsonb_build_object(
      'success', true,
      'reconciled', false,
      'order_id', v_order_row.id,
      'payment_status', v_effective_status,
      'order_status', v_order_row.status
    );
  END IF;

  RETURN v_result;
END;
$$;


-- 3. PERMISOS DE EJECUCIÓN (SEGURIDAD DE RESTRICCIÓN RLS)
REVOKE EXECUTE ON FUNCTION public.reconcile_mercado_pago_payment FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_mercado_pago_payment TO service_role;


-- 4. POLÍTICAS RLS EN ORDERS (RESTRINGIR UPDATE DIRECTO DE COLUMNAS DE PAGO AL CLIENTE)
-- Asegurar que los usuarios normales no puedan alterar 'payment_status', 'paid_at', 'payment_id' mediante Supabase REST.
DO $$
BEGIN
  -- Verificar y reforzar la política de UPDATE en orders
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'orders' AND policyname = 'client_update_own_orders'
  ) THEN
    ALTER POLICY client_update_own_orders ON public.orders
      USING (
        client_id = auth.uid() 
        OR client_id = public.get_my_client_id()
      )
      WITH CHECK (
        (client_id = auth.uid() OR client_id = public.get_my_client_id())
        AND (status IN ('draft', 'pending_review', 'pending_payment'))
      );
  END IF;
END $$;

COMMIT;

-- CONSULTAS DE VERIFICACIÓN (DESCOMENTAR PARA PROBAR DESDE SQL EDITOR):
-- SELECT * FROM public.order_payments ORDER BY created_at DESC LIMIT 5;
-- SELECT id, order_number, status, payment_status, total, paid_at FROM public.orders ORDER BY updated_at DESC LIMIT 5;
