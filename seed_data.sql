-- =====================================================
-- GO MEDICAL — Seed Data for Products + Media
-- Run in: Supabase Dashboard → SQL Editor → New query
-- Uses the REAL schema with correct ENUMs
-- =====================================================

-- Insert products with correct ENUM types
INSERT INTO public.products (sku, name, category, application, commercial_brand, description, brand, model, unit_price_mxn, cost_price_mxn, currency, unit, is_active, requires_serial, track_inventory, lead_time_days) VALUES

-- EQUIPO MÉDICO HUMANO
('USG-DP300', 'Ultrasonido Doppler Portátil GM-DP300',
 'equipo_medico', 'humano', 'Go Medical',
 'Equipo de ultrasonido Doppler color portátil, pantalla LED de 15", batería de larga duración. Tecnología de reducción de speckle, imagen armónica tisular y conectividad DICOM 3.0 completa.',
 'Go Medical', 'GM-DP300', 125000.00, 75000.00, 'MXN', 'pieza', true, true, true, 7),

('RX-500D', 'Rayos X Digital GM-RX500 Piso a Techo',
 'equipo_medico', 'humano', 'Go Medical',
 'Sala de rayos X digital de piso a techo, generador de alta frecuencia de 50kW. Detector Flat Panel de CsI con imágenes de alta resolución y dosis mínima.',
 'Go Medical', 'GM-RX500', 450000.00, 280000.00, 'MXN', 'pieza', true, true, true, 15),

('MON-MV120', 'Monitor de Signos Vitales GM-MV120',
 'equipo_medico', 'humano', 'Go Medical',
 'Monitor multiparamétrico de 12 pulgadas. ECG 5 derivadas, SpO2, NIBP, TEMP, RESP. Interfaz intuitiva y alarmas inteligentes para urgencias y cuidados intermedios.',
 'Go Medical', 'GM-MV120', 28500.00, 16000.00, 'MXN', 'pieza', true, true, true, 5),

('ECG-12CH', 'Electrocardiógrafo Digital 12 Canales Wi-Fi',
 'equipo_medico', 'humano', 'Edan',
 'ECG digital de 12 canales con interpretación automática. Impresión térmica integrada. Conectividad Wi-Fi y USB. Base de datos interna para 1,000 ECGs.',
 'Edan', 'SE-1201', 15000.00, 8500.00, 'MXN', 'pieza', true, true, true, 4),

('VENT-UCI15', 'Ventilador Mecánico UCI Pantalla Táctil 15"',
 'equipo_medico', 'humano', 'Dräger',
 'Ventilador de soporte de vida para UCI. Modos: VCV, PCV, SIMV, CPAP, BiPAP. Pantalla táctil 15". Monitoreo de mecánica pulmonar en tiempo real.',
 'Dräger', 'Evita V300', 180000.00, 120000.00, 'MXN', 'pieza', true, true, true, 10),

('DEA-AED3', 'Desfibrilador Externo Automático DEA',
 'equipo_medico', 'humano', 'Philips',
 'DEA con guía de voz en español. Parches adulto y pediátrico incluidos. Batería de litio 5 años standby. Certificación FDA y CE. Maletín incluido.',
 'Philips', 'HeartStart FRx', 22000.00, 13000.00, 'MXN', 'pieza', true, true, true, 4),

-- ULTRASONIDO HUMANO
('USG-CONV', 'Ultrasonido Portátil Doppler Color con Sondas',
 'ultrasonido_humano', 'humano', 'GE Healthcare',
 'Sistema de ultrasonido portátil con Doppler color. Sonda convexa y lineal incluidas. Batería de 3 horas. Interfaz táctil con presets por especialidad.',
 'GE Healthcare', 'Logiq e', 85000.00, 52000.00, 'MXN', 'pieza', true, true, true, 7),

-- ULTRASONIDO VETERINARIO
('VET-USG200', 'Ultrasonido Veterinario Portátil GM-VET-US200',
 'ultrasonido_veterinario', 'veterinario', 'Go Medical Vet',
 'Ultrasonido para pequeñas y grandes especies. Software preinstalado para medición gestacional en caninos, felinos, equinos y bovinos. Resistente a líquidos.',
 'Go Medical', 'GM-VET-US200', 85000.00, 48000.00, 'MXN', 'pieza', true, true, true, 7),

