CREATE OR REPLACE FUNCTION public.notify_client_on_quote_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_status_es text;
  v_client_user_id uuid;
  v_resource_type text;
  v_resource_id uuid;
  v_title text;
  v_body text;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    v_status_es := CASE NEW.status::text
      WHEN 'draft' THEN 'Borrador'
      WHEN 'sent' THEN 'Enviada'
      WHEN 'approved' THEN 'Aprobada'
      WHEN 'rejected' THEN 'Rechazada'
      ELSE NEW.status::text
    END;

    SELECT p.id
    INTO v_client_user_id
    FROM public.profiles p
    WHERE p.client_id = NEW.client_id
      AND p.is_active = true
      AND lower(p.role::text) = 'client'
    LIMIT 1;

    IF v_client_user_id IS NOT NULL THEN
      IF NEW.service_ticket_id IS NOT NULL THEN
        v_resource_type := 'service_ticket';
        v_resource_id := NEW.service_ticket_id;
        v_title := 'Actualización de tu servicio';
        v_body := 'La propuesta de tu servicio cambió a estado: ' || v_status_es;
      ELSE
        v_resource_type := 'quote';
        v_resource_id := NEW.id;
        v_title := 'Actualización de cotización';
        v_body := 'Tu cotización ' || COALESCE(NEW.quote_number, '') ||
          ' cambió a estado: ' || v_status_es;
      END IF;

      INSERT INTO public.notifications (
        user_id,
        title,
        body,
        is_read,
        resource_type,
        resource_id
      )
      VALUES (
        v_client_user_id,
        v_title,
        v_body,
        false,
        v_resource_type,
        v_resource_id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_client_on_quote_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_client_id uuid;
  v_quote_number text;
  v_service_ticket_id uuid;
  v_resource_type text;
  v_resource_id uuid;
  v_title text;
  v_body text;
BEGIN
  IF NEW.sender_type = 'staff' AND NEW.is_internal = false THEN
    SELECT q.client_id, q.quote_number, q.service_ticket_id
    INTO v_client_id, v_quote_number, v_service_ticket_id
    FROM public.quotes q
    WHERE q.id = NEW.quote_id;

    IF v_client_id IS NOT NULL THEN
      IF v_service_ticket_id IS NOT NULL THEN
        v_resource_type := 'service_ticket';
        v_resource_id := v_service_ticket_id;
        v_title := 'Nuevo mensaje sobre tu servicio';
        v_body := 'Mensaje sobre la propuesta de tu servicio: ' ||
          substring(NEW.message from 1 for 100);
      ELSE
        v_resource_type := 'quote';
        v_resource_id := NEW.quote_id;
        v_title := 'Nuevo mensaje de cotización';
        v_body := COALESCE('Cotización ' || v_quote_number || ': ', '') ||
          substring(NEW.message from 1 for 100);
      END IF;

      INSERT INTO public.notifications (
        user_id,
        title,
        body,
        is_read,
        resource_type,
        resource_id
      )
      SELECT
        p.id,
        v_title,
        v_body,
        false,
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
