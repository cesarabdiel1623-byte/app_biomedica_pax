-- ==============================================================================
-- Migración T3C: Condiciones Públicas Administrables en Cupones (public_terms)
-- ==============================================================================
-- 1. Agregar columna public_terms a public.coupons para almacenar condiciones
--    adicionales redactadas por administración (texto libre visible para el cliente).
-- 2. Recrear get_my_coupons() mediante DROP + CREATE para actualizar RETURNS TABLE
--    incorporando public_terms text de forma segura, sin exponer jamás internal_notes.
-- 3. Actualizar save_coupon_with_rules preservando su tipo de retorno histórico (jsonb)
--    y su contrato completo de metadata (uses_count, eligible_products), persistiendo
--    public_terms en INSERT y UPDATE con normalización trim/null.
-- ==============================================================================

-- 1. Columna public_terms en public.coupons
alter table public.coupons
  add column if not exists public_terms text null;

-- 2. Recrear get_my_coupons() para actualizar RETURNS TABLE
-- Se requiere DROP explícito (sin CASCADE) debido al cambio de columnas en RETURNS TABLE.
drop function if exists public.get_my_coupons();

create function public.get_my_coupons()
returns table (
  coupon_id uuid,
  code text,
  name text,
  public_description text,
  public_terms text,
  discount_type text,
  discount_value numeric,
  minimum_subtotal numeric,
  maximum_discount numeric,
  valid_from timestamp with time zone,
  valid_until timestamp with time zone,
  application_scope text,
  catalog_scope text,
  combinable_with_promotions boolean,
  distribution_scope text,
  usage_limit integer,
  client_usage_limit integer,
  client_uses bigint,
  remaining_uses bigint,
  coupon_state text
)
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_client_id uuid;
begin
  select profile.client_id into v_client_id
  from public.profiles profile
  where profile.id = auth.uid()
    and profile.client_id is not null
    and coalesce(profile.is_active, true)
    and lower(coalesce(profile.role::text, '')) in ('client', 'user', 'customer');

  if auth.uid() is null or v_client_id is null then
    raise exception using errcode = '42501', message = 'coupon_distribution:client_profile_required';
  end if;

  return query
  select
    coupon.id,
    coupon.code,
    coupon.name,
    coupon.public_description,
    coupon.public_terms,
    coupon.discount_type,
    coupon.discount_value,
    coupon.minimum_subtotal,
    coupon.max_discount_amount,
    coupon.starts_at,
    coupon.ends_at,
    coupon.application_scope,
    coupon.catalog_scope,
    coupon.combinable_with_promotions,
    coupon.distribution_scope,
    coupon.usage_limit_total,
    coupon.usage_limit_per_client,
    uses.client_uses,
    case
      when coupon.usage_limit_total is null and coupon.usage_limit_per_client is null then null
      when coupon.usage_limit_total is null then greatest(coupon.usage_limit_per_client::bigint - uses.client_uses, 0)
      when coupon.usage_limit_per_client is null then greatest(coupon.usage_limit_total::bigint - uses.global_uses, 0)
      else least(
        greatest(coupon.usage_limit_total::bigint - uses.global_uses, 0),
        greatest(coupon.usage_limit_per_client::bigint - uses.client_uses, 0)
      )
    end as remaining_uses,
    case
      when coupon.starts_at is not null and now() < coupon.starts_at then 'not_started'
      when coupon.ends_at is not null and now() > coupon.ends_at then 'expired'
      when coupon.usage_limit_total is not null and uses.global_uses >= coupon.usage_limit_total then 'limit_reached'
      when coupon.usage_limit_per_client is not null and uses.client_uses >= coupon.usage_limit_per_client then 'used'
      else 'available'
    end as coupon_state
  from public.coupons coupon
  cross join lateral (
    select
      count(*) filter (where redemption.client_id = v_client_id)::bigint as client_uses,
      count(*)::bigint as global_uses
    from public.coupon_redemptions redemption
    where redemption.coupon_id = coupon.id
  ) uses
  where coupon.status = 'active'
    and coupon.channel in ('mobile', 'all')
    and public.coupon_is_available_to_client(coupon.id, v_client_id)
  order by
    case
      when coupon.starts_at is not null and now() < coupon.starts_at then 2
      when coupon.ends_at is not null and now() > coupon.ends_at then 3
      when coupon.usage_limit_total is not null and uses.global_uses >= coupon.usage_limit_total then 4
      when coupon.usage_limit_per_client is not null and uses.client_uses >= coupon.usage_limit_per_client then 4
      else 1
    end,
    coupon.ends_at asc nulls last,
    coupon.created_at desc;
end
$$;

revoke all on function public.get_my_coupons() from public, anon;
grant execute on function public.get_my_coupons() to authenticated, service_role;