('VET-RX300', 'Rayos X Veterinario Digital GM-VET-RX300',
 'ultrasonido_veterinario', 'veterinario', 'Go Medical Vet',
 'Sistema de radiografía digital compacto con mesa flotante para mascotas. Generador de alta frecuencia integrado. Flat Panel resistente a fluidos.',
 'Go Medical', 'GM-VET-RX300', 250000.00, 155000.00, 'MXN', 'pieza', true, true, true, 15),

('VET-MP100', 'Monitor Multiparámetro Veterinario GM-VET-MP100',
 'equipo_medico', 'veterinario', 'Go Medical Vet',
 'Monitor con accesorios para animales (pinzas linguales, manguitos especiales). Medición precisa incluso en animales con baja perfusión.',
 'Go Medical', 'GM-VET-MP100', 18000.00, 10000.00, 'MXN', 'pieza', true, true, true, 5),

-- CONSUMIBLES
('CONS-GEL5L', 'Gel para Ultrasonido 5 Litros',
 'consumible', 'ambos', 'EcoGel',
 'Gel conductor de alta viscosidad. Transmisión acústica óptima. No mancha, sin alcohol, soluble en agua. Presentación de galón.',
 'EcoGel', 'Galón 5L', 450.00, 180.00, 'MXN', 'litro', true, false, true, 2),

('CONS-PAPEL', 'Papel Térmico para Ultrasonido Sony UPP-110HD',
 'consumible', 'ambos', 'Sony',
 'Rollo de papel térmico de alta densidad (HD) blanco y negro. Grado médico. 110mm x 20m.',
 'Sony', 'UPP-110HD', 320.00, 150.00, 'MXN', 'rollo', true, false, true, 2),

-- REFACCIONES
('REF-TRANS-C', 'Transductor Convexo Multifrecuencia C3-5',
 'refaccion', 'humano', 'Go Medical',
 'Sonda convexa multifrecuencia para aplicaciones abdominales. 100% compatible con GM-DP300.',
 'Go Medical', 'C3-5', 18000.00, 9500.00, 'MXN', 'pieza', true, true, true, 5),

('REF-SPO2-VET', 'Sensor SpO2 Veterinario Clip Tipo Y',
 'refaccion', 'veterinario', 'Genérico',
 'Sensor de oximetría compatible con monitores Mindray, Edan y Bionet. Clip para lengua/oreja. Cable 3m. Conector DB9.',
 'Genérico', 'SPO2-Y-DB9', 2500.00, 800.00, 'MXN', 'pieza', true, false, true, 3),

-- ACCESORIOS
('ACC-MESA-VET', 'Mesa Quirúrgica Veterinaria en V Hidráulica',
 'accesorio', 'veterinario', 'VetEquip',
 'Mesa quirúrgica hidráulica de acero inoxidable 304 con diseño en V. Excelente drenaje de fluidos.',
 'VetEquip', 'V-Top Surgical', 32000.00, 18000.00, 'MXN', 'pieza', true, true, true, 10),

-- SERVICIOS
('SERV-MANT-USG', 'Mantenimiento Preventivo Ultrasonido',
 'servicio', 'ambos', 'Go Medical Service',
 'Mantenimiento preventivo anual. Revisión, calibración de parámetros y limpieza profesional de equipos de ultrasonido.',
 'Go Medical', 'Mant-USG', 4500.00, 1500.00, 'MXN', 'servicio', true, false, false, 1),

('SERV-MANT-VET', 'Mantenimiento Equipo Veterinario Completo',
 'servicio', 'veterinario', 'Go Medical Service',
 'Limpieza y mantenimiento especializado para clínicas veterinarias. Atención a filtros por acumulación de pelo en ventiladores.',
 'Go Medical', 'Mant-Vet', 5000.00, 2000.00, 'MXN', 'servicio', true, false, false, 1);


