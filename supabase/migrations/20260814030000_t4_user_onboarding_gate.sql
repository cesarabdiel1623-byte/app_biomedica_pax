-- ==============================================================================
-- Migración: 20260814030000_t4_user_onboarding_gate.sql
-- Objetivo: Onboarding Gate autoritativo y blindaje de columnas sensibles
-- ==============================================================================

-- 1. Nuevas columnas en public.clients para términos y estado de teléfono
ALTER TABLE public.clients 
ADD COLUMN IF NOT EXISTS terms_accepted_at timestamptz,
ADD COLUMN IF NOT EXISTS terms_version text,
ADD COLUMN IF NOT EXISTS phone_skipped_at timestamptz;
COMMENT ON COLUMN public.clients.terms_accepted_at IS 'Fecha y hora en que el cliente aceptó los términos y condiciones.';
COMMENT ON COLUMN public.clients.terms_version IS 'Versión formal de términos y condiciones aceptada (NULL si no está definida).';
COMMENT ON COLUMN public.clients.phone_skipped_at IS 'Fecha y hora en que el cliente decidió omitir la validación de teléfono.';
-- 2. Blindar columnas de onboarding en el trigger de clientes
CREATE OR REPLACE FUNCTION public.protect_client_sensitive_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND current_user NOT IN ('postgres','service_role','supabase_admin')
     AND NOT public.is_staff_or_admin() THEN
    IF NEW.status IS DISTINCT FROM OLD.status
       OR NEW.credit_allowed IS DISTINCT FROM OLD.credit_allowed
       OR NEW.has_app_access IS DISTINCT FROM OLD.has_app_access
       OR NEW.is_active IS DISTINCT FROM OLD.is_active
       OR NEW.source IS DISTINCT FROM OLD.source
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.preferred_currency IS DISTINCT FROM OLD.preferred_currency
       OR NEW.profile_completed IS DISTINCT FROM OLD.profile_completed
       OR NEW.terms_accepted_at IS DISTINCT FROM OLD.terms_accepted_at
       OR NEW.terms_version IS DISTINCT FROM OLD.terms_version
       OR NEW.phone_skipped_at IS DISTINCT FROM OLD.phone_skipped_at THEN
      RAISE EXCEPTION USING errcode = '42501', message = 'No puedes modificar campos administrativos o de onboarding del cliente directamente.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
-- 3. Función RPC para consultar el estado completo del onboarding del usuario autenticado
CREATE OR REPLACE FUNCTION public.get_my_onboarding_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_profile public.profiles%ROWTYPE;
  v_client public.clients%ROWTYPE;
  v_has_valid_name boolean;
  v_has_valid_phone boolean;
  v_phone_skipped boolean;
  v_terms_accepted boolean;
  v_is_completed boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'authenticated', false,
      'profile_completed', false
    );
  END IF;

  SELECT * INTO v_profile
  FROM public.profiles
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'authenticated', true,
      'profile_found', false,
      'profile_completed', false
    );
  END IF;

  SELECT * INTO v_client
  FROM public.clients
  WHERE id = v_profile.client_id;

  v_has_valid_name := (v_profile.full_name IS NOT NULL AND btrim(v_profile.full_name) <> '' AND v_profile.full_name <> 'Sin especificar');
  v_has_valid_phone := (v_profile.phone IS NOT NULL AND btrim(v_profile.phone) <> '');
  v_phone_skipped := (v_client.phone_skipped_at IS NOT NULL);
  v_terms_accepted := (v_client.terms_accepted_at IS NOT NULL);
  v_is_completed := COALESCE(v_client.profile_completed, false);

  RETURN jsonb_build_object(
    'authenticated', true,
    'profile_found', true,
    'user_id', v_user_id,
    'email', v_profile.email,
    'full_name', v_profile.full_name,
    'phone', v_profile.phone,
    'has_valid_name', v_has_valid_name,
    'has_valid_phone', v_has_valid_phone,
    'phone_skipped', v_phone_skipped,
    'terms_accepted', v_terms_accepted,
    'terms_version', v_client.terms_version,
    'profile_completed', v_is_completed,
    'client_id', v_profile.client_id,
    'role', v_profile.role,
    'is_active', v_profile.is_active
  );
