# Guía de Evidencias Fotográficas y Capturas de Pantalla (Supabase Backend)
**Capítulo IV: Resultados y Experiencias - Proyecto Go Medical**

Este documento contiene la lista detallada de capturas de pantalla que se sugiere tomar directamente desde el panel de Supabase (`https://supabase.com/dashboard`) o la interfaz de PostgreSQL/SQL Editor para ilustrar los resultados técnicos en el Capítulo IV del reporte de estadía profesional.

---

## Captura 1: Información General del Proyecto Supabase
- **Sección del panel:** Project Settings -> General
- **Qué debe aparecer:** Nombre del proyecto (`Go medical`), Región (`us-east-1`), versión del motor PostgreSQL (17.x), e indicador de estado activo.
- **Qué demuestra:** La existencia real del entorno backend en la nube AWS North Virginia y la plataforma administrada de Supabase.
- **Título sugerido:** *Figura 4.1. Configuración e infraestructura del proyecto Go Medical en Supabase.*
- **Datos a ocultar / censurar:** Ocultar el *Project Reference ID* completo y cualquier URL pública/privada de la API.

---

## Captura 2: Inventario de Tablas y RLS Habilitado
- **Sección del panel:** Table Editor / Database -> Tables
- **Qué debe aparecer:** Lista de tablas principales (`profiles`, `clients`, `carts`, `orders`, `service_tickets`, `products`, `notifications`) mostrando el badge verde `RLS Enabled` en cada una.
- **Qué demuestra:** Que el esquema relacional está completamente protegido mediante aislamiento Row Level Security.
- **Título sugerido:** *Figura 4.2. Estructura de tablas del esquema público y activación de RLS.*
- **Datos a ocultar / censurar:** Ninguno en la vista de lista de esquema.

---

## Captura 3: Relación entre Usuarios Auth, Perfiles y Clientes
- **Sección del panel:** Authentication -> Users & SQL Editor
- **Qué debe aparecer:** Vista general de usuarios registrados y el resultado de la consulta SQL que muestra la coincidencia entre `auth.users.id`, `profiles.id` y `profiles.client_id`.
- **Qué demuestra:** La arquitectura de vinculación automática entre identidades de autenticación y expedientes comerciales.
- **Título sugerido:** *Figura 4.3. Vinculación relacional entre credenciales de autenticación y entidad comercial del cliente.*
- **Datos a ocultar / censurar:** Censurar direcciones de correo electrónico reales de usuarios de prueba e identificadores UUID completos.

---

## Captura 4: Políticas de Seguridad RLS (Row Level Security)
- **Sección del panel:** Database -> Policies
- **Qué debe aparecer:** Las políticas creadas para las tablas `carts`, `orders` y `client_addresses` mostrando las condiciones `(client_id = auth.uid())` o `(client_id = get_my_client_id())`.
- **Qué demuestra:** La restricción de acceso multi-inquilino que impide que un cliente consulte datos de otro usuario.
- **Título sugerido:** *Figura 4.4. Reglas de acceso y políticas RLS para el aislamiento de información por cliente.*
- **Datos a ocultar / censurar:** Ninguno.

---

## Captura 5: Definición de Vistas de Promociones Basadas en Servidor
- **Sección del panel:** Database -> Views & SQL Editor
- **Qué debe aparecer:** La definición SQL de la vista `product_promotions_with_status` o `active_product_promotions` mostrando la evaluación de fechas con `now()`.
- **Qué demuestra:** Que el estado de las promociones se calcula en el servidor y no depende del reloj del teléfono móvil.
- **Título sugerido:** *Figura 4.5. Definición SQL de la vista de promociones activas calculadas por el servidor.*
- **Datos a ocultar / censurar:** Ninguno.

---

## Captura 6: Funciones RPC Desplegadas (PL/pgSQL)
- **Sección del panel:** Database -> Functions
- **Qué debe aparecer:** Lista de funciones RPC en el esquema `public`, destacando `process_cart_checkout`, `process_cart_quote` y `handle_new_user`.
- **Qué demuestra:** La existencia de procedimientos almacenados en la base de datos para la lógica transaccional.
- **Título sugerido:** *Figura 4.6. Funciones almacenadas RPC para el procesamiento transaccional de compras y cotizaciones.*
- **Datos a ocultar / censurar:** Ninguno.

---

## Captura 7: Código de la Función RPC `process_cart_checkout`
- **Sección del panel:** SQL Editor o Database -> Functions -> Edit `process_cart_checkout`
- **Qué debe aparecer:** La sección de código PL/pgSQL donde se inserta el movimiento de egreso en `inventory_movements` para el descuento automático de stock.
- **Qué demuestra:** El descuento real de inventario y generación automática de la orden de compra al completar el checkout.
- **Título sugerido:** *Figura 4.7. Código fuente PL/pgSQL de la función transaccional de checkout y descuento de stock.*
- **Datos a ocultar / censurar:** Ninguno.

