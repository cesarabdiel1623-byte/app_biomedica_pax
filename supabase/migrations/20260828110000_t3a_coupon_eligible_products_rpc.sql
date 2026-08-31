-- Migration: T3A.1 — Backend autoritativo para consulta de productos participantes de cupones
-- Timestamp: 20260828110000
-- Arquitectura: Retorna JSONB con { "product_ids": ["uuid", ...], "total_count": 12, "is_full_catalog": false }
-- para que el cliente móvil consuma ProductService.getProductsByIds sin exponer tablas internas.

CREATE OR REPLACE FUNCTION public.get_coupon_eligible_product_ids(
  p_coupon_id uuid,
  p_search text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_user_id uuid;
  v_client_id uuid;
  v_coupon public.coupons%rowtype;
  v_search text;
  v_limit integer;
  v_offset integer;
  v_is_available boolean := false;
  v_is_full_catalog boolean := false;
  v_global_uses integer := 0;
  v_client_uses integer := 0;
  v_total_count bigint := 0;
  v_product_ids jsonb := '[]'::jsonb;
begin
  -- 1. Validar parámetros de entrada
  if p_coupon_id is null then
    return jsonb_build_object(
      'product_ids', '[]'::jsonb,
      'total_count', 0,
      'is_full_catalog', false
    );
  end if;

  v_limit := greatest(1, least(coalesce(p_limit, 20), 50));
  v_offset := greatest(0, coalesce(p_offset, 0));
  v_search := nullif(btrim(coalesce(p_search, '')), '');

  -- 2. Autenticación y resolución segura de cliente
  v_user_id := auth.uid();
  if v_user_id is null then
    return jsonb_build_object(
      'product_ids', '[]'::jsonb,
      'total_count', 0,
      'is_full_catalog', false
    );
  end if;

  select p.client_id into v_client_id
  from public.profiles p
  where p.id = v_user_id;

  if v_client_id is null then
    return jsonb_build_object(
      'product_ids', '[]'::jsonb,
      'total_count', 0,
      'is_full_catalog', false
    );
  end if;

  -- 3. Cargar cupón y validar estado / vigencia / canal / application_scope
  select c.* into v_coupon
  from public.coupons c
  where c.id = p_coupon_id;

  if not found then
    return jsonb_build_object(
      'product_ids', '[]'::jsonb,
      'total_count', 0,
      'is_full_catalog', false
    );
  end if;

  -- Validaciones explícitas de cupón (Fail-Closed)
  if v_coupon.status is null or v_coupon.status != 'active' then
    return jsonb_build_object('product_ids', '[]'::jsonb, 'total_count', 0, 'is_full_catalog', false);
  end if;

  if v_coupon.channel is null or v_coupon.channel not in ('mobile', 'all') then
    return jsonb_build_object('product_ids', '[]'::jsonb, 'total_count', 0, 'is_full_catalog', false);
  end if;

  if v_coupon.application_scope is null or v_coupon.application_scope not in ('purchase', 'both') then
    return jsonb_build_object('product_ids', '[]'::jsonb, 'total_count', 0, 'is_full_catalog', false);
  end if;

  if (v_coupon.starts_at is not null and now() < v_coupon.starts_at)
     or (v_coupon.ends_at is not null and now() > v_coupon.ends_at) then
    return jsonb_build_object('product_ids', '[]'::jsonb, 'total_count', 0, 'is_full_catalog', false);
  end if;

  -- 4. Privacidad y autorización: Fail-Closed
  begin
    v_is_available := public.coupon_is_available_to_client(
      p_coupon_id := p_coupon_id,
      p_client_id := v_client_id
    );
  exception when others then
    v_is_available := false;
  end;

  if v_is_available is distinct from true then
    return jsonb_build_object(
      'product_ids', '[]'::jsonb,
      'total_count', 0,
      'is_full_catalog', false
    );
  end if;

  -- 4.1 Validación autoritativa de límites de uso (Global y por Cliente)
  if v_coupon.usage_limit_total is not null then
    select count(*)::integer into v_global_uses
    from public.coupon_redemptions cr
    where cr.coupon_id = p_coupon_id;

    if v_global_uses >= v_coupon.usage_limit_total then
      return jsonb_build_object(
        'product_ids', '[]'::jsonb,
        'total_count', 0,
        'is_full_catalog', false
      );
    end if;
  end if;

  if v_coupon.usage_limit_per_client is not null then
    select count(*)::integer into v_client_uses
    from public.coupon_redemptions cr
    where cr.coupon_id = p_coupon_id and cr.client_id = v_client_id;

    if v_client_uses >= v_coupon.usage_limit_per_client then
      return jsonb_build_object(
        'product_ids', '[]'::jsonb,
        'total_count', 0,
        'is_full_catalog', false
      );
    end if;
  end if;

  -- 5. Determinar si es full catalog (catalog_scope = 'all' SIN exclusiones configuradas)
  if v_coupon.catalog_scope = 'all' then
    v_is_full_catalog := not exists (
      select 1 from public.coupon_products cp
      where cp.coupon_id = p_coupon_id and cp.rule_type = 'exclude'
    ) and not exists (
      select 1 from public.coupon_categories cc
      where cc.coupon_id = p_coupon_id and cc.rule_type = 'exclude'
    ) and not exists (
      select 1 from public.coupon_subcategories cs
      where cs.coupon_id = p_coupon_id and cs.rule_type = 'exclude'
    );
  else
    v_is_full_catalog := false;
  end if;

  -- 6. Calcular total_count (antes de limit y offset)
  with eligible_products as (
    select
      p.id as prod_id,
      p.name as prod_name
    from public.products p
    where p.is_active = true
      -- Inclusión
      and (
        v_coupon.catalog_scope = 'all'
        or exists (
          select 1 from public.coupon_products cp
          where cp.coupon_id = p_coupon_id and cp.product_id = p.id and cp.rule_type = 'include'
        )
        or (
          p.category_id is not null and exists (
            select 1 from public.coupon_categories cc
            where cc.coupon_id = p_coupon_id and cc.category_id = p.category_id and cc.rule_type = 'include'
          )
        )
        or (
          p.subcategory_id is not null and exists (
            select 1 from public.coupon_subcategories cs
            where cs.coupon_id = p_coupon_id and cs.subcategory_id = p.subcategory_id and cs.rule_type = 'include'
          )
        )
      )
      -- Exclusión (Precedencia absoluta: EXCLUDE siempre gana)
      and not exists (
        select 1 from public.coupon_products cp
        where cp.coupon_id = p_coupon_id and cp.product_id = p.id and cp.rule_type = 'exclude'
      )
      and not (
        p.category_id is not null and exists (
          select 1 from public.coupon_categories cc
          where cc.coupon_id = p_coupon_id and cc.category_id = p.category_id and cc.rule_type = 'exclude'
        )
      )
      and not (
        p.subcategory_id is not null and exists (
          select 1 from public.coupon_subcategories cs
          where cs.coupon_id = p_coupon_id and cs.subcategory_id = p.subcategory_id and cs.rule_type = 'exclude'
        )
      )
      -- Búsqueda textual server-side
      and (
        v_search is null
        or p.name ilike ('%' || v_search || '%')
        or p.sku ilike ('%' || v_search || '%')
      )
  )
  select count(*) into v_total_count from eligible_products;

  -- 7. Obtener IDs paginados en formato JSON
  with eligible_products as (
    select
      p.id as prod_id,
      p.name as prod_name
    from public.products p
    where p.is_active = true
      -- Inclusión
      and (
        v_coupon.catalog_scope = 'all'
        or exists (
          select 1 from public.coupon_products cp
          where cp.coupon_id = p_coupon_id and cp.product_id = p.id and cp.rule_type = 'include'
        )
        or (
          p.category_id is not null and exists (
            select 1 from public.coupon_categories cc
            where cc.coupon_id = p_coupon_id and cc.category_id = p.category_id and cc.rule_type = 'include'
          )
        )
        or (
          p.subcategory_id is not null and exists (
            select 1 from public.coupon_subcategories cs
            where cs.coupon_id = p_coupon_id and cs.subcategory_id = p.subcategory_id and cs.rule_type = 'include'
          )
        )
      )
      -- Exclusión (Precedencia absoluta: EXCLUDE siempre gana)
      and not exists (
        select 1 from public.coupon_products cp
        where cp.coupon_id = p_coupon_id and cp.product_id = p.id and cp.rule_type = 'exclude'
      )
      and not (
        p.category_id is not null and exists (
          select 1 from public.coupon_categories cc
          where cc.coupon_id = p_coupon_id and cc.category_id = p.category_id and cc.rule_type = 'exclude'
        )
      )
      and not (
        p.subcategory_id is not null and exists (
          select 1 from public.coupon_subcategories cs
          where cs.coupon_id = p_coupon_id and cs.subcategory_id = p.subcategory_id and cs.rule_type = 'exclude'
        )
      )
      -- Búsqueda textual server-side
      and (
        v_search is null
        or p.name ilike ('%' || v_search || '%')
        or p.sku ilike ('%' || v_search || '%')
      )
    order by prod_name asc, prod_id asc
    limit v_limit
    offset v_offset
  )
  select coalesce(jsonb_agg(prod_id::text order by prod_name asc, prod_id asc), '[]'::jsonb)
  into v_product_ids
  from eligible_products;

  return jsonb_build_object(
    'product_ids', coalesce(v_product_ids, '[]'::jsonb),
    'total_count', v_total_count,
    'is_full_catalog', v_is_full_catalog
  );
end;
$function$;

-- Privilegios de ejecución
REVOKE ALL ON FUNCTION public.get_coupon_eligible_product_ids(uuid, text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_coupon_eligible_product_ids(uuid, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_coupon_eligible_product_ids(uuid, text, integer, integer) TO service_role;
