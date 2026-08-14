-- Tabla: categories (Categorías del catálogo con control de posición en Home)
CREATE TABLE public.categories (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  slug         TEXT NOT NULL UNIQUE,
  image_url    TEXT,
  show_before_slider BOOLEAN NOT NULL DEFAULT false,
  show_after_slider  BOOLEAN NOT NULL DEFAULT false,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  sort_order   INTEGER DEFAULT 0,
  created_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_no_both_positions
    CHECK (NOT (show_before_slider = true AND show_after_slider = true))
);

-- RLS
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view categories"
  ON public.categories FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert categories"
  ON public.categories FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update categories"
  ON public.categories FOR UPDATE
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can delete categories"
  ON public.categories FOR DELETE
  TO authenticated
  USING (true);

-- Trigger para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_categories_updated_at
  BEFORE UPDATE ON public.categories
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Insertar categorías iniciales basadas en el enum existente de productos
INSERT INTO public.categories (name, slug, show_before_slider, show_after_slider, sort_order) VALUES
  ('Equipo Médico',            'equipo-medico',           false, true,  1),
  ('Accesorios',               'accesorios',              false, true,  2),
  ('Consumibles',              'consumibles',             false, true,  3),
  ('Refacciones',              'refacciones',             false, false, 4),
  ('Servicios',                'servicios',               false, false, 5),
  ('Ultrasonido Humano',       'ultrasonido-humano',      false, true,  6),
  ('Ultrasonido Veterinario',  'ultrasonido-veterinario', false, false, 7);;
