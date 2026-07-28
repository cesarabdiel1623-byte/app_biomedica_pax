-- Auditoria de solo lectura para revisar capas de seguridad en Supabase.
-- Este archivo no modifica datos ni schema.
-- Ejecutar por secciones en SQL Editor o con psql.

-- 1) Tablas del schema public y estado de RLS
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'r'
  and n.nspname = 'public'
order by c.relname;

-- 2) Policies desplegadas por tabla
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname in ('public', 'storage')
order by schemaname, tablename, policyname;

-- 3) Grants directos sobre tablas public
select
  table_schema,
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type;

-- 4) Grants sobre columnas para detectar exposicion parcial
select
  table_schema,
  table_name,
  column_name,
  grantee,
  privilege_type
from information_schema.column_privileges
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, column_name, grantee;

-- 5) Vistas del schema public
select
  table_schema,
  table_name,
  view_definition
from information_schema.views
where table_schema = 'public'
order by table_name;

-- 6) Funciones expuestas en public y su modo de seguridad
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args,
  p.prosecdef as security_definer,
  p.provolatile as volatility
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;

-- 7) Permisos EXECUTE sobre funciones public
select
  routine_schema,
  routine_name,
  grantee,
  privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
order by routine_name, grantee;

-- 8) Buckets de Storage
select
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types,
  created_at,
  updated_at
from storage.buckets
order by name;

-- 9) Policies de storage.objects
  select
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
  order by policyname;

-- 10) Conteo rapido por bucket para ubicar superficies activas
select
  bucket_id,
  count(*) as object_count
from storage.objects
group by bucket_id
order by bucket_id;

-- 11) Tablas especialmente sensibles para revisar primero
select
  schemaname,
  tablename,
  policyname,
  roles,
  cmd
from pg_policies
where schemaname = 'public'
  and tablename in (
    'products',
    'product_reviews',
    'product_questions',
    'profiles',
    'clients',
    'client_addresses',
    'client_favorites',
    'carts',
    'cart_items',
    'quotes',
    'quote_items',
    'quote_requests',
    'quote_request_items',
    'orders',
    'order_items',
    'service_tickets',
    'service_ticket_messages',
    'notifications',
    'equipment_units'
  )
order by tablename, policyname;
