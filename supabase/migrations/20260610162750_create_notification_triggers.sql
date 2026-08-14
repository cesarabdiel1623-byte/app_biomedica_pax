-- Trigger 1: Notify client on support chat message (staff -> client)
CREATE OR REPLACE FUNCTION public.notify_client_on_support_message()
RETURNS TRIGGER AS $$
DECLARE
  v_client_id UUID;
  v_ticket_number TEXT;
BEGIN
  -- We only notify when staff sends a message and it is NOT internal
  IF NEW.sender_type = 'staff' AND NEW.is_internal = FALSE THEN
    SELECT client_id, ticket_number INTO v_client_id, v_ticket_number
    FROM public.service_tickets WHERE id = NEW.ticket_id;
    
    IF v_client_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, title, body, is_read)
      VALUES (
        v_client_id, 
        'Nuevo mensaje de soporte',
        COALESCE(v_ticket_number || ': ', '') || substring(NEW.message from 1 for 100),
        FALSE
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_client_on_support_message ON public.service_ticket_messages;
CREATE TRIGGER trg_notify_client_on_support_message
AFTER INSERT ON public.service_ticket_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_client_on_support_message();


-- Trigger 2: Notify client on service ticket status change
CREATE OR REPLACE FUNCTION public.notify_client_on_ticket_status_change()
RETURNS TRIGGER AS $$
DECLARE
  v_status_es TEXT;
BEGIN
  -- We only notify when status changes
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    v_status_es := CASE NEW.status::text
      WHEN 'open' THEN 'Abierto'
      WHEN 'cancelled' THEN 'Cancelado'
      WHEN 'closed' THEN 'Cerrado'
      WHEN 'waiting_parts' THEN 'Esperando refacciones'
      WHEN 'assigned' THEN 'Asignado a técnico'
      ELSE NEW.status::text
    END;

    INSERT INTO public.notifications (user_id, title, body, is_read)
    VALUES (
      NEW.client_id, 
      'Actualización de tu ticket',
      'Tu ticket ' || COALESCE(NEW.ticket_number, '') || ' cambió a estado: ' || v_status_es,
      FALSE
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_client_on_ticket_status_change ON public.service_tickets;
CREATE TRIGGER trg_notify_client_on_ticket_status_change
AFTER UPDATE ON public.service_tickets
FOR EACH ROW EXECUTE FUNCTION public.notify_client_on_ticket_status_change();


-- Trigger 3: Notify client on quote chat message (staff -> client)
CREATE OR REPLACE FUNCTION public.notify_client_on_quote_message()
RETURNS TRIGGER AS $$
DECLARE
  v_client_id UUID;
  v_quote_number TEXT;
BEGIN
  -- We only notify when staff sends a message and it is NOT internal
  IF NEW.sender_type = 'staff' AND NEW.is_internal = FALSE THEN
    SELECT client_id, quote_number INTO v_client_id, v_quote_number
    FROM public.quotes WHERE id = NEW.quote_id;
    
    IF v_client_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, title, body, is_read)
      VALUES (
        v_client_id, 
        'Nuevo mensaje de cotización',
        COALESCE('Cotización ' || v_quote_number || ': ', '') || substring(NEW.message from 1 for 100),
        FALSE
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_client_on_quote_message ON public.quote_messages;
CREATE TRIGGER trg_notify_client_on_quote_message
AFTER INSERT ON public.quote_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_client_on_quote_message();


-- Trigger 4: Notify client on quote status change
CREATE OR REPLACE FUNCTION public.notify_client_on_quote_status_change()
RETURNS TRIGGER AS $$
DECLARE
  v_status_es TEXT;
BEGIN
  -- We only notify when status changes
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    v_status_es := CASE NEW.status::text
      WHEN 'draft' THEN 'Borrador'
      WHEN 'sent' THEN 'Enviada'
      WHEN 'approved' THEN 'Aprobada'
      WHEN 'rejected' THEN 'Rechazada'
      ELSE NEW.status::text
    END;

    INSERT INTO public.notifications (user_id, title, body, is_read)
    VALUES (
      NEW.client_id, 
      'Actualización de cotización',
      'Tu cotización ' || COALESCE(NEW.quote_number, '') || ' cambió a estado: ' || v_status_es,
      FALSE
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_client_on_quote_status_change ON public.quotes;
CREATE TRIGGER trg_notify_client_on_quote_status_change
AFTER UPDATE ON public.quotes
FOR EACH ROW EXECUTE FUNCTION public.notify_client_on_quote_status_change();;
