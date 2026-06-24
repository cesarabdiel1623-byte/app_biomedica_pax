-- =====================================================
-- GO MEDICAL — Supabase Setup (English table names)
-- Run in: Supabase Dashboard → SQL Editor → New query
-- =====================================================

-- 1. TABLE: clients (B2B profile linked to auth.users)
CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT,
  clinic TEXT,
  license TEXT,
  address TEXT,
  phone TEXT,
  avatar_url TEXT,
  auth_provider TEXT DEFAULT 'email',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile" ON public.clients
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.clients
  FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.clients
  FOR INSERT WITH CHECK (auth.uid() = id);


-- 2. TABLE: categories
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  icon TEXT,
  color TEXT,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read categories" ON public.categories
  FOR SELECT USING (true);

INSERT INTO public.categories (name, icon, color, sort_order) VALUES
  ('Veterinaria', 'paw', '#10B981', 1),
  ('Imagenología', 'radioactive', '#6366F1', 2),
  ('Soporte de Vida', 'heart-pulse', '#EF4444', 3),
  ('Refacciones', 'cog', '#F59E0B', 4),
  ('Laboratorio', 'flask', '#8B5CF6', 5),
  ('Cirugía', 'content-cut', '#EC4899', 6)
ON CONFLICT (name) DO NOTHING;


-- 3. TABLE: products
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  price DECIMAL(12,2) NOT NULL,
  old_price DECIMAL(12,2),
  stock INT DEFAULT 0,
  main_image TEXT,
  images TEXT[],
  data_sheet TEXT,
  category TEXT NOT NULL,
  brand TEXT,
  warranty TEXT,
  featured BOOLEAN DEFAULT false,
  condition TEXT DEFAULT 'Nuevo',
  sold_count INT DEFAULT 0,
  rating DECIMAL(2,1) DEFAULT 0,
  review_count INT DEFAULT 0,
  free_shipping BOOLEAN DEFAULT false,
  delivery_days TEXT DEFAULT '3-5 días hábiles',
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read active products" ON public.products
  FOR SELECT USING (active = true);


-- 4. TABLE: orders
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.clients(id) NOT NULL,
  order_date TIMESTAMPTZ DEFAULT NOW(),
  status TEXT DEFAULT 'Pendiente',
  total DECIMAL(12,2) NOT NULL,
  shipping_address TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own orders" ON public.orders
  FOR SELECT USING (auth.uid() = client_id);
CREATE POLICY "Users can create orders" ON public.orders
  FOR INSERT WITH CHECK (auth.uid() = client_id);


-- 5. TABLE: order_items
CREATE TABLE IF NOT EXISTS public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES public.products(id) NOT NULL,
  quantity INT NOT NULL DEFAULT 1,
  unit_price DECIMAL(12,2) NOT NULL
);

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own order items" ON public.order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.orders
      WHERE orders.id = order_items.order_id
      AND orders.client_id = auth.uid()
    )
  );
CREATE POLICY "Users can insert order items" ON public.order_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders
      WHERE orders.id = order_items.order_id
      AND orders.client_id = auth.uid()
    )
  );


-- 6. TABLE: tickets (support / maintenance)
CREATE TABLE IF NOT EXISTS public.tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.clients(id) NOT NULL,
  product_id UUID REFERENCES public.products(id),
  product_name TEXT,
  issue TEXT NOT NULL,
  status TEXT DEFAULT 'Abierto',
  image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own tickets" ON public.tickets
  FOR SELECT USING (auth.uid() = client_id);
CREATE POLICY "Users can create tickets" ON public.tickets
  FOR INSERT WITH CHECK (auth.uid() = client_id);


-- 7. STORAGE: Bucket for ticket images
INSERT INTO storage.buckets (id, name, public)
VALUES ('ticket-images', 'ticket-images', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Authenticated users can upload ticket images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'ticket-images' AND auth.role() = 'authenticated');

CREATE POLICY "Anyone can view ticket images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'ticket-images');


-- 8. TRIGGER: Auto-create client profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.clients (id, name, email, phone, auth_provider)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    NEW.email,
    NEW.phone,
    COALESCE(NEW.raw_app_meta_data->>'provider', 'email')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists to avoid errors on re-run
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =====================================================
-- SEED DATA: Initial products
-- =====================================================

