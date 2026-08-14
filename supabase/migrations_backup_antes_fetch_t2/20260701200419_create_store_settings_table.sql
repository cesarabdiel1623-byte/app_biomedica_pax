-- Tabla: store_settings (Configuración global del comercio)
CREATE TABLE public.store_settings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_name      TEXT NOT NULL DEFAULT 'Go Medical',
  logo_url        TEXT,
  primary_currency TEXT NOT NULL DEFAULT 'MXN',
  tax_regime      TEXT NOT NULL DEFAULT 'Régimen General',
  tax_pct         NUMERIC NOT NULL DEFAULT 0.16,
  brand_color     TEXT NOT NULL DEFAULT '#0D9488',
  banner_hero_url TEXT,
  whatsapp_number TEXT,
  contact_email   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Solo debe existir una fila de configuración
ALTER TABLE public.store_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view settings"
  ON public.store_settings FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can update settings"
  ON public.store_settings FOR UPDATE
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert settings"
  ON public.store_settings FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE TRIGGER trg_store_settings_updated_at
  BEFORE UPDATE ON public.store_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Insertar fila de configuración inicial
INSERT INTO public.store_settings (store_name, primary_currency, tax_regime, tax_pct, brand_color)
VALUES ('Go Medical', 'MXN', 'Régimen General', 0.16, '#0D9488');;
