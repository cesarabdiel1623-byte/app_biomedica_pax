-- =====================================================
-- GO MEDICAL — Fix RLS + Sync Users
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- =====================================================

-- ─── 1. TABLA clients: Agregar/Reparar políticas RLS ───
DROP POLICY IF EXISTS "Users can view own profile" ON public.clients;
DROP POLICY IF EXISTS "Users can update own profile" ON public.clients;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.clients;

CREATE POLICY "Users can view own profile" ON public.clients
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.clients
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.clients
  FOR INSERT WITH CHECK (auth.uid() = id);


-- ─── 2. TABLA carts: Agregar políticas RLS ───
DROP POLICY IF EXISTS "Users can view own carts" ON public.carts;
DROP POLICY IF EXISTS "Users can create own carts" ON public.carts;
DROP POLICY IF EXISTS "Users can update own carts" ON public.carts;

CREATE POLICY "Users can view own carts" ON public.carts
  FOR SELECT USING (auth.uid() = client_id);

CREATE POLICY "Users can create own carts" ON public.carts
  FOR INSERT WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Users can update own carts" ON public.carts
  FOR UPDATE USING (auth.uid() = client_id);


-- ─── 3. TABLA cart_items: Agregar políticas RLS ───
DROP POLICY IF EXISTS "Users can view own cart items" ON public.cart_items;
DROP POLICY IF EXISTS "Users can insert own cart items" ON public.cart_items;
DROP POLICY IF EXISTS "Users can update own cart items" ON public.cart_items;
DROP POLICY IF EXISTS "Users can delete own cart items" ON public.cart_items;

CREATE POLICY "Users can view own cart items" ON public.cart_items
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.carts WHERE carts.id = cart_items.cart_id AND carts.client_id = auth.uid())
  );

CREATE POLICY "Users can insert own cart items" ON public.cart_items
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.carts WHERE carts.id = cart_items.cart_id AND carts.client_id = auth.uid())
  );

CREATE POLICY "Users can update own cart items" ON public.cart_items
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.carts WHERE carts.id = cart_items.cart_id AND carts.client_id = auth.uid())
  );

CREATE POLICY "Users can delete own cart items" ON public.cart_items
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.carts WHERE carts.id = cart_items.cart_id AND carts.client_id = auth.uid())
  );


-- ─── 4. TABLA client_addresses: Verificar políticas RLS ───
DROP POLICY IF EXISTS "Users can view own addresses" ON public.client_addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.client_addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON public.client_addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.client_addresses;

CREATE POLICY "Users can view own addresses" ON public.client_addresses
  FOR SELECT USING (auth.uid() = client_id);

CREATE POLICY "Users can insert own addresses" ON public.client_addresses
  FOR INSERT WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Users can update own addresses" ON public.client_addresses
  FOR UPDATE USING (auth.uid() = client_id);

CREATE POLICY "Users can delete own addresses" ON public.client_addresses
  FOR DELETE USING (auth.uid() = client_id);


-- ─── 5. TRIGGER: Actualizar para usar columnas REALES ───
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.clients (id, business_name, contact_name, email, phone, is_active, preferred_currency, country)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'Usuario'),
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    NEW.email,
    NEW.phone,
    TRUE,
    'MXN',
    'México'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ─── 6. SINCRONIZAR usuarios que ya existen sin perfil ───
INSERT INTO public.clients (id, business_name, contact_name, email, is_active, preferred_currency, country)
SELECT 
  id,
  COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', 'Usuario'),
  COALESCE(raw_user_meta_data->>'full_name', ''),
  email,
  TRUE,
  'MXN',
  'México'
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.clients)
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- DONE! Verifica en Table Editor que:
-- 1. clients tiene a todos los usuarios de auth.users
-- 2. Las políticas RLS aparecen en cada tabla
-- =====================================================
