-- T6.1: allow the mobile service form to persist diagnostic requests.
-- Local-only migration; do not run without review against the target schema.

DO $$
DECLARE
  v_type_oid oid;
  v_type_name text;
BEGIN
  SELECT a.atttypid, a.atttypid::regtype::text
    INTO v_type_oid, v_type_name
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'service_tickets'
    AND a.attname = 'type'
    AND NOT a.attisdropped;

  IF v_type_oid IS NULL THEN
    RAISE NOTICE 'public.service_tickets.type was not found; diagnostico enum value was not added.';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    WHERE t.oid = v_type_oid
      AND t.typtype = 'e'
  ) THEN
    RAISE NOTICE 'public.service_tickets.type (%) is not an enum; diagnostico enum value was not added.', v_type_name;
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    WHERE e.enumtypid = v_type_oid
      AND e.enumlabel = 'diagnostico'
  ) THEN
    EXECUTE format('ALTER TYPE %s ADD VALUE %L', v_type_name, 'diagnostico');
  END IF;
END $$;
