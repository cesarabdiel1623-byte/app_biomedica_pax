-- Tabla: order_returns (Devoluciones y reclamaciones de pedidos)
CREATE TYPE public.return_status AS ENUM ('pending', 'approved', 'rejected');

CREATE TABLE public.order_returns (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_number TEXT NOT NULL DEFAULT generate_folio('RET'),
  order_id      UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  client_id     UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  product_name  TEXT NOT NULL,
  reason        TEXT NOT NULL,
  details       TEXT,
  status        public.return_status NOT NULL DEFAULT 'pending',
  evidence_url  TEXT,
  reviewed_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at   TIMESTAMPTZ,
  rejection_reason TEXT,
  created_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE public.order_returns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view returns"
  ON public.order_returns FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert returns"
  ON public.order_returns FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update returns"
  ON public.order_returns FOR UPDATE
  TO authenticated
  USING (true);

CREATE TRIGGER trg_order_returns_updated_at
  BEFORE UPDATE ON public.order_returns
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();;