-- 3. Actualizar función RPC save_coupon_with_rules preservando RETURNS jsonb y metadata
create or replace function public.save_coupon_with_rules(
  p_coupon jsonb,
  p_category_rules jsonb default '[]'::jsonb,
  p_subcategory_rules jsonb default '[]'::jsonb,
  p_product_rules jsonb default '[]'::jsonb,
  p_coupon_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_input public.coupons%rowtype;
  v_existing public.coupons%rowtype;
  v_saved public.coupons%rowtype;
  v_category_rules jsonb := coalesce(p_category_rules, '[]'::jsonb);
  v_subcategory_rules jsonb := coalesce(p_subcategory_rules, '[]'::jsonb);
  v_product_rules jsonb := coalesce(p_product_rules, '[]'::jsonb);
  v_eligible_count integer := 0;
  v_uses_count integer := 0;
begin
  if auth.uid() is null
    or not (public.is_admin_user() or public.is_staff_or_admin()) then
    raise exception using errcode = '42501', message = 'Acceso no autorizado.';
  end if;

  if p_coupon is null or jsonb_typeof(p_coupon) <> 'object' then
    raise exception using errcode = '22023', message = 'coupon_payload_invalid';
  end if;

  perform public.coupon_assert_rule_array(v_category_rules, 'category');
  perform public.coupon_assert_rule_array(v_subcategory_rules, 'subcategory');
  perform public.coupon_assert_rule_array(v_product_rules, 'product');

  v_input := jsonb_populate_record(
    null::public.coupons,
    p_coupon - array[
      'id', 'created_by', 'updated_by', 'created_at', 'updated_at',
      'catalog_review_required', 'catalog_rules_version', 'uses_count',
      'coupon_redemptions'
    ]
  );

  v_input.code := upper(btrim(coalesce(v_input.code, '')));
  v_input.name := btrim(coalesce(v_input.name, ''));
  v_input.status := coalesce(v_input.status, 'draft');
  v_input.minimum_subtotal := coalesce(v_input.minimum_subtotal, 0);
  v_input.first_purchase_only := coalesce(v_input.first_purchase_only, false);
  v_input.channel := coalesce(v_input.channel, 'all');
  v_input.application_scope := coalesce(v_input.application_scope, 'purchase');
  v_input.combinable_with_promotions := coalesce(v_input.combinable_with_promotions, false);
  v_input.catalog_scope := coalesce(v_input.catalog_scope, 'all');

  if v_input.code !~ '^[A-Z0-9][A-Z0-9_-]{2,39}$' then
    raise exception using errcode = '22023', message = 'coupon_validation:code';
  end if;
  if length(v_input.name) < 1 or length(v_input.name) > 120 then
    raise exception using errcode = '22023', message = 'coupon_validation:name';
  end if;
  if length(coalesce(v_input.public_description, '')) > 300
    or length(coalesce(v_input.public_terms, '')) > 1000
    or length(coalesce(v_input.internal_notes, '')) > 1000 then
    raise exception using errcode = '22023', message = 'coupon_validation:text_length';
  end if;
  if v_input.status not in ('draft', 'active', 'paused', 'archived') then
    raise exception using errcode = '22023', message = 'coupon_validation:status';
  end if;
  if v_input.discount_type is null
    or v_input.discount_value is null
    or v_input.discount_type not in ('percentage', 'fixed_amount', 'free_shipping')
    or (v_input.discount_type = 'percentage' and (v_input.discount_value <= 0 or v_input.discount_value > 100))
    or (v_input.discount_type = 'fixed_amount' and v_input.discount_value <= 0)
    or (v_input.discount_type = 'free_shipping' and v_input.discount_value <> 0) then
    raise exception using errcode = '22023', message = 'coupon_validation:discount';
  end if;
  if v_input.minimum_subtotal is null or v_input.minimum_subtotal < 0 then
    raise exception using errcode = '22023', message = 'coupon_validation:minimum_subtotal';
  end if;
  if v_input.discount_type = 'percentage' and v_input.max_discount_amount is not null and v_input.max_discount_amount <= 0 then
    raise exception using errcode = '22023', message = 'coupon_validation:max_discount';
  end if;
  if v_input.starts_at is not null and v_input.ends_at is not null and v_input.ends_at <= v_input.starts_at then
    raise exception using errcode = '22023', message = 'coupon_validation:dates';
  end if;
  if (v_input.usage_limit_total is not null and v_input.usage_limit_total <= 0)
    or (v_input.usage_limit_per_client is not null and v_input.usage_limit_per_client <= 0)
    or (
      v_input.usage_limit_total is not null
      and v_input.usage_limit_per_client is not null
      and v_input.usage_limit_per_client > v_input.usage_limit_total
    ) then
    raise exception using errcode = '22023', message = 'coupon_validation:limits';
  end if;
  if v_input.channel not in ('mobile', 'web', 'all')
    or v_input.application_scope not in ('purchase', 'quote', 'both')
    or v_input.catalog_scope not in ('all', 'restricted') then
    raise exception using errcode = '22023', message = 'coupon_validation:scope';
  end if;
  if v_input.status = 'active' and v_input.ends_at is not null and v_input.ends_at <= now() then
    raise exception using errcode = '22023', message = 'coupon_validation:expired';
  end if;

  if p_coupon_id is not null then
    select * into v_existing
    from public.coupons c
    where c.id = p_coupon_id
    for update;

    if not found then
      raise exception using errcode = 'P0002', message = 'coupon_not_found';
    end if;

    if v_existing.status <> v_input.status and not (
      (v_existing.status = 'draft' and v_input.status in ('active', 'archived'))
      or (v_existing.status = 'active' and v_input.status in ('paused', 'archived'))
      or (v_existing.status = 'paused' and v_input.status in ('active', 'archived'))
    ) then
      raise exception using errcode = '22023', message = 'coupon_validation:status_transition';
    end if;

    update public.coupons
    set code = v_input.code,
        name = v_input.name,
        public_description = nullif(btrim(coalesce(v_input.public_description, '')), ''),
        public_terms = nullif(btrim(coalesce(v_input.public_terms, '')), ''),
        internal_notes = nullif(btrim(coalesce(v_input.internal_notes, '')), ''),
        status = v_input.status,
        discount_type = v_input.discount_type,
        discount_value = v_input.discount_value,
        max_discount_amount = v_input.max_discount_amount,
        minimum_subtotal = v_input.minimum_subtotal,
        starts_at = v_input.starts_at,
        ends_at = v_input.ends_at,
        usage_limit_total = v_input.usage_limit_total,
        usage_limit_per_client = v_input.usage_limit_per_client,
        first_purchase_only = v_input.first_purchase_only,
        channel = v_input.channel,
        application_scope = v_input.application_scope,
        combinable_with_promotions = v_input.combinable_with_promotions,
        catalog_scope = v_input.catalog_scope,
        catalog_review_required = false,
        catalog_rules_version = 2,
        updated_by = auth.uid(),
        updated_at = now()
    where id = p_coupon_id
    returning * into v_saved;
  else
    insert into public.coupons (
      code, name, public_description, public_terms, internal_notes, status, discount_type,
      discount_value, max_discount_amount, minimum_subtotal, starts_at, ends_at,
      usage_limit_total, usage_limit_per_client, first_purchase_only, channel,
      application_scope, combinable_with_promotions, catalog_scope,
      catalog_review_required, catalog_rules_version, created_by, updated_by
    ) values (
      v_input.code,
      v_input.name,
      nullif(btrim(coalesce(v_input.public_description, '')), ''),
      nullif(btrim(coalesce(v_input.public_terms, '')), ''),
      nullif(btrim(coalesce(v_input.internal_notes, '')), ''),
      v_input.status,
      v_input.discount_type,
      v_input.discount_value,
      v_input.max_discount_amount,
      v_input.minimum_subtotal,
      v_input.starts_at,
      v_input.ends_at,
      v_input.usage_limit_total,
      v_input.usage_limit_per_client,
      v_input.first_purchase_only,
      v_input.channel,
      v_input.application_scope,
      v_input.combinable_with_promotions,
      v_input.catalog_scope,
      false,
      2,
      auth.uid(),
      auth.uid()
    ) returning * into v_saved;
  end if;

  delete from public.coupon_products where coupon_id = v_saved.id;
  delete from public.coupon_subcategories where coupon_id = v_saved.id;
  delete from public.coupon_categories where coupon_id = v_saved.id;

  insert into public.coupon_categories (coupon_id, category_id, rule_type)
  select v_saved.id, (e->>'entity_id')::uuid, e->>'action'
  from jsonb_array_elements(v_category_rules) e;

  insert into public.coupon_subcategories (coupon_id, subcategory_id, rule_type)
  select v_saved.id, (e->>'entity_id')::uuid, e->>'action'
  from jsonb_array_elements(v_subcategory_rules) e;

  insert into public.coupon_products (coupon_id, product_id, rule_type)
  select v_saved.id, (e->>'entity_id')::uuid, e->>'action'
  from jsonb_array_elements(v_product_rules) e;

  select count(*)::integer into v_eligible_count
  from public.products p
  cross join lateral public.is_product_eligible_for_coupon(v_saved.id, p.id) evaluation
  where p.is_active is true
    and evaluation.eligible;

  if v_saved.catalog_scope = 'restricted'
    and v_saved.status = 'active'
    and v_eligible_count = 0 then
    raise exception using
      errcode = '22023',
      message = 'coupon_specific_requires_inclusion';
  end if;

  update public.coupons
  set catalog_review_required = false,
      catalog_rules_version = 2,
      updated_at = now()
  where id = v_saved.id
  returning * into v_saved;

  select count(*)::integer into v_uses_count
  from public.coupon_redemptions r
  where r.coupon_id = v_saved.id;

  return to_jsonb(v_saved)
    || jsonb_build_object(
      'uses_count', v_uses_count,
      'eligible_products', v_eligible_count
    );
end;
$$;

revoke all on function public.save_coupon_with_rules(jsonb, jsonb, jsonb, jsonb, uuid) from public, anon;
grant execute on function public.save_coupon_with_rules(jsonb, jsonb, jsonb, jsonb, uuid) to authenticated, service_role;
