-- Migration: T2.8 fix order totals with included VAT and customer shipping
-- Archivo local preparado para revisión. NO ejecutar db push.

CREATE OR REPLACE FUNCTION public.recalculate_order_totals(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
  v_order record;
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

  SELECT COALESCE(
    ROUND(
      SUM(
        ROUND(
          GREATEST(
            COALESCE(
              oi.total_line_price,
              COALESCE(oi.unit_price, 0) * COALESCE(oi.quantity, 0),
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

  -- subtotal conserva la suma efectiva de order_items antes del cupón de orden.
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

  -- Los precios de producto ya incluyen IVA. tax es informativo y no se suma al total.
  v_total := ROUND(GREATEST(v_product_payable + v_customer_shipping_amount, 0), 2);

  UPDATE public.orders
  SET subtotal = v_items_subtotal,
      tax = v_tax,
      total = v_total,
      updated_at = now()
  WHERE id = p_order_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.after_order_items_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.order_id IS DISTINCT FROM NEW.order_id THEN
      PERFORM public.recalculate_order_totals(OLD.order_id);
    END IF;
    PERFORM public.recalculate_order_totals(NEW.order_id);
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    PERFORM public.recalculate_order_totals(OLD.order_id);
    RETURN OLD;
  END IF;

  PERFORM public.recalculate_order_totals(NEW.order_id);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_order_items_recalculate ON public.order_items;
CREATE TRIGGER trg_order_items_recalculate
AFTER INSERT OR UPDATE OR DELETE ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.after_order_items_change();
REVOKE EXECUTE ON FUNCTION public.recalculate_order_totals(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.recalculate_order_totals(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.recalculate_order_totals(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.recalculate_order_totals(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.after_order_items_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.after_order_items_change() FROM anon;
REVOKE EXECUTE ON FUNCTION public.after_order_items_change() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.after_order_items_change() TO service_role;
CREATE OR REPLACE FUNCTION public.coupon_calculate_cart_pricing(
  p_cart_id uuid,
  p_code text DEFAULT NULL::text,
  p_enforce_owner boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_cart public.carts%rowtype;
  v_coupon public.coupons%rowtype;
  v_client_id uuid;
  v_code text := nullif(upper(btrim(coalesce(p_code, ''))), '');
  v_item record;
  v_base_unit numeric;
  v_effective_unit numeric;
  v_line_base numeric;
  v_line_effective numeric;
  v_items_subtotal numeric := 0;
  v_product_discount numeric := 0;
  v_eligible_subtotal numeric := 0;
  v_coupon_discount numeric := 0;
  v_shipping_before numeric := 0;
  v_shipping_discount numeric := 0;
  v_payable_product_amount numeric := 0;
  v_tax numeric := 0;
  v_total numeric := 0;
  v_has_items boolean := false;
  v_has_eligible_promotion boolean := false;
  v_included boolean;
  v_excluded boolean;
  v_global_uses integer;
  v_client_uses integer;
  v_channel text;
  v_reason text := 'applied';
  v_message text := 'Cupón aplicado';
begin
  select c.* into v_cart
  from public.carts c
  where c.id = p_cart_id;

  if not found or (p_enforce_owner and v_cart.status::text <> 'active') then
    return jsonb_build_object('valid', false, 'reason', 'invalid_cart', 'message', 'No fue posible validar el carrito.');
  end if;

  select p.client_id into v_client_id
  from public.profiles p
  where p.id = auth.uid();

  if p_enforce_owner and (
    auth.uid() is null
    or v_client_id is null
    or v_cart.client_id is distinct from v_client_id
  ) then
    return jsonb_build_object('valid', false, 'reason', 'invalid_cart', 'message', 'No fue posible validar el carrito.');
  end if;

  if v_code is not null then
    select c.* into v_coupon
    from public.coupons c
    where upper(c.code) = v_code;

    if not found then
      return jsonb_build_object('valid', false, 'reason', 'not_found', 'message', 'El cupón no es válido.');
    end if;
  end if;

  for v_item in
    select
      ci.product_id,
      greatest(ci.quantity, 0) as quantity,
      p.unit_price_mxn,
      p.category_id,
      p.subcategory_id
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = p_cart_id
      and p.is_active = true
  loop
    v_has_items := true;
    v_base_unit := greatest(coalesce(v_item.unit_price_mxn, 0), 0);
    v_effective_unit := v_base_unit;

    select least(
      v_effective_unit,
      case pp.discount_type::text
        when 'percentage' then greatest(0, v_base_unit * (1 - pp.discount_value / 100))
        when 'fixed_amount' then greatest(0, v_base_unit - pp.discount_value)
        when 'promotional_price' then greatest(0, pp.discount_value)
        else v_base_unit
      end
    )
    into v_effective_unit
    from public.product_promotions pp
    where pp.product_id = v_item.product_id
      and coalesce(pp.is_enabled, true)
      and pp.status::text in ('active', 'enabled', 'published')
      and (pp.starts_at is null or pp.starts_at <= now())
      and (pp.ends_at is null or pp.ends_at >= now())
    order by
      case pp.discount_type::text
        when 'percentage' then greatest(0, v_base_unit * (1 - pp.discount_value / 100))
        when 'fixed_amount' then greatest(0, v_base_unit - pp.discount_value)
        when 'promotional_price' then greatest(0, pp.discount_value)
        else v_base_unit
      end
    limit 1;

    v_effective_unit := coalesce(v_effective_unit, v_base_unit);
    v_line_base := round(v_base_unit * v_item.quantity, 2);
    v_line_effective := round(v_effective_unit * v_item.quantity, 2);
    v_items_subtotal := v_items_subtotal + v_line_base;
    v_product_discount := v_product_discount + greatest(0, v_line_base - v_line_effective);

    if v_code is not null then
      v_included := v_coupon.catalog_scope = 'all'
        or exists (
          select 1 from public.coupon_products cp
          where cp.coupon_id = v_coupon.id and cp.product_id = v_item.product_id and cp.rule_type = 'include'
        )
        or exists (
          select 1 from public.coupon_categories cc
          where cc.coupon_id = v_coupon.id and cc.category_id = v_item.category_id and cc.rule_type = 'include'
        )
        or exists (
          select 1 from public.coupon_subcategories cs
          where cs.coupon_id = v_coupon.id and cs.subcategory_id = v_item.subcategory_id and cs.rule_type = 'include'
        );
      v_excluded := exists (
          select 1 from public.coupon_products cp
          where cp.coupon_id = v_coupon.id and cp.product_id = v_item.product_id and cp.rule_type = 'exclude'
        )
        or exists (
          select 1 from public.coupon_categories cc
          where cc.coupon_id = v_coupon.id and cc.category_id = v_item.category_id and cc.rule_type = 'exclude'
        )
        or exists (
          select 1 from public.coupon_subcategories cs
          where cs.coupon_id = v_coupon.id and cs.subcategory_id = v_item.subcategory_id and cs.rule_type = 'exclude'
        );
      if v_included and not v_excluded then
        v_eligible_subtotal := v_eligible_subtotal + v_line_effective;
        v_has_eligible_promotion := v_has_eligible_promotion or v_line_effective < v_line_base;
      end if;
    end if;
  end loop;

  if not v_has_items then
    return jsonb_build_object('valid', false, 'reason', 'invalid_cart', 'message', 'No fue posible validar el carrito.');
  end if;

  if v_code is null then
    v_payable_product_amount := greatest(0, v_items_subtotal - v_product_discount);
    v_tax := case
      when v_cart.tax_exempt then 0
      else round(v_payable_product_amount - (v_payable_product_amount / (1 + coalesce(v_cart.tax_pct, 0.16))), 2)
    end;
    v_total := round(v_payable_product_amount + v_shipping_before, 2);

    return jsonb_build_object(
      'valid', true, 'reason', 'no_coupon', 'message', 'Carrito calculado',
      'coupon', null,
      'amounts', jsonb_build_object(
        'items_subtotal', round(v_items_subtotal, 2),
        'product_discount', round(v_product_discount, 2),
        'coupon_discount', 0,
        'shipping_before_discount', round(v_shipping_before, 2),
        'shipping_discount', 0,
        'tax', round(v_tax, 2),
        'total', round(v_total, 2),
        'currency', 'MXN'
      )
    );
  end if;

  if v_coupon.status <> 'active' then
    v_reason := 'inactive'; v_message := 'El cupón no está disponible.';
  elsif v_coupon.starts_at is not null and now() < v_coupon.starts_at then
    v_reason := 'not_started'; v_message := 'El cupón todavía no está vigente.';
  elsif v_coupon.ends_at is not null and now() > v_coupon.ends_at then
    v_reason := 'expired'; v_message := 'El cupón ha vencido.';
  else
    v_channel := case when coalesce(v_cart.source, 'mobile_app') = 'mobile_app' then 'mobile' else 'web' end;
    if v_coupon.channel <> 'all' and v_coupon.channel <> v_channel then
      v_reason := 'not_applicable'; v_message := 'El cupón no aplica en este canal.';
    elsif v_coupon.application_scope not in ('purchase', 'both') then
      v_reason := 'not_applicable'; v_message := 'El cupón no aplica a compras.';
    elsif v_eligible_subtotal <= 0 then
      v_reason := 'not_applicable'; v_message := 'El cupón no aplica a los productos del carrito.';
    elsif v_eligible_subtotal < v_coupon.minimum_subtotal then
      v_reason := 'minimum_not_met'; v_message := 'El carrito no alcanza el subtotal mínimo.';
    elsif not v_coupon.combinable_with_promotions and v_has_eligible_promotion then
      v_reason := 'not_combinable'; v_message := 'El cupón no es acumulable con promociones activas.';
    else
      select count(*)::integer into v_global_uses
      from public.coupon_redemptions cr where cr.coupon_id = v_coupon.id;
      select count(*)::integer into v_client_uses
      from public.coupon_redemptions cr
      where cr.coupon_id = v_coupon.id and cr.client_id = v_cart.client_id;

      if v_coupon.usage_limit_total is not null and v_global_uses >= v_coupon.usage_limit_total then
        v_reason := 'usage_limit_reached'; v_message := 'El cupón alcanzó su límite de usos.';
      elsif v_coupon.usage_limit_per_client is not null and v_client_uses >= v_coupon.usage_limit_per_client then
        v_reason := 'client_limit_reached'; v_message := 'Ya utilizaste este cupón.';
      elsif v_coupon.first_purchase_only and exists (
        select 1 from public.orders o
        where o.client_id = v_cart.client_id
          and o.id is distinct from v_cart.converted_order_id
          and o.status::text not in ('cancelled', 'canceled', 'refunded')
      ) then
        v_reason := 'first_purchase_required'; v_message := 'El cupón es exclusivo para la primera compra.';
      end if;
    end if;
  end if;

  if v_reason <> 'applied' then
    return jsonb_build_object('valid', false, 'reason', v_reason, 'message', v_message);
  end if;

  if v_coupon.discount_type = 'percentage' then
    v_coupon_discount := round(v_eligible_subtotal * v_coupon.discount_value / 100, 2);
    if v_coupon.max_discount_amount is not null then
      v_coupon_discount := least(v_coupon_discount, v_coupon.max_discount_amount);
    end if;
  elsif v_coupon.discount_type = 'fixed_amount' then
    v_coupon_discount := least(v_coupon.discount_value, v_eligible_subtotal);
  elsif v_coupon.discount_type = 'free_shipping' then
    v_shipping_discount := v_shipping_before;
  end if;

  v_payable_product_amount := greatest(0, v_items_subtotal - v_product_discount - v_coupon_discount);
  v_tax := case
    when v_cart.tax_exempt then 0
    else round(v_payable_product_amount - (v_payable_product_amount / (1 + coalesce(v_cart.tax_pct, 0.16))), 2)
  end;

  v_total := round(greatest(
    0,
    v_payable_product_amount + v_shipping_before - v_shipping_discount
  ), 2);

  return jsonb_build_object(
    'valid', true, 'reason', 'applied', 'message', 'Cupón aplicado',
    'coupon', jsonb_build_object(
      'id', v_coupon.id,
      'code', v_coupon.code,
      'name', v_coupon.name,
      'discount_type', v_coupon.discount_type,
      'discount_value', v_coupon.discount_value
    ),
    'amounts', jsonb_build_object(
      'items_subtotal', round(v_items_subtotal, 2),
      'product_discount', round(v_product_discount, 2),
      'coupon_discount', round(v_coupon_discount, 2),
      'shipping_before_discount', round(v_shipping_before, 2),
      'shipping_discount', round(v_shipping_discount, 2),
      'tax', round(v_tax, 2),
      'total', round(v_total, 2),
      'currency', 'MXN'
    )
  );
end
$function$;
REVOKE EXECUTE ON FUNCTION public.coupon_calculate_cart_pricing(uuid, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.coupon_calculate_cart_pricing(uuid, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.coupon_calculate_cart_pricing(uuid, text, boolean) TO service_role;
