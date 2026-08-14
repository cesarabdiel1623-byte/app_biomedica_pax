-- 1. Agregar columna sales_count a products si no existe
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='products' AND column_name='sales_count') THEN
        ALTER TABLE products ADD COLUMN sales_count INTEGER NOT NULL DEFAULT 0;
    END IF;
END $$;

-- 2. Crear función para actualizar sales_count
CREATE OR REPLACE FUNCTION public.update_product_sales_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    -- Si el estado del pedido cambia a 'paid' o 'delivered'
    IF NEW.status IN ('paid', 'delivered') AND (OLD.status IS NULL OR OLD.status NOT IN ('paid', 'delivered')) THEN
        -- Sumar la cantidad vendida a cada producto
        UPDATE public.products
        SET sales_count = sales_count + oi.quantity
        FROM public.order_items oi
        WHERE oi.order_id = NEW.id AND public.products.id = oi.product_id;
    END IF;

    -- Si el estado del pedido cambia a 'canceled' y antes era 'paid' o 'delivered'
    IF NEW.status = 'canceled' AND OLD.status IN ('paid', 'delivered') THEN
        -- Restar la cantidad vendida a cada producto
        UPDATE public.products
        SET sales_count = sales_count - oi.quantity
        FROM public.order_items oi
        WHERE oi.order_id = NEW.id AND public.products.id = oi.product_id;
    END IF;

    RETURN NEW;
END;
$function$;

-- 3. Crear el Trigger en la tabla orders
DROP TRIGGER IF EXISTS trigger_update_sales_count ON public.orders;
CREATE TRIGGER trigger_update_sales_count
AFTER UPDATE ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION public.update_product_sales_count();
;
