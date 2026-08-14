-- 1. Alter product_questions
ALTER TABLE public.product_questions DROP COLUMN IF EXISTS answer_text;

-- Restrict status constraint
ALTER TABLE public.product_questions DROP CONSTRAINT IF EXISTS chk_product_questions_status;
ALTER TABLE public.product_questions ADD CONSTRAINT chk_product_questions_status CHECK (status IN ('pending', 'answered', 'hidden', 'archived'));

-- Add missing columns
ALTER TABLE public.product_questions ADD COLUMN IF NOT EXISTS profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.product_questions ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT true;
ALTER TABLE public.product_questions ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.product_questions ADD COLUMN IF NOT EXISTS answered_at timestamptz NULL;
ALTER TABLE public.product_questions ADD COLUMN IF NOT EXISTS hidden_at timestamptz NULL;
ALTER TABLE public.product_questions ADD COLUMN IF NOT EXISTS archived_at timestamptz NULL;

-- 2. Indexes for product_questions
CREATE INDEX IF NOT EXISTS idx_product_questions_product_id ON public.product_questions(product_id);
CREATE INDEX IF NOT EXISTS idx_product_questions_status ON public.product_questions(status);
CREATE INDEX IF NOT EXISTS idx_product_questions_created_at ON public.product_questions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_questions_client_id ON public.product_questions(client_id);
CREATE INDEX IF NOT EXISTS idx_product_questions_profile_id ON public.product_questions(profile_id);

-- 3. product_answers constraints and indexes
ALTER TABLE public.product_answers DROP CONSTRAINT IF EXISTS unique_question_id;
ALTER TABLE public.product_answers ADD CONSTRAINT unique_question_id UNIQUE(question_id);

CREATE INDEX IF NOT EXISTS idx_product_answers_question_id ON public.product_answers(question_id);
CREATE INDEX IF NOT EXISTS idx_product_answers_answered_by ON public.product_answers(answered_by);

-- 4. Triggers
CREATE OR REPLACE FUNCTION mark_product_question_answered()
RETURNS TRIGGER AS $$
BEGIN
  -- Solo actualizar si la pregunta no esta hidden ni archived
  UPDATE public.product_questions
  SET 
    status = CASE 
               WHEN status IN ('hidden', 'archived') THEN status 
               ELSE 'answered' 
             END,
    answered_at = CASE 
                    WHEN status IN ('hidden', 'archived') THEN answered_at 
                    ELSE now() 
                  END,
    updated_at = now()
  WHERE id = NEW.question_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_mark_product_question_answered_insert ON public.product_answers;
CREATE TRIGGER trg_mark_product_question_answered_insert
AFTER INSERT OR UPDATE ON public.product_answers
FOR EACH ROW
EXECUTE FUNCTION mark_product_question_answered();

-- updated_at trigger for product_questions
DROP TRIGGER IF EXISTS trg_product_questions_updated_at ON public.product_questions;
CREATE TRIGGER trg_product_questions_updated_at
BEFORE UPDATE ON public.product_questions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- updated_at trigger for product_answers
DROP TRIGGER IF EXISTS trg_product_answers_updated_at ON public.product_answers;
CREATE TRIGGER trg_product_answers_updated_at
BEFORE UPDATE ON public.product_answers
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- 5. RPC para submit mobile
CREATE OR REPLACE FUNCTION submit_product_question(p_product_id uuid, p_question_text text)
RETURNS public.product_questions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_profile_id uuid;
  v_client_id uuid;
  v_is_active boolean;
  v_visible_in_app boolean;
  v_clean_text text;
  v_question public.product_questions;
BEGIN
  -- 1. Requerir auth.uid()
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado.';
  END IF;

  -- 2, 3, 4. Validar producto
  SELECT is_active, visible_in_app INTO v_is_active, v_visible_in_app
  FROM public.products WHERE id = p_product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Producto no existe.';
  END IF;

  IF NOT v_is_active OR NOT v_visible_in_app THEN
    RAISE EXCEPTION 'El producto no está disponible para preguntas.';
  END IF;

  -- 5. Limpiar espacios y rechazar vacíos
  v_clean_text := trim(p_question_text);
  IF v_clean_text = '' THEN
    RAISE EXCEPTION 'La pregunta no puede estar vacía.';
  END IF;

  -- 7. Validar longitud
  IF length(v_clean_text) < 10 THEN
    RAISE EXCEPTION 'La pregunta es muy corta (mínimo 10 caracteres).';
  END IF;
  IF length(v_clean_text) > 500 THEN
    RAISE EXCEPTION 'La pregunta es muy larga (máximo 500 caracteres).';
  END IF;

  -- 8, 9. Buscar profile (id es auth.uid() en supabase usualmente)
  SELECT id, client_id INTO v_profile_id, v_client_id 
  FROM public.profiles WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Perfil de usuario no encontrado.';
  END IF;

  -- 10. Insertar pregunta
  INSERT INTO public.product_questions (
    product_id, profile_id, client_id, question_text, status, is_public
  ) VALUES (
    p_product_id, v_profile_id, v_client_id, v_clean_text, 'pending', true
  ) RETURNING * INTO v_question;

  -- 11. Retornar
  RETURN v_question;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RLS Policies
ALTER TABLE public.product_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_answers ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Public can view answered public questions" ON public.product_questions;
DROP POLICY IF EXISTS "Staff can manage all questions" ON public.product_questions;
DROP POLICY IF EXISTS "Public can view public answers" ON public.product_answers;
DROP POLICY IF EXISTS "Staff can manage all answers" ON public.product_answers;
DROP POLICY IF EXISTS "Users can view own pending questions" ON public.product_questions;

-- Questions Policies
CREATE POLICY "Public can view answered public questions"
ON public.product_questions
FOR SELECT
USING (
  status = 'answered' 
  AND is_public = true 
  AND EXISTS (
    SELECT 1 FROM public.products p 
    WHERE p.id = product_questions.product_id 
      AND p.is_active = true 
      AND p.visible_in_app = true
  )
);

CREATE POLICY "Users can view own pending questions"
ON public.product_questions
FOR SELECT
USING (
  profile_id = auth.uid()
);

CREATE POLICY "Staff can manage all questions"
ON public.product_questions
FOR ALL
USING (
  public.is_staff_or_admin()
)
WITH CHECK (
  public.is_staff_or_admin()
);

-- Answers Policies
CREATE POLICY "Public can view public answers"
ON public.product_answers
FOR SELECT
USING (
  is_public = true
);

CREATE POLICY "Staff can manage all answers"
ON public.product_answers
FOR ALL
USING (
  public.is_staff_or_admin()
)
WITH CHECK (
  public.is_staff_or_admin()
);;
