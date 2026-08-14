-- 1. Create client_favorites table
CREATE TABLE IF NOT EXISTS public.client_favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(client_id, product_id)
);

-- Enable RLS for client_favorites
ALTER TABLE public.client_favorites ENABLE ROW LEVEL SECURITY;

-- RLS Policies for client_favorites
CREATE POLICY "Users can view their own favorites" 
    ON public.client_favorites FOR SELECT 
    USING (auth.uid() = client_id);

CREATE POLICY "Users can insert their own favorites" 
    ON public.client_favorites FOR INSERT 
    WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Users can delete their own favorites" 
    ON public.client_favorites FOR DELETE 
    USING (auth.uid() = client_id);


-- 2. Create product_questions table
CREATE TABLE IF NOT EXISTS public.product_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    answer_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS for product_questions
ALTER TABLE public.product_questions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for product_questions
CREATE POLICY "Anyone can view product questions" 
    ON public.product_questions FOR SELECT 
    USING (true);

CREATE POLICY "Users can ask product questions" 
    ON public.product_questions FOR INSERT 
    WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Users can delete their own questions" 
    ON public.product_questions FOR DELETE 
    USING (auth.uid() = client_id);


-- 3. Create product_reviews table
CREATE TABLE IF NOT EXISTS public.product_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    images TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS for product_reviews
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;

-- RLS Policies for product_reviews
CREATE POLICY "Anyone can view product reviews" 
    ON public.product_reviews FOR SELECT 
    USING (true);

CREATE POLICY "Users can create reviews" 
    ON public.product_reviews FOR INSERT 
    WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Users can update or delete their own reviews" 
    ON public.product_reviews FOR ALL 
    USING (auth.uid() = client_id);


-- 4. Create review-assets storage bucket if it does not exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('review-assets', 'review-assets', true)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for review-assets bucket
CREATE POLICY "Public Access to review-assets"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'review-assets');

CREATE POLICY "Authenticated users can upload review-assets"
    ON storage.objects FOR INSERT
    WITH CHECK (bucket_id = 'review-assets' AND auth.role() = 'authenticated');

CREATE POLICY "Users can update or delete their own review-assets"
    ON storage.objects FOR ALL
    USING (bucket_id = 'review-assets' AND auth.uid() = owner);;
