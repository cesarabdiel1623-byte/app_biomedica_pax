-- =====================================================
-- GO MEDICAL — Migration: Add columns + Remove veterinary
-- Run in: Supabase Dashboard → SQL Editor
-- =====================================================

-- STEP 1: Add missing columns to products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS old_price numeric;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS warranty_text text;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS shipping_info text DEFAULT 'Envío estándar';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS availability_status text DEFAULT 'Disponible';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS subcategory text;

-- STEP 2: Delete veterinary products (and their media/specs via CASCADE or manual)
-- First delete product_specs for veterinary products
DELETE FROM public.product_specs
WHERE product_id IN (
  SELECT id FROM public.products
  WHERE application = 'veterinario'
     OR category = 'ultrasonido_veterinario'
);

-- Delete product_media for veterinary products
DELETE FROM public.product_media
WHERE product_id IN (
  SELECT id FROM public.products
  WHERE application = 'veterinario'
     OR category = 'ultrasonido_veterinario'
);

-- Delete the veterinary products themselves
DELETE FROM public.products
WHERE application = 'veterinario'
   OR category = 'ultrasonido_veterinario';

-- STEP 3: Update remaining products with the new columns data
UPDATE public.products SET
  old_price = 150000.00,
  warranty_text = '24 meses de garantía. Incluye 2 mantenimientos preventivos.',
  shipping_info = 'Envío gratis',
  availability_status = 'Disponible',
  subcategory = 'ultrasonido'
WHERE sku = 'USG-DP300';

UPDATE public.products SET
  warranty_text = '36 meses de garantía. Instalación incluida.',
  shipping_info = 'Envío a convenir',
  availability_status = 'Cotizable',
  subcategory = 'rayos_x'
WHERE sku = 'RX-500D';

UPDATE public.products SET
  old_price = 32000.00,
  warranty_text = '12 meses de garantía.',
  shipping_info = 'Llega gratis mañana',
  availability_status = 'Disponible',
  subcategory = 'monitores'
WHERE sku = 'MON-MV120';

UPDATE public.products SET
  old_price = 18000.00,
  warranty_text = '12 meses de garantía.',
  shipping_info = 'Envío gratis',
  availability_status = 'Disponible',
  subcategory = 'ecg'
WHERE sku = 'ECG-12CH';

UPDATE public.products SET
  old_price = 200000.00,
  warranty_text = '5 años de garantía.',
  shipping_info = 'Envío a convenir',
  availability_status = 'Cotizable',
  subcategory = 'soporte_vida'
WHERE sku = 'VENT-UCI15';

UPDATE public.products SET
  old_price = 25000.00,
  warranty_text = '5 años de garantía. Certificación FDA y CE.',
  shipping_info = 'Envío gratis',
  availability_status = 'Disponible',
  subcategory = 'soporte_vida'
WHERE sku = 'DEA-AED3';

UPDATE public.products SET
  warranty_text = '36 meses de garantía.',
  shipping_info = 'Envío gratis',
  availability_status = 'Disponible',
  subcategory = 'ultrasonido'
WHERE sku = 'USG-CONV';

UPDATE public.products SET
  warranty_text = 'Caducidad: 24 meses.',
  shipping_info = 'Envío gratis',
  availability_status = 'Disponible',
  subcategory = 'gel'
WHERE sku = 'CONS-GEL5L';

UPDATE public.products SET
  old_price = 380.00,
  warranty_text = 'N/A',
  shipping_info = 'Llega mañana',
  availability_status = 'Bajo stock',
  subcategory = 'papel_termico'
WHERE sku = 'CONS-PAPEL';

UPDATE public.products SET
  warranty_text = '6 meses de garantía.',
  shipping_info = 'Envío gratis',
  availability_status = 'Disponible',
  subcategory = 'sondas'
WHERE sku = 'REF-TRANS-C';

UPDATE public.products SET
  warranty_text = 'Garantía de 30 días post-servicio.',
  shipping_info = 'Servicio en sitio',
  availability_status = 'Cotizable',
  subcategory = 'preventivo'
WHERE sku = 'SERV-MANT-USG';

-- STEP 4: Verify
-- SELECT count(*) FROM products;
-- Expected: ~10-11 products (no veterinary)
-- SELECT sku, name, category, application, old_price, availability_status FROM products;

-- =====================================================
-- DONE! All veterinary products removed.
-- New columns added: old_price, warranty_text, shipping_info, availability_status, subcategory
-- =====================================================
