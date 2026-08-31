-- 1. Add resource_type and resource_id to notifications
ALTER TABLE public.notifications
ADD COLUMN IF NOT EXISTS resource_type text NULL,
ADD COLUMN IF NOT EXISTS resource_id uuid NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_resource_lookup ON public.notifications (user_id, resource_type, resource_id);
-- 2. Modify notify_client_on_quote_status_change
CREATE OR REPLACE FUNCTION public.notify_client_on_quote_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_status_es TEXT;
  v_client_user_id uuid;
  v_resource_type text;
  v_resource_id uuid;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    v_status_es := CASE NEW.status::text
      WHEN 'draft' THEN 'Borrador'
      WHEN 'sent' THEN 'Enviada'
      WHEN 'approved' THEN 'Aprobada'
      WHEN 'rejected' THEN 'Rechazada'
      ELSE NEW.status::text
    END;

    SELECT p.id INTO v_client_user_id
    FROM public.profiles p
    WHERE p.client_id = NEW.client_id
      AND p.is_active = true
      AND lower(p.role::text) = 'client'
    LIMIT 1;

    IF v_client_user_id IS NOT NULL THEN
      IF NEW.service_ticket_id IS NOT NULL THEN
        v_resource_type := 'service_ticket';
        v_resource_id := NEW.service_ticket_id;
      ELSE
        v_resource_type := 'quote';
        v_resource_id := NEW.id;
      END IF;

      INSERT INTO public.notifications (user_id, title, body, is_read, resource_type, resource_id)
      VALUES (
        v_client_user_id,
        'Actualización de cotización',
        'Tu cotización ' || COALESCE(NEW.quote_number, '') || ' cambió a estado: ' || v_status_es,
        FALSE,
        v_resource_type,
        v_resource_id
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
-- 3. Modify notify_client_on_support_message
CREATE OR REPLACE FUNCTION public.notify_client_on_support_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
declare
  v_client_id uuid;
  v_ticket_number text;
begin
  if new.sender_type::text in ('staff', 'admin', 'agent', 'support') and coalesce(new.is_internal, false) is false then
    select t.client_id, t.ticket_number
    into v_client_id, v_ticket_number
    from public.service_tickets as t
    where t.id = new.ticket_id;

    if v_client_id is not null then
      insert into public.notifications (
        user_id,
        title,
        body,
        is_read,
        resource_type,
        resource_id
      )
      select
        profile_record.id,
        'Nuevo mensaje en ticket ' || coalesce(v_ticket_number, ''),
        case
          when new.message is not null and btrim(new.message) <> ''
            then substr(new.message, 1, 120)
          else 'Has recibido un archivo adjunto en tu ticket de soporte.'
        end,
        false,
        'service_ticket',
        new.ticket_id
      from public.profiles as profile_record
      where profile_record.client_id = v_client_id
        and profile_record.is_active is true
        and lower(profile_record.role::text) = 'client';
    end if;
  end if;

  return new;
end;
$$;
-- 4. Modify notify_client_on_ticket_status_change
CREATE OR REPLACE FUNCTION public.notify_client_on_ticket_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
begin
  if old.status is distinct from new.status then
    insert into public.notifications (
      user_id,
      title,
      body,
      is_read,
      resource_type,
      resource_id
    )
    select
      profile_record.id,
      'Actualización de tu ticket',
      'El estado de tu ticket cambió a: ' ||
        case new.status::text
          when 'open' then 'Abierto'
          when 'assigned' then 'Asignado a técnico'
          when 'in_progress' then 'En proceso'
          when 'waiting_parts' then 'Esperando refacciones'
          when 'paused' then 'En pausa'
          when 'resolved' then 'Servicio realizado'
          when 'closed' then 'Cerrado'
          when 'cancelled' then 'Cancelado'
          else new.status::text
        end,
      false,
      'service_ticket',
      new.id
    from public.profiles as profile_record
    where profile_record.client_id = new.client_id
      and profile_record.is_active is true
      and lower(profile_record.role::text) = 'client';
  end if;

  return new;
end;
$$;
-- 5. Modify notify_client_on_quote_message
CREATE OR REPLACE FUNCTION public.notify_client_on_quote_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_client_id UUID;
  v_quote_number TEXT;
  v_service_ticket_id UUID;
  v_resource_type TEXT;
  v_resource_id UUID;
BEGIN
  IF NEW.sender_type = 'staff' AND NEW.is_internal = FALSE THEN
    -- Get quote details and infer resource type from service ticket association
    SELECT client_id, quote_number, service_ticket_id INTO v_client_id, v_quote_number, v_service_ticket_id
    FROM public.quotes WHERE id = NEW.quote_id;

    IF v_client_id IS NOT NULL THEN
      IF v_service_ticket_id IS NOT NULL THEN
        v_resource_type := 'service_ticket';
        v_resource_id := v_service_ticket_id;
      ELSE
        v_resource_type := 'quote';
        v_resource_id := NEW.quote_id;
      END IF;

      INSERT INTO public.notifications (user_id, title, body, is_read, resource_type, resource_id)
      SELECT
        p.id,
        'Nuevo mensaje de cotización',
        COALESCE('Cotización ' || v_quote_number || ': ', '') || substring(NEW.message from 1 for 100),
        FALSE,
        v_resource_type,
        v_resource_id
      FROM public.profiles p
      WHERE p.client_id = v_client_id
        AND p.is_active = true
        AND lower(p.role::text) = 'client';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
-- 6. Modify notify_client_on_question_answered
CREATE OR REPLACE FUNCTION public.notify_client_on_question_answered()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_product_name text;
  v_answer_text text;
BEGIN
  IF NEW.status = 'answered' AND (OLD.status IS DISTINCT FROM 'answered' OR NEW.answer_text IS DISTINCT FROM OLD.answer_text) THEN
    SELECT name INTO v_product_name FROM public.products WHERE id = NEW.product_id;

    v_answer_text := NEW.answer_text;
    IF v_answer_text IS NULL OR v_answer_text = '' THEN
      SELECT answer_text INTO v_answer_text
      FROM public.product_answers
      WHERE question_id = NEW.id
      ORDER BY created_at DESC LIMIT 1;
    END IF;

    IF NEW.profile_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, title, body, is_read, created_at, resource_type, resource_id)
      VALUES (
        NEW.profile_id,
        'Pregunta respondida',
        'Tu pregunta sobre "' || coalesce(v_product_name, 'el producto') || '" fue respondida: "' || coalesce(v_answer_text, '') || '"',
        false,
        now(),
        'product_question',
        NEW.id
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
-- 7. Backfill
-- product_questions backfill
UPDATE public.notifications n
SET resource_type = 'product_question'
WHERE n.title = 'Pregunta respondida'
  AND n.resource_type IS NULL
  AND n.resource_id IS NULL;
-- quotes backfill
UPDATE public.notifications n
SET resource_type = CASE WHEN q.service_ticket_id IS NOT NULL THEN 'service_ticket' ELSE 'quote' END,
    resource_id = CASE WHEN q.service_ticket_id IS NOT NULL THEN q.service_ticket_id ELSE q.id END
FROM public.quotes q
JOIN public.profiles p ON p.client_id = q.client_id
WHERE n.title IN ('Actualización de cotización', 'Nuevo mensaje de cotización')
  AND n.user_id = p.id
  AND n.body LIKE '%' || q.quote_number || '%'
  AND n.resource_id IS NULL;
-- service tickets backfill (Nuevo mensaje en ticket TCK-...)
UPDATE public.notifications n
SET resource_type = 'service_ticket',
    resource_id = t.id
FROM public.service_tickets t
JOIN public.profiles p ON p.client_id = t.client_id
WHERE n.title = 'Nuevo mensaje en ticket ' || t.ticket_number
  AND n.user_id = p.id
  AND n.resource_id IS NULL;
