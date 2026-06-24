-- =====================================================
-- GO MEDICAL — Reinsertar productos SOLO MÉDICOS (FIXED)
-- Limpia dependencias FK antes de borrar products
-- =====================================================

-- STEP 0: Clean all FK dependencies first
DELETE FROM public.service_parts_used;
DELETE FROM public.maintenance_logs;
DELETE FROM public.equipment_history;
DELETE FROM public.equipment_units;
DELETE FROM public.inventory_movements;
DELETE FROM public.inventory_stock;
DELETE FROM public.sale_items;
DELETE FROM public.order_items;
DELETE FROM public.cart_items;
DELETE FROM public.quote_items;
DELETE FROM public.product_specs;
DELETE FROM public.product_media;
DELETE FROM public.product_documents;
DELETE FROM public.products;

-- STEP 1: Insert 12 medical-only products
INSERT INTO public.products (sku, name, category, application, commercial_brand, description, brand, model, unit_price_mxn, cost_price_mxn, old_price, currency, unit, is_active, requires_serial, track_inventory, lead_time_days, warranty_text, shipping_info, availability_status, subcategory) VALUES
('USG-DP300', 'Ultrasonido Doppler Portátil GM-DP300',
 'equipo_medico', 'humano', 'Go Medical',
 'Equipo de ultrasonido Doppler color portátil, pantalla LED de 15", batería de larga duración. Tecnología de reducción de speckle, imagen armónica tisular y conectividad DICOM 3.0 completa.',
 'Go Medical', 'GM-DP300', 125000.00, 75000.00, 150000.00, 'MXN', 'pieza', true, true, true, 5,
 '24 meses de garantía. Incluye 2 mantenimientos preventivos.', 'Envío gratis', 'Disponible', 'ultrasonido'),
('RX-500D', 'Rayos X Digital GM-RX500 Piso a Techo',
 'equipo_medico', 'humano', 'Go Medical',
 'Sala de rayos X digital de piso a techo, generador de alta frecuencia de 50kW. Detector Flat Panel de CsI con imágenes de alta resolución y dosis mínima al paciente.',
 'Go Medical', 'GM-RX500', 450000.00, 280000.00, NULL, 'MXN', 'pieza', true, true, true, 15,
 '36 meses de garantía. Instalación incluida.', 'Envío e instalación a convenir', 'Cotizable', 'rayos_x'),
('MON-MV120', 'Monitor de Signos Vitales GM-MV120 12"',
 'equipo_medico', 'humano', 'Go Medical',
 'Monitor multiparamétrico de 12 pulgadas. ECG 5 derivadas, SpO2, NIBP, temperatura y respiración. Interfaz intuitiva con alarmas inteligentes.',
 'Go Medical', 'GM-MV120', 28500.00, 16000.00, 32000.00, 'MXN', 'pieza', true, true, true, 4,
 '12 meses de garantía.', 'Llega gratis mañana', 'Disponible', 'monitores'),
('ECG-12CH', 'Electrocardiógrafo Digital 12 Canales Wi-Fi',
 'equipo_medico', 'humano', 'Edan',
 'ECG digital de 12 canales con interpretación automática. Impresión térmica integrada. Conectividad Wi-Fi y USB.',
 'Edan', 'SE-1201', 15000.00, 8500.00, 18000.00, 'MXN', 'pieza', true, true, true, 3,
 '12 meses de garantía.', 'Envío gratis', 'Disponible', 'ecg'),
('VENT-UCI15', 'Ventilador Mecánico UCI Pantalla Táctil 15"',
 'equipo_medico', 'humano', 'Dräger',
 'Ventilador de soporte de vida para UCI. Modos: VCV, PCV, SIMV, CPAP, BiPAP. Pantalla táctil 15". Monitoreo de mecánica pulmonar.',
 'Dräger', 'Evita V300', 180000.00, 120000.00, 200000.00, 'MXN', 'pieza', true, true, true, 10,
 '5 años de garantía.', 'Envío e instalación incluidos', 'Cotizable', 'soporte_vida'),
('DEA-AED3', 'Desfibrilador Externo Automático DEA',
 'equipo_medico', 'humano', 'Philips',
 'DEA con guía de voz en español. Parches adulto y pediátrico incluidos. Batería de litio 5 años standby. Certificación FDA y CE.',
 'Philips', 'HeartStart FRx', 22000.00, 13000.00, 25000.00, 'MXN', 'pieza', true, true, true, 3,
 '5 años de garantía.', 'Envío gratis', 'Disponible', 'soporte_vida'),
('USG-CONV', 'Ultrasonido Portátil Doppler Color con Sondas',
 'ultrasonido_humano', 'humano', 'GE Healthcare',
 'Sistema de ultrasonido portátil con Doppler color. Sonda convexa y lineal incluidas. Batería de 3 horas. Ideal para consultorio.',
 'GE Healthcare', 'Logiq e', 85000.00, 52000.00, NULL, 'MXN', 'pieza', true, true, true, 7,
 '36 meses de garantía.', 'Envío gratis', 'Disponible', 'ultrasonido'),
('PACS-PRO', 'Panel PACS Médico CloudPACS Pro',
 'ultrasonido_humano', 'ambos', 'Go Medical',
 'Sistema PACS en la nube. Visor DICOM integrado. Almacenamiento ilimitado. Acceso desde cualquier dispositivo.',
 'Go Medical', 'CloudPACS Pro', 45000.00, 20000.00, 50000.00, 'MXN', 'servicio', true, false, false, 1,
 'Soporte 24/7 incluido.', 'Entrega digital inmediata', 'Disponible', 'pacs'),