-- Now insert product_media (images for each product)
-- We use Unsplash images as placeholders
INSERT INTO public.product_media (product_id, file_path, file_name, document_type, is_primary, sort_order)
SELECT p.id, img.file_path, img.file_name, 'imagen', img.is_primary, img.sort_order
FROM public.products p
JOIN (VALUES
  ('USG-DP300', 'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?w=600&fit=crop', 'usg-dp300-1.jpg', true, 0),
  ('RX-500D', 'https://images.unsplash.com/photo-1530497610245-94d3c16cda28?w=600&fit=crop', 'rx-500d-1.jpg', true, 0),
  ('MON-MV120', 'https://images.unsplash.com/photo-1581594693702-fbdc51b2763b?w=600&fit=crop', 'mon-mv120-1.jpg', true, 0),
  ('ECG-12CH', 'https://images.unsplash.com/photo-1559757175-5700dde675bc?w=600&fit=crop', 'ecg-12ch-1.jpg', true, 0),
  ('VENT-UCI15', 'https://images.unsplash.com/photo-1582750433449-648ed127bb54?w=600&fit=crop', 'vent-uci15-1.jpg', true, 0),
  ('DEA-AED3', 'https://images.unsplash.com/photo-1530026405186-ed1f139313f8?w=600&fit=crop', 'dea-aed3-1.jpg', true, 0),
  ('USG-CONV', 'https://images.unsplash.com/photo-1516549655169-df83a0774514?w=600&fit=crop', 'usg-conv-1.jpg', true, 0),
  ('VET-USG200', 'https://images.unsplash.com/photo-1583337130417-3346a1be7dee?w=600&fit=crop', 'vet-usg200-1.jpg', true, 0),
  ('VET-RX300', 'https://images.unsplash.com/photo-1628009368231-7bb7cbcb8122?w=600&fit=crop', 'vet-rx300-1.jpg', true, 0),
  ('VET-MP100', 'https://images.unsplash.com/photo-1516714435131-44d6b64dc6a2?w=600&fit=crop', 'vet-mp100-1.jpg', true, 0),
  ('CONS-GEL5L', 'https://images.unsplash.com/photo-1579154204601-01588f351e67?w=600&fit=crop', 'cons-gel-1.jpg', true, 0),
  ('CONS-PAPEL', 'https://images.unsplash.com/photo-1616423640778-28d1b53229bd?w=600&fit=crop', 'cons-papel-1.jpg', true, 0),
  ('REF-TRANS-C', 'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?w=600&fit=crop', 'ref-trans-1.jpg', true, 0),
  ('REF-SPO2-VET', 'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=600&fit=crop', 'ref-spo2-1.jpg', true, 0),
  ('ACC-MESA-VET', 'https://images.unsplash.com/photo-1587824874315-0819ce299443?w=600&fit=crop', 'acc-mesa-1.jpg', true, 0),
  ('SERV-MANT-USG', 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=600&fit=crop', 'serv-mant-1.jpg', true, 0),
  ('SERV-MANT-VET', 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=600&fit=crop', 'serv-mant-vet-1.jpg', true, 0)
) AS img(sku, file_path, file_name, is_primary, sort_order) ON p.sku = img.sku;


-- Insert some product specs
INSERT INTO public.product_specs (product_id, spec_group, spec_key, spec_value, sort_order)
SELECT p.id, s.spec_group, s.spec_key, s.spec_value, s.sort_order
FROM public.products p
JOIN (VALUES
  ('USG-DP300', 'General', 'Pantalla', 'LED 15 pulgadas', 1),
  ('USG-DP300', 'General', 'Batería', 'Autonomía de 4 horas', 2),
  ('USG-DP300', 'Conectividad', 'DICOM', '3.0 completo', 3),
  ('RX-500D', 'General', 'Potencia', '50kW', 1),
  ('RX-500D', 'General', 'Detector', 'Flat Panel Inalámbrico CsI', 2),
  ('MON-MV120', 'General', 'Pantalla', '12 pulgadas TFT', 1),
  ('MON-MV120', 'Parámetros', 'Mediciones', 'ECG, SpO2, NIBP, TEMP, RESP', 2),
  ('VET-USG200', 'General', 'Software', 'Veterinario Especializado', 1),
  ('VET-USG200', 'General', 'Sondas incluidas', 'Microconvexa', 2),
  ('CONS-GEL5L', 'General', 'Volumen', '5 Litros', 1),
  ('REF-TRANS-C', 'General', 'Tipo', 'Convexo Multifrecuencia', 1),
  ('REF-SPO2-VET', 'General', 'Conector', 'DB9', 1),
  ('ACC-MESA-VET', 'General', 'Material', 'Acero INOX 304', 1),
  ('ACC-MESA-VET', 'General', 'Sistema', 'Elevación Hidráulica', 2)
) AS s(sku, spec_group, spec_key, spec_value, sort_order) ON p.sku = s.sku;


-- =====================================================
-- DONE! Run this and verify:
-- SELECT count(*) FROM products;  → should return 17
-- SELECT count(*) FROM product_media;  → should return 17
-- SELECT count(*) FROM product_specs;  → should return 14
-- =====================================================