---

## Captura 8: Buckets de Almacenamiento (Supabase Storage)
- **Sección del panel:** Storage -> Buckets
- **Qué debe aparecer:** Lista de buckets (`product-media`, `promotion-assets`, `review-assets`, `ticket-attachments`, `product-documents`) con su etiqueta `Public` o `Private`.
- **Qué demuestra:** La organización de archivos multimedia, fichas técnicas y adjuntos de soporte técnico.
- **Título sugerido:** *Figura 4.8. Configuración de buckets de almacenamiento para la aplicación Go Medical.*
- **Datos a ocultar / censurar:** Nombres o rutas que contengan información sensible de pruebas reales.

---

## Captura 9: Configuración de Realtime en Tablas
- **Sección del panel:** Database -> Publications / Realtime
- **Qué debe aparecer:** La publicación `supabase_realtime` mostrando las tablas habilitadas (`notifications`, `service_ticket_messages`).
- **Qué demuestra:** La infraestructura habilitada para recibir eventos en vivo en la aplicación móvil.
- **Título sugerido:** *Figura 4.9. Tablas asociadas a la publicación de eventos en tiempo real (Realtime).*
- **Datos a ocultar / censurar:** Ninguno.

---

## Captura 10: Edge Function de Mercado Pago (`create-mp-test-preference`)
- **Sección del panel:** Edge Functions
- **Qué debe aparecer:** Nombre de la función `create-mp-test-preference`, estado `ACTIVE`, indicador `JWT Verification Enabled` y contador de invocaciones.
- **Qué demuestra:** La ejecución de código serverless seguro para comunicarse con la API de Mercado Pago sin exponer tokens en la app móvil.
- **Título sugerido:** *Figura 4.10. Despliegue de la función Edge serverless para la generación de preferencias de pago.*
- **Datos a ocultar / censurar:** Censurar la URL completa del endpoint de la Edge Function.

---

## Captura 11: Logs de Invocación Exitosa de Edge Function
- **Sección del panel:** Edge Functions -> `create-mp-test-preference` -> Logs
- **Qué debe aparecer:** Registro de peticiones HTTP POST recibidas con código de respuesta `200 OK`.
- **Qué demuestra:** El funcionamiento operativo de la comunicación entre la app móvil Flutter y la Edge Function en Supabase.
- **Título sugerido:** *Figura 4.11. Historial de logs de ejecución exitosa en la Edge Function de pruebas de pago.*
- **Datos a ocultar / censurar:** Ocultar direcciones IP de origen y tokens de autorización.

---

## Captura 12: Triggers Automáticos de Notificaciones
- **Sección del panel:** Database -> Triggers
- **Qué debe aparecer:** Lista de disparadores como `trg_notify_client_on_ticket_status_change` y `trg_notify_client_on_question_answered`.
- **Qué demuestra:** La automatización en PostgreSQL para generar notificaciones internas ante eventos en el sistema.
- **Título sugerido:** *Figura 4.12. Disparadores automáticos en la base de datos para la generación de notificaciones.*
- **Datos a ocultar / censurar:** Ninguno.

---

## Captura 13: Ejemplo de Registro de Pedido / Cotización de Prueba
- **Sección del panel:** Table Editor -> `orders` o `quotes`
- **Qué debe aparecer:** Filas con folios generados (`ORD-xxx` o `COT-xxx`), subtotales, IVA y estado.
- **Qué demuestra:** La persistencia estructurada de compras y solicitudes emitidas desde la aplicación móvil.
- **Título sugerido:** *Figura 4.13. Registro de compras y cotizaciones procesadas en la base de datos.*
- **Datos a ocultar / censurar:** Ocultar nombres de clientes reales y correos de prueba.

---

## Captura 14: Ejemplo de Ticket de Mantenimiento Biomédico y Mensajes
- **Sección del panel:** Table Editor -> `service_tickets` y `service_ticket_messages`
- **Qué debe aparecer:** Registro de un ticket con tipo (`preventivo` o `correctivo`), prioridad, descripción y mensajes asociados.
- **Qué demuestra:** La integración del módulo de soporte biomédico en la base de datos.
- **Título sugerido:** *Figura 4.14. Estructura de tickets de soporte y mensajes de seguimiento biomédico.*
- **Datos a ocultar / censurar:** Ocultar nombres reales de personal o clientes en los mensajes de prueba.