INSERT INTO public.products (name, description, price, old_price, stock, main_image, images, data_sheet, category, brand, warranty, featured, condition, sold_count, rating, review_count, free_shipping, delivery_days) VALUES
(
  'Monitor de Signos Vitales Veterinario Multiparamétrico 12.1"',
  'Monitor multiparamétrico para uso veterinario. Incluye SpO2, ECG, NIBP, temperatura y capnografía. Pantalla TFT de 12.1 pulgadas con alta resolución. Alarmas configurables y tendencias de 72 horas.',
  25000.00, 30000.00, 5,
  'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=800&fit=crop', 'https://images.unsplash.com/photo-1581093588401-fbb62a02f120?w=800&fit=crop'],
  'https://example.com/manual-monitor.pdf',
  'Veterinaria', 'Mindray', '2 años', true,
  'Nuevo', 150, 4.7, 23, true, '3-5 días hábiles'
),
(
  'Ultrasonido Portátil Doppler Color con Sonda Convexa y Lineal',
  'Sistema de ultrasonido portátil con Doppler color. Ideal para diagnóstico en consultorio. Incluye sonda convexa y lineal. Batería de larga duración de hasta 3 horas.',
  85000.00, NULL, 3,
  'https://images.unsplash.com/photo-1516549655169-df83a0774514?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1516549655169-df83a0774514?w=800&fit=crop'],
  'https://example.com/manual-ultrasonido.pdf',
  'Imagenología', 'GE Healthcare', '3 años', true,
  'Nuevo', 45, 4.9, 12, true, '5-7 días hábiles'
),
(
  'Ventilador Mecánico UCI Pantalla Táctil 15" Modos Avanzados',
  'Ventilador de soporte de vida para unidades de cuidados intensivos. Modos ventilatorios avanzados: VCV, PCV, SIMV, CPAP, BiPAP. Pantalla táctil de 15 pulgadas.',
  180000.00, 200000.00, 2,
  'https://images.unsplash.com/photo-1582750433449-648ed127bb54?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1582750433449-648ed127bb54?w=800&fit=crop'],
  'https://example.com/manual-ventilador.pdf',
  'Soporte de Vida', 'Dräger', '5 años', true,
  'Nuevo', 28, 4.8, 8, true, '7-10 días hábiles'
),
(
  'Electrocardiógrafo Digital 12 Canales Wi-Fi USB Interpretación Auto',
  'ECG digital de 12 canales con interpretación automática. Impresión térmica integrada. Conectividad Wi-Fi y USB para exportar estudios.',
  15000.00, 18000.00, 8,
  'https://images.unsplash.com/photo-1559757175-5700dde675bc?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1559757175-5700dde675bc?w=800&fit=crop'],
  NULL,
  'Soporte de Vida', 'Edan', '2 años', false,
  'Nuevo', 210, 4.5, 34, true, '2-4 días hábiles'
),
(
  'Mesa Quirúrgica Eléctrica Radiotranslúcida 250kg',
  'Mesa de cirugía con control eléctrico de posiciones. Capacidad máxima de 250 kg. Superficie radiotranslúcida. Accesorios intercambiables.',
  95000.00, NULL, 1,
  'https://images.unsplash.com/photo-1551190822-a9ce113ac100?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1551190822-a9ce113ac100?w=800&fit=crop'],
  'https://example.com/manual-mesa.pdf',
  'Cirugía', 'Mindray', '3 años', true,
  'Nuevo', 15, 4.6, 5, false, '10-15 días hábiles'
),
(
  'Sensor de SpO2 Veterinario Clip Tipo Y Compatible Mindray Edan',
  'Sensor de oximetría de pulso compatible con monitores veterinarios Mindray, Edan y Bionet. Clip tipo Y para lengua o oreja. Cable de 3 metros.',
  2500.00, 3000.00, 20,
  'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=800&fit=crop'],
  NULL,
  'Refacciones', 'Genérico', '6 meses', false,
  'Nuevo', 430, 4.3, 67, true, '1-3 días hábiles'
),
(
  'Analizador de Química Sanguínea Automatizado 120 Pruebas/Hora',
  'Sistema de análisis clínico automatizado. 120 pruebas por hora. Reactivos secos. Ideal para laboratorio de clínica pequeña o mediana.',
  45000.00, NULL, 4,
  'https://images.unsplash.com/photo-1579154204601-01588f351e67?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1579154204601-01588f351e67?w=800&fit=crop'],
  'https://example.com/manual-quimica.pdf',
  'Laboratorio', 'Rayto', '2 años', true,
  'Nuevo', 62, 4.4, 18, true, '5-7 días hábiles'
),
(
  'Desfibrilador Externo Automático DEA Guía de Voz Español',
  'DEA con guía de voz en español. Parches adulto y pediátrico incluidos. Batería de litio de larga duración (5 años standby). Certificación FDA y CE.',
  22000.00, 25000.00, 6,
  'https://images.unsplash.com/photo-1530026405186-ed1f139313f8?w=400&h=400&fit=crop',
  ARRAY['https://images.unsplash.com/photo-1530026405186-ed1f139313f8?w=800&fit=crop'],
  'https://example.com/manual-dea.pdf',
  'Soporte de Vida', 'Philips', '5 años', false,
  'Nuevo', 95, 4.8, 41, true, '2-4 días hábiles'
);


-- =====================================================
-- DONE! Verify in Table Editor that all tables exist:
-- clients, categories, products, orders, order_items, tickets
-- =====================================================
