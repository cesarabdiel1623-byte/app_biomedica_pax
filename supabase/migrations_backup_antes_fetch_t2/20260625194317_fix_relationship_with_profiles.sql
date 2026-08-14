-- 1. Alter product_reviews to reference public.profiles(id)
ALTER TABLE public.product_reviews
DROP CONSTRAINT IF EXISTS product_reviews_client_id_fkey,
ADD CONSTRAINT product_reviews_client_id_fkey 
FOREIGN KEY (client_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 2. Alter product_questions to reference public.profiles(id)
ALTER TABLE public.product_questions
DROP CONSTRAINT IF EXISTS product_questions_client_id_fkey,
ADD CONSTRAINT product_questions_client_id_fkey 
FOREIGN KEY (client_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 3. Alter client_favorites to reference public.profiles(id)
ALTER TABLE public.client_favorites
DROP CONSTRAINT IF EXISTS client_favorites_client_id_fkey,
ADD CONSTRAINT client_favorites_client_id_fkey 
FOREIGN KEY (client_id) REFERENCES public.profiles(id) ON DELETE CASCADE;;
