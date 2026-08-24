ALTER TABLE public.product_logistics_data
ADD COLUMN IF NOT EXISTS package_type_code text;
COMMENT ON COLUMN public.product_logistics_data.package_type_code IS
'Package type code used by logistics/API integrations. The value must come from a valid provider catalog and is independent from the human packaging_type description.';
UPDATE public.product_logistics_data
SET package_type_code = '4G'
WHERE product_id = '8daf1dc5-8ee0-4cdb-9952-3a12c06af412'::uuid
  AND packaging_type = 'Caja reforzada mediana'
  AND package_type_code IS NULL;