('CONS-GEL5L', 'Gel para Ultrasonido 5 Litros',
 'consumible', 'ambos', 'EcoGel',
 'Gel conductor de alta viscosidad. Transmisión acústica óptima. No mancha, sin alcohol, soluble en agua.',
 'EcoGel', 'Galón 5L', 450.00, 180.00, NULL, 'MXN', 'litro', true, false, true, 2,
 'Caducidad: 24 meses.', 'Envío gratis', 'Disponible', 'gel'),
('CONS-PAPEL', 'Papel Térmico para Ultrasonido Sony UPP-110HD',
 'consumible', 'ambos', 'Sony',
 'Rollo de papel térmico HD blanco y negro. Grado médico. 110mm x 20m.',
 'Sony', 'UPP-110HD', 320.00, 150.00, 380.00, 'MXN', 'rollo', true, false, true, 2,
 'N/A', 'Llega mañana', 'Bajo stock', 'papel_termico'),
('REF-TRANS-C', 'Transductor Convexo Multifrecuencia C3-5',
 'refaccion', 'humano', 'Go Medical',
 'Sonda convexa multifrecuencia para aplicaciones abdominales. 100% compatible con GM-DP300.',
 'Go Medical', 'C3-5', 18000.00, 9500.00, NULL, 'MXN', 'pieza', true, true, true, 5,
 '6 meses de garantía.', 'Envío gratis', 'Disponible', 'sondas'),
('SERV-MANT-USG', 'Mantenimiento Preventivo Ultrasonido',
 'servicio', 'humano', 'Go Medical Service',
 'Mantenimiento preventivo anual. Revisión, calibración y limpieza profesional de equipos de ultrasonido.',
 'Go Medical', 'Mant-USG', 4500.00, 1500.00, NULL, 'MXN', 'servicio', true, false, false, 1,
 'Garantía de 30 días post-servicio.', 'Servicio en sitio', 'Cotizable', 'preventivo');

-- STEP 2: Insert images
INSERT INTO public.product_media (product_id, file_path, file_name, document_type, is_primary, sort_order)
SELECT p.id, i.fp, i.fn, 'imagen', i.pr, i.so
FROM public.products p JOIN (VALUES
('USG-DP300','https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?w=600&fit=crop','img1.jpg',true,0),
('USG-DP300','https://images.unsplash.com/photo-1516549655169-df83a0774514?w=600&fit=crop','img2.jpg',false,1),
('RX-500D','https://images.unsplash.com/photo-1530497610245-94d3c16cda28?w=600&fit=crop','img1.jpg',true,0),
('MON-MV120','https://images.unsplash.com/photo-1581594693702-fbdc51b2763b?w=600&fit=crop','img1.jpg',true,0),
('ECG-12CH','https://images.unsplash.com/photo-1559757175-5700dde675bc?w=600&fit=crop','img1.jpg',true,0),
('VENT-UCI15','https://images.unsplash.com/photo-1582750433449-648ed127bb54?w=600&fit=crop','img1.jpg',true,0),
('DEA-AED3','https://images.unsplash.com/photo-1530026405186-ed1f139313f8?w=600&fit=crop','img1.jpg',true,0),
('USG-CONV','https://images.unsplash.com/photo-1516549655169-df83a0774514?w=600&fit=crop','img1.jpg',true,0),
('PACS-PRO','https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=600&fit=crop','img1.jpg',true,0),
('CONS-GEL5L','https://images.unsplash.com/photo-1579154204601-01588f351e67?w=600&fit=crop','img1.jpg',true,0),
('CONS-PAPEL','https://images.unsplash.com/photo-1616423640778-28d1b53229bd?w=600&fit=crop','img1.jpg',true,0),
('REF-TRANS-C','https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?w=600&fit=crop','img1.jpg',true,0),
('SERV-MANT-USG','https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=600&fit=crop','img1.jpg',true,0)
) AS i(sku,fp,fn,pr,so) ON p.sku=i.sku;

-- STEP 3: Insert specs
INSERT INTO public.product_specs (product_id, spec_group, spec_key, spec_value, sort_order)
SELECT p.id, s.sg, s.sk, s.sv, s.so
FROM public.products p JOIN (VALUES
('USG-DP300','General','Pantalla','LED 15 pulgadas',1),
('USG-DP300','General','Batería','Autonomía de 4 horas',2),
('USG-DP300','Conectividad','DICOM','3.0 completo',3),
('RX-500D','General','Potencia','50kW',1),
('RX-500D','General','Detector','Flat Panel CsI',2),
('MON-MV120','General','Pantalla','12 pulgadas TFT',1),
('MON-MV120','Parámetros','Mediciones','ECG, SpO2, NIBP, TEMP, RESP',2),
('ECG-12CH','General','Canales','12 simultáneos',1),
('VENT-UCI15','General','Pantalla','Táctil 15 pulgadas',1),
('VENT-UCI15','Modos','Ventilación','VCV, PCV, SIMV, CPAP, BiPAP',2),
('DEA-AED3','General','Guía','Voz en español',1),
('DEA-AED3','General','Batería','5 años standby',2),
('USG-CONV','General','Sondas','Convexa + Lineal',1),
('CONS-GEL5L','General','Volumen','5 Litros',1),
('REF-TRANS-C','General','Tipo','Convexo Multifrecuencia',1)
) AS s(sku,sg,sk,sv,so) ON p.sku=s.sku;

-- DONE! Verify:
-- SELECT count(*) FROM products;  → 12
-- SELECT sku, name, category, application FROM products ORDER BY category;
