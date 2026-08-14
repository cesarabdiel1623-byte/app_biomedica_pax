-- Enum para source (si no existe)
DO $$ BEGIN
    CREATE TYPE opportunity_source AS ENUM ('cart', 'abandoned_cart', 'quote_request', 'quote', 'manual', 'whatsapp', 'email', 'phone', 'other');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Enum para status de oportunidad
DO $$ BEGIN
    CREATE TYPE sales_opportunity_status AS ENUM ('new', 'contacted', 'follow_up', 'quote_requested', 'quoted', 'won', 'lost', 'archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Enum para prioridad
DO $$ BEGIN
    CREATE TYPE opportunity_priority AS ENUM ('low', 'medium', 'high');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS public.sales_opportunities (
    id uuid primary key default gen_random_uuid(),
    opportunity_number text unique default 'OP-' || upper(substr(md5(random()::text), 1, 8)),
    source opportunity_source not null default 'manual',
    status sales_opportunity_status not null default 'new',
    priority opportunity_priority not null default 'medium',
    
    client_id uuid references public.clients(id) on delete set null,
    profile_id uuid references public.profiles(id) on delete set null,
    cart_id uuid,
    quote_request_id uuid references public.quote_requests(id) on delete set null,
    quote_id uuid references public.quotes(id) on delete set null,
    order_id uuid references public.orders(id) on delete set null,
    
    title text not null,
    description text,
    contact_name text,
    contact_email text,
    contact_phone text,
    company_name text,
    
    estimated_total numeric(12,2) not null default 0,
    currency text not null default 'MXN',
    products_summary text,
    items_count integer not null default 0,
    
    assigned_to uuid references public.profiles(id) on delete set null,
    next_follow_up_at timestamptz,
    last_activity_at timestamptz not null default now(),
    attended_at timestamptz,
    closed_at timestamptz,
    archived_at timestamptz,
    lost_reason text,
    won_at timestamptz,
    lost_at timestamptz,
    
    created_by uuid references public.profiles(id) on delete set null,
    updated_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Unique parcial para evitar duplicar por cart_id
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_opp_active_cart 
ON public.sales_opportunities (cart_id) 
WHERE status IN ('new', 'contacted', 'follow_up', 'quote_requested');

CREATE TABLE IF NOT EXISTS public.sales_opportunity_items (
    id uuid primary key default gen_random_uuid(),
    opportunity_id uuid not null references public.sales_opportunities(id) on delete cascade,
    product_id uuid references public.products(id) on delete set null,
    sku_snapshot text,
    product_name_snapshot text not null,
    product_category_snapshot text,
    quantity numeric(12,2) not null default 1,
    unit_price numeric(12,2),
    estimated_total numeric(12,2),
    created_at timestamptz not null default now()
);

CREATE TABLE IF NOT EXISTS public.sales_opportunity_notes (
    id uuid primary key default gen_random_uuid(),
    opportunity_id uuid not null references public.sales_opportunities(id) on delete cascade,
    note text not null,
    contact_channel text, -- whatsapp, email, phone, in_person, note
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

-- 2. RLS Policies

ALTER TABLE public.sales_opportunities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_opportunity_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_opportunity_notes ENABLE ROW LEVEL SECURITY;

-- Staff/Admin ven todo
CREATE POLICY "Staff can view all opportunities" ON public.sales_opportunities FOR SELECT
USING (public.is_staff_or_admin());

CREATE POLICY "Staff can insert opportunities" ON public.sales_opportunities FOR INSERT
WITH CHECK (public.is_staff_or_admin());

CREATE POLICY "Staff can update opportunities" ON public.sales_opportunities FOR UPDATE
USING (public.is_staff_or_admin());

CREATE POLICY "Staff can delete opportunities" ON public.sales_opportunities FOR DELETE
USING (public.is_staff_or_admin());

CREATE POLICY "Clients can view their own opportunities indirectly" ON public.sales_opportunities FOR SELECT
USING (client_id = public.get_my_client_id() OR profile_id = auth.uid());

CREATE POLICY "Service roles can insert opportunities via triggers" ON public.sales_opportunities FOR ALL
USING (true) WITH CHECK (true);

-- Igual para items
CREATE POLICY "Staff can view all opp items" ON public.sales_opportunity_items FOR SELECT USING (public.is_staff_or_admin());
CREATE POLICY "Staff can insert opp items" ON public.sales_opportunity_items FOR INSERT WITH CHECK (public.is_staff_or_admin());
CREATE POLICY "Staff can update opp items" ON public.sales_opportunity_items FOR UPDATE USING (public.is_staff_or_admin());
CREATE POLICY "Staff can delete opp items" ON public.sales_opportunity_items FOR DELETE USING (public.is_staff_or_admin());
CREATE POLICY "Clients can view their opp items" ON public.sales_opportunity_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.sales_opportunities o WHERE o.id = opportunity_id AND (o.client_id = public.get_my_client_id() OR o.profile_id = auth.uid()))
);
CREATE POLICY "Service roles can insert opp items via triggers" ON public.sales_opportunity_items FOR ALL USING (true) WITH CHECK (true);

-- Igual para notes
CREATE POLICY "Staff can view all opp notes" ON public.sales_opportunity_notes FOR SELECT USING (public.is_staff_or_admin());
CREATE POLICY "Staff can insert opp notes" ON public.sales_opportunity_notes FOR INSERT WITH CHECK (public.is_staff_or_admin());
CREATE POLICY "Staff can update opp notes" ON public.sales_opportunity_notes FOR UPDATE USING (public.is_staff_or_admin());
CREATE POLICY "Staff can delete opp notes" ON public.sales_opportunity_notes FOR DELETE USING (public.is_staff_or_admin());

-- 3. Función y Trigger
CREATE OR REPLACE FUNCTION public.sync_cart_to_opportunity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cart record;
    v_total numeric;
    v_items_count int;
    v_summary text;
    v_opp_id uuid;
    v_target_cart_id uuid;
BEGIN
    -- Determinar el cart_id afectado (por el item modificado/insertado/borrado)
    IF TG_OP = 'DELETE' THEN
        v_target_cart_id := OLD.cart_id;
    ELSE
        v_target_cart_id := NEW.cart_id;
    END IF;

    -- Obtener info del carrito y usuario
    SELECT * INTO v_cart FROM public.carts WHERE id = v_target_cart_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Calcular totales desde cart_items
    SELECT 
        COALESCE(SUM(quantity * unit_price), 0),
        COALESCE(SUM(quantity), 0),
        string_agg(product_name_snapshot, ', ')
    INTO v_total, v_items_count, v_summary
    FROM public.cart_items
    WHERE cart_id = v_target_cart_id;
    
    -- Limitar longitud del summary
    IF length(v_summary) > 200 THEN
        v_summary := substr(v_summary, 1, 197) || '...';
    END IF;

    -- Buscar oportunidad ACTIVA para este carrito
    SELECT id INTO v_opp_id 
    FROM public.sales_opportunities 
    WHERE cart_id = v_target_cart_id 
      AND status IN ('new', 'contacted', 'follow_up', 'quote_requested');

    IF v_opp_id IS NOT NULL THEN
        -- Actualizar oportunidad existente
        UPDATE public.sales_opportunities
        SET 
            estimated_total = v_total,
            items_count = v_items_count,
            products_summary = COALESCE(v_summary, 'Sin productos'),
            last_activity_at = now(),
            updated_at = now()
        WHERE id = v_opp_id;
        
    ELSIF v_items_count > 0 THEN
        -- Si hay items y no existe una opp activa, creamos una nueva
        INSERT INTO public.sales_opportunities (
            cart_id, 
            client_id, 
            title, 
            contact_name, 
            contact_email, 
            contact_phone, 
            source, 
            status, 
            estimated_total, 
            items_count, 
            products_summary,
            last_activity_at
        ) VALUES (
            v_target_cart_id,
            v_cart.client_id,
            'Oportunidad de Carrito',
            v_cart.lead_name,
            v_cart.lead_email,
            v_cart.lead_phone,
            'cart',
            'new',
            v_total,
            v_items_count,
            COALESCE(v_summary, 'Sin productos'),
            now()
        ) RETURNING id INTO v_opp_id;
    END IF;

    -- Si el carrito quedó vacío, y tenemos la oportunidad activa
    IF v_items_count = 0 AND v_opp_id IS NOT NULL THEN
        -- Marcar como archivada y limpiar totales
        UPDATE public.sales_opportunities
        SET 
            estimated_total = 0,
            items_count = 0,
            products_summary = 'Carrito vaciado',
            status = 'archived',
            archived_at = now(),
            updated_at = now()
        WHERE id = v_opp_id;
    END IF;

    -- Sincronizar items
    IF v_opp_id IS NOT NULL THEN
        -- Borrar items actuales de la opp
        DELETE FROM public.sales_opportunity_items WHERE opportunity_id = v_opp_id;
        
        -- Insertar los nuevos (una copia de cart_items)
        INSERT INTO public.sales_opportunity_items (
            opportunity_id, product_id, sku_snapshot, product_name_snapshot, 
            product_category_snapshot, quantity, unit_price, estimated_total
        )
        SELECT 
            v_opp_id, product_id, sku_snapshot, product_name_snapshot, 
            product_category_snapshot::text, quantity, unit_price, total_line_price
        FROM public.cart_items
        WHERE cart_id = v_target_cart_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_cart_items ON public.cart_items;
CREATE TRIGGER trg_sync_cart_items
AFTER INSERT OR UPDATE OR DELETE ON public.cart_items
FOR EACH ROW
EXECUTE FUNCTION public.sync_cart_to_opportunity();;
