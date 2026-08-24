BEGIN;
-- 1. Protección previa
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.product_reviews r
        LEFT JOIN public.clients c ON c.id = r.client_id
        WHERE r.client_id IS NOT NULL
          AND c.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Existen filas en product_reviews cuyo client_id no existe en public.clients. Abortando migración.';
    END IF;
END $$;
-- 2. Corregir FK
ALTER TABLE public.product_reviews
DROP CONSTRAINT IF EXISTS product_reviews_client_id_fkey;
ALTER TABLE public.product_reviews
ADD CONSTRAINT product_reviews_client_id_fkey
FOREIGN KEY (client_id)
REFERENCES public.clients(id)
ON DELETE CASCADE;
-- 3. Eliminar SOLO las políticas legacy incorrectas
DROP POLICY IF EXISTS "Anyone can view product reviews" ON public.product_reviews;
DROP POLICY IF EXISTS "Users can create reviews" ON public.product_reviews;
DROP POLICY IF EXISTS "Users can update or delete their own reviews" ON public.product_reviews;
-- 4. Endurecer EXECUTE de la RPC
REVOKE EXECUTE ON FUNCTION public.submit_product_review(uuid, integer, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_product_review(uuid, integer, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.submit_product_review(uuid, integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_product_review(uuid, integer, text, text) TO service_role;
COMMIT;