END;
$$;
-- 4. Función RPC para guardado parcial de datos de contacto (Paso 2 Nombre, Paso 3 Teléfono)
-- NOTA: No modifica business_name para respetar nombres comerciales / institucionales
CREATE OR REPLACE FUNCTION public.save_onboarding_contact(
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_phone_skipped boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_client_id uuid;
  v_clean_name text;
  v_clean_phone text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'Sesión requerida.';
  END IF;

  SELECT client_id INTO v_client_id
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_client_id IS NULL THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'No existe perfil vinculado.';
  END IF;

  -- Sanitizar nombre si viene
  IF p_full_name IS NOT NULL THEN
    v_clean_name := left(btrim(p_full_name), 160);
    IF length(v_clean_name) >= 2 AND v_clean_name <> 'Sin especificar' THEN
      UPDATE public.profiles
      SET full_name = v_clean_name,
          updated_at = now()
      WHERE id = v_user_id;

      UPDATE public.clients
      SET contact_name = v_clean_name,
          updated_at = now()
      WHERE id = v_client_id;
    END IF;
  END IF;

  -- Sanitizar teléfono si viene o marcar omitido
  IF p_phone IS NOT NULL AND btrim(p_phone) <> '' THEN
    v_clean_phone := left(btrim(p_phone), 40);
    UPDATE public.profiles
    SET phone = v_clean_phone,
        updated_at = now()
    WHERE id = v_user_id;

    UPDATE public.clients
    SET phone = v_clean_phone,
        updated_at = now()
    WHERE id = v_client_id;
  ELSIF p_phone_skipped THEN
    UPDATE public.clients
    SET phone_skipped_at = COALESCE(phone_skipped_at, now()),
        updated_at = now()
    WHERE id = v_client_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'client_id', v_client_id
  );
END;
$$;
-- 5. Función RPC autoritativa para completar el onboarding
-- NOTA: No modifica business_name para respetar nombres comerciales / institucionales
CREATE OR REPLACE FUNCTION public.complete_user_onboarding(
  p_full_name text,
  p_phone text DEFAULT NULL,
  p_phone_skipped boolean DEFAULT false,
  p_terms_version text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_client_id uuid;
  v_clean_name text;
  v_clean_phone text;
  v_current_phone text;
  v_phone_skipped_already boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'Sesión requerida.';
  END IF;

  -- Obtener perfil del usuario
  SELECT client_id, phone INTO v_client_id, v_current_phone
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_client_id IS NULL THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'No existe perfil vinculado para este usuario.';
  END IF;

  -- Validar Nombre
  v_clean_name := left(btrim(COALESCE(p_full_name, '')), 160);
  IF length(v_clean_name) < 2 OR v_clean_name = 'Sin especificar' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'Se requiere un nombre válido para completar el registro.';
  END IF;

  -- Validar Teléfono según regla (debe haber teléfono o haberse omitido explícitamente)
  IF p_phone IS NOT NULL AND btrim(p_phone) <> '' THEN
    v_clean_phone := left(btrim(p_phone), 40);
  ELSE
    v_clean_phone := v_current_phone;
  END IF;

  SELECT (phone_skipped_at IS NOT NULL) INTO v_phone_skipped_already
  FROM public.clients
  WHERE id = v_client_id;

  IF (v_clean_phone IS NULL OR btrim(v_clean_phone) = '') AND NOT p_phone_skipped AND NOT COALESCE(v_phone_skipped_already, false) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'El teléfono es requerido o debe confirmarse como omitido.';
  END IF;

  -- Actualizar profiles
  UPDATE public.profiles
  SET full_name = v_clean_name,
      phone = NULLIF(v_clean_phone, ''),
      updated_at = now()
  WHERE id = v_user_id;

  -- Actualizar clients con contacto, términos y profile_completed
  UPDATE public.clients
  SET contact_name = v_clean_name,
      phone = NULLIF(v_clean_phone, ''),
      phone_skipped_at = CASE WHEN p_phone_skipped THEN COALESCE(phone_skipped_at, now()) ELSE phone_skipped_at END,
      terms_accepted_at = COALESCE(terms_accepted_at, now()),
      terms_version = COALESCE(p_terms_version, terms_version),
      profile_completed = true,
      has_app_access = true,
      app_registered_at = COALESCE(app_registered_at, now()),
      updated_at = now()
  WHERE id = v_client_id;

  RETURN jsonb_build_object(
    'success', true,
    'profile_completed', true,
    'client_id', v_client_id,
    'user_id', v_user_id
  );
END;
$$;
-- 6. Asignar permisos estrictos a las funciones RPC
REVOKE ALL ON FUNCTION public.get_my_onboarding_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_onboarding_status() TO authenticated;
REVOKE ALL ON FUNCTION public.save_onboarding_contact(text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_onboarding_contact(text, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_user_onboarding(text, text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_user_onboarding(text, text, boolean, text) TO authenticated;
