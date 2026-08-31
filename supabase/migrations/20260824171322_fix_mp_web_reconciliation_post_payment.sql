CREATE OR REPLACE FUNCTION public.reconcile_mp_web_order_payment(
    p_external_reference text,
    p_payment_id text,
    p_amount numeric,
    p_currency_id text,
    p_status text,
    p_status_detail text,
    p_payment_method_id text,
    p_payment_type_id text,
    p_installments integer,
    p_live_mode boolean,
    p_date_approved timestamptz,
    p_provider_created_at timestamptz,
    p_provider_updated_at timestamptz,
    p_environment text,
    p_raw_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_payment record;
    v_order record;
BEGIN
    /*
     * Adaptador autoritativo para pagos web de Mercado Pago.
     *
     * Responsabilidades propias de esta función:
     * - localizar el intento web;
     * - validar identidad payment/order;
     * - validar payment_id;
     * - validar monto y moneda;
     * - validar ambiente TEST/PRODUCTION;
     * - validar live_mode.
     *
     * Una vez validados los datos, la reconciliación y finalización
     * post-pago se delegan a reconcile_mercado_pago_payment().
     */

    SELECT *
    INTO v_payment
    FROM public.order_payments
    WHERE external_reference = p_external_reference
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Payment attempt with external_reference % not found',
            p_external_reference;
    END IF;

    SELECT *
    INTO v_order
    FROM public.orders
    WHERE id = v_payment.order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', v_payment.order_id;
    END IF;

    IF v_order.client_id <> v_payment.client_id THEN
        RAISE EXCEPTION 'Order and payment client mismatch';
    END IF;

    IF p_payment_id IS NULL OR btrim(p_payment_id) = '' THEN
        RAISE EXCEPTION 'Payment ID is required';
    END IF;

    /*
     * Una misma external_reference no puede cambiar de payment_id.
     */
    IF v_payment.payment_id IS NOT NULL
       AND v_payment.payment_id <> p_payment_id THEN
        RAISE EXCEPTION
            'Payment attempt is already associated with a different payment ID';
    END IF;

    /*
     * El payment_id tampoco puede pertenecer a otro intento.
     */
    IF EXISTS (
        SELECT 1
        FROM public.order_payments
        WHERE payment_id = p_payment_id
          AND id <> v_payment.id
    ) THEN
        RAISE EXCEPTION
            'Payment ID % is used in another order or attempt',
            p_payment_id;
    END IF;

    /*
     * El monto confirmado por Mercado Pago debe coincidir tanto
     * con el intento como con el total autoritativo de la orden.
     */
    IF v_payment.amount <> p_amount
       OR v_order.total <> p_amount THEN

        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments
            SET status = 'error',
                status_detail = 'amount_mismatch',
                updated_at = now()
            WHERE id = v_payment.id;
        END IF;

        RETURN jsonb_build_object(
            'success', false,
            'error', 'amount_mismatch'
        );
    END IF;

    IF p_currency_id <> 'MXN' THEN
        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments
            SET status = 'error',
                status_detail = 'currency_mismatch',
                updated_at = now()
            WHERE id = v_payment.id;
        END IF;

        RETURN jsonb_build_object(
            'success', false,
            'error', 'currency_mismatch'
        );
    END IF;

    /*
     * La configuración solicitada por el webhook debe coincidir
     * con el ambiente almacenado cuando se creó el intento.
     */
    IF p_environment NOT IN ('test', 'production')
       OR p_environment <> v_payment.environment THEN

        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments
            SET status = 'error',
                status_detail = 'environment_mismatch',
                updated_at = now()
            WHERE id = v_payment.id;
        END IF;

        RETURN jsonb_build_object(
            'success', false,
            'error', 'environment_mismatch'
        );
    END IF;

    /*
     * Producción únicamente puede aceptar pagos live.
     */
    IF p_environment = 'production'
       AND p_live_mode IS DISTINCT FROM TRUE THEN

        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments
            SET status = 'error',
                status_detail = 'live_mode_mismatch',
                updated_at = now()
            WHERE id = v_payment.id;
        END IF;

        RETURN jsonb_build_object(
            'success', false,
            'error', 'live_mode_mismatch'
        );
    END IF;

    /*
     * TEST únicamente puede aceptar pagos no-live.
     */
    IF p_environment = 'test'
       AND p_live_mode IS DISTINCT FROM FALSE THEN

        IF v_payment.status <> 'approved' THEN
            UPDATE public.order_payments
            SET status = 'error',
                status_detail = 'live_mode_mismatch',
                updated_at = now()
            WHERE id = v_payment.id;
        END IF;

        RETURN jsonb_build_object(
            'success', false,
            'error', 'live_mode_mismatch'
        );
    END IF;

    /*
     * A partir de aquí existe una sola ruta autoritativa.
     *
     * Esta función realiza:
     * - reconciliación del pago;
     * - marcado del pago primario;
     * - actualización de orders;
     * - sales / sale_items;
     * - coupon_redemptions;
     * - apply_paid_order_post_payment();
     * - descuento de inventario;
     * - conversión del carrito;
     * - enqueue idempotente en order_fulfillment_jobs.
     *
     * configured_environment preserva la validación de ambiente
     * que requiere el conciliador autoritativo.
     */
    RETURN public.reconcile_mercado_pago_payment(
        p_payment_id              => p_payment_id,
        p_external_reference      => p_external_reference,
        p_status                  => p_status,
        p_status_detail           => p_status_detail,
        p_amount                  => p_amount,
        p_currency_id             => p_currency_id,
        p_payment_method_id       => p_payment_method_id,
        p_payment_type_id         => p_payment_type_id,
        p_installments            => p_installments,
        p_live_mode               => p_live_mode,
        p_date_approved           => p_date_approved,
        p_provider_created_at     => p_provider_created_at,
        p_provider_updated_at     => p_provider_updated_at,
        p_raw_metadata            => coalesce(p_raw_metadata, '{}'::jsonb)
            || jsonb_build_object(
                'configured_environment',
                p_environment
            )
    );
END;
$function$;
/*
 * SECURITY DEFINER:
 * no debe ser invocable directamente por usuarios del marketplace.
 */
REVOKE ALL ON FUNCTION public.reconcile_mp_web_order_payment(
    text,
    text,
    numeric,
    text,
    text,
    text,
    text,
    text,
    integer,
    boolean,
    timestamptz,
    timestamptz,
    timestamptz,
    text,
    jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_mp_web_order_payment(
    text,
    text,
    numeric,
    text,
    text,
    text,
    text,
    text,
    integer,
    boolean,
    timestamptz,
    timestamptz,
    timestamptz,
    text,
    jsonb
) TO service_role;
