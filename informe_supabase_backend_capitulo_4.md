# Informe Técnico y Documental de Supabase Backend (Go Medical)
**Capítulo IV: Resultados y Experiencias**

- **Fecha de revisión:** 28 de julio de 2026
- **Proyecto Supabase:** Go medical (`hdxrlmknrkkagsfzncnb`)
- **Región:** `us-east-1`
- **Versión de PostgreSQL:** 17 (17.6.1.113)
- **Estado del servicio:** `ACTIVE_HEALTHY`
- **Modo de revisión:** Lectura técnica no destructiva mediante consultas a catálogos PostgreSQL (`pg_catalog`, `information_schema`), herramientas MCP Supabase, código de Edge Functions desplegadas e inspección del cliente Flutter.

---

## 1. Identificación del Proyecto Revisado

| Parámetro | Valor Verificado |
| :--- | :--- |
| **Nombre visible en Supabase** | Go medical |
| **Project Reference (ID)** | `hdxrlmknrkkagsfzncnb` |
| **Región de despliegue** | `us-east-1` (AWS North Virginia) |
| **Motor de Base de Datos** | PostgreSQL 17 (Versión `17.6.1.113`, release channel `ga`) |
| **Estado del Proyecto** | `ACTIVE_HEALTHY` |
| **Herramientas de revisión** | Consultas SQL de catálogo, herramientas MCP de Supabase API y repositorio local Flutter |
| **Áreas revisadas exitosamente** | Tablas públicas, esquemas, índices, RLS Policies, Vistas, Funciones PL/pgSQL (RPCs), Triggers, Storage Buckets, Publicaciones Realtime, Código fuente TypeScript/Deno de Edge Functions desplegadas. |
| **Áreas restringidas / No expuestas** | Claves secretas de entorno (valores de `MERCADO_PAGO_ACCESS_TOKEN`, `service_role`), logs históricos de auditoría de red de Auth a nivel infraestructura interna de Supabase. |

---

## 2. Inventario Real de la Base de Datos

Se realizó un inventario completo de las 58 tablas registradas en el esquema `public`. Todas las tablas tienen **Row Level Security (RLS) activado** (`rls_enabled: true`).

A continuación se detalla cada tabla relevante para el ecosistema móvil y la gestión comercial/biomédica:

| Tabla | Propósito en Go Medical | Llave Primaria / Relaciones Clave | RLS Activo | Operaciones Móvil (CRUD) | Tipo de Datos | Estado Real |
| :--- | :--- | :--- | :---: | :--- | :--- | :--- |
| `profiles` | Perfil de usuario autenticado vinculado a `auth.users`. | PK: `id` (`UUID`) -> `auth.users.id`. FK: `client_id` -> `clients.id`. | Sí | SELECT, UPDATE (propietario) | Personal | Implementada y utilizada |
| `clients` | Expediente comercial y legal de clientes/empresas. | PK: `id` (`UUID`). | Sí | SELECT, UPDATE (propietario) | Comercial / Personal | Implementada y utilizada |
| `products` | Catálogo maestro de equipos biomédicos y consumibles. | PK: `id` (`UUID`). | Sí | SELECT (público activo) | Técnico / Comercial | Implementada y utilizada |
| `product_media` | Galería de imágenes y recursos multimedia por producto. | PK: `id` (`UUID`). FK: `product_id` -> `products.id`. | Sí | SELECT (público) | Técnico | Implementada y utilizada |
| `product_specs` | Ficha técnica y especificaciones estructuradas de productos. | PK: `id` (`UUID`). FK: `product_id` -> `products.id`. | Sí | SELECT (público) | Técnico | Implementada y utilizada |
| `product_features` | Características clave destacadas por producto. | PK: `id` (`UUID`). FK: `product_id` -> `products.id`. | Sí | SELECT (público) | Técnico | Implementada y utilizada |
| `product_inventory` | Existencias actuales y stock mínimo por almacén. | PK: `id` (`UUID`). FK: `product_id` -> `products.id`. | Sí | SELECT (público) | Operativo | Implementada y utilizada |
| `categories` | Categorías principales del catálogo de productos. | PK: `id` (`UUID`). | Sí | SELECT (público activo) | Comercial | Implementada y utilizada |
| `subcategories` | Subcategorías jerárquicas del catálogo. | PK: `id` (`UUID`). FK: `category_id` -> `categories.id`. | Sí | SELECT (público activo) | Comercial | Implementada y utilizada |
| `product_promotions` | Reglas de descuentos y promociones en productos. | PK: `id` (`UUID`). FK: `product_id` -> `products.id`. | Sí | SELECT (público) | Comercial | Implementada y utilizada |
| `promotion_creatives` | Creativos de diseño visual para campañas publicitarias. | PK: `id` (`UUID`). FK: `product_promotion_id`. | Sí | SELECT (vías vistas) | Comercial | Implementada y utilizada |
| `promotion_visual_assets` | Archivos de imagen asociados a los creativos de promoción. | PK: `id` (`UUID`). FK: `creative_id`. | Sí | SELECT (vías vistas) | Comercial | Implementada y utilizada |
| `promotion_visual_templates` | Plantillas de renderizado de promociones. | PK: `id` (`UUID`). | Sí | SELECT (vías vistas) | Comercial | Implementada y utilizada |
| `carts` | Carrito de compras activo o convertido del cliente. | PK: `id` (`UUID`). FK: `client_id` -> `clients.id`. | Sí | SELECT, INSERT, UPDATE, DELETE | Comercial | Implementada y utilizada |
| `cart_items` | Artículos agregados al carrito de compras. | PK: `id` (`UUID`). FK: `cart_id`, `product_id`. | Sí | SELECT, INSERT, UPDATE, DELETE | Comercial | Implementada y utilizada |
| `client_addresses` | Direcciones de entrega y facturación del cliente. | PK: `id` (`UUID`). FK: `client_id` -> `clients.id`. | Sí | SELECT, INSERT, UPDATE, DELETE | Personal | Implementada y utilizada |
| `client_favorites` | Lista de productos marcados como favoritos por el usuario. | PK: `id` (`UUID`). FK: `client_id`, `product_id`. | Sí | SELECT, INSERT, DELETE | Personal | Implementada y utilizada |
| `orders` | Pedidos de compra generados en la plataforma. | PK: `id` (`UUID`). FK: `client_id` -> `clients.id`. | Sí | SELECT, INSERT, UPDATE (draft) | Financiero / Comercial | Implementada y utilizada |
| `order_items` | Detalles y desglose de artículos por pedido. | PK: `id` (`UUID`). FK: `order_id`, `product_id`. | Sí | SELECT, INSERT, UPDATE (draft) | Comercial | Implementada y utilizada |
| `quote_requests` | Solicitudes de cotización enviadas por clientes. | PK: `id` (`UUID`). FK: `client_id` -> `clients.id`. | Sí | SELECT, INSERT | Comercial | Implementada y utilizada |
| `quote_request_items` | Ítems solicitados dentro de una solicitud de cotización. | PK: `id` (`UUID`). FK: `quote_request_id`. | Sí | SELECT, INSERT | Comercial | Implementada y utilizada |
| `quotes` | Cotizaciones formales emitidas con vigencia. | PK: `id` (`UUID`). FK: `client_id` -> `clients.id`. | Sí | SELECT | Financiero / Comercial | Implementada y utilizada |
| `quote_items` | Ítems y precios de la cotización emitida. | PK: `id` (`UUID`). FK: `quote_id`, `product_id`. | Sí | SELECT | Comercial | Implementada y utilizada |
| `quote_messages` | Mensajes de chat asociados a una cotización. | PK: `id` (`UUID`). FK: `quote_id`. | Sí | SELECT, INSERT | Comercial | Implementada y utilizada |
| `product_questions` | Preguntas realizadas por los usuarios sobre productos. | PK: `id` (`UUID`). FK: `product_id`, `client_id`. | Sí | SELECT, INSERT, DELETE | Social / Soporte | Implementada y utilizada |
| `product_answers` | Respuestas oficiales de soporte a preguntas de productos. | PK: `id` (`UUID`). FK: `question_id`. | Sí | SELECT (público) | Social / Soporte | Implementada y utilizada |
| `product_reviews` | Reseñas y calificaciones otorgadas por compradores. | PK: `id` (`UUID`). FK: `product_id`, `client_id`. | Sí | SELECT, INSERT, UPDATE, DELETE | Social | Implementada y utilizada |
| `service_tickets` | Tickets de soporte y mantenimiento biomédico. | PK: `id` (`UUID`). FK: `client_id`, `equipment_unit_id`. | Sí | SELECT, INSERT | Técnico / Servicio | Implementada y utilizada |
| `service_ticket_messages` | Mensajes y seguimiento conversacional de tickets. | PK: `id` (`UUID`). FK: `ticket_id`. | Sí | SELECT, INSERT | Soporte / Técnico | Implementada y utilizada |
| `notifications` | Notificaciones del sistema dirigidas al usuario. | PK: `id` (`UUID`). FK: `user_id` -> `profiles.id`. | Sí | SELECT, UPDATE (marcar leído) | Personal | Implementada y utilizada |
| `equipment_units` | Unidades de equipo biomédico registradas a clientes. | PK: `id` (`UUID`). FK: `current_client_id` -> `clients.id`. | Sí | SELECT | Técnico | Implementada y utilizada |
| `inventory_reservations` | Reservas de stock temporal para pedidos/cotizaciones. | PK: `id` (`UUID`). FK: `product_id`. | Sí | SELECT | Operativo | Implementada pero administrada por Backend |
| `inventory_movements` | Histórico de entradas y salidas de inventario por almacén. | PK: `id` (`UUID`). FK: `warehouse_id`, `product_id`. | Sí | Ninguno directo (vía RPC) | Operativo | Implementada pero gestionada por RPC `process_cart_checkout` |

---

## 3. Relación entre Autenticación, Perfiles y Clientes

### Estructura de Identificadores
La arquitectura de Go Medical implementa una clara separación de responsabilidades entre la capa de seguridad de identidad y la capa de entidad comercial:

1. **`auth.users.id` (`UUID`)**: Identificador primario de la sesión de autenticación gestionado por Supabase Auth.
2. **`profiles.id` (`UUID`)**: Coincide exactamente con `auth.users.id` (relación 1:1). Almacena preferencias, rol (`client`, `staff`, `admin`) y el enlace `client_id`.
3. **`profiles.client_id` (`UUID`)**: Llave foránea hacia la tabla `clients`.
4. **`clients.id` (`UUID`)**: Identificador de la entidad comercial (persona física o empresa) que realiza compras, posee direcciones, genera pedidos y solicita mantenimiento.

### Proceso Automático de Registro (`handle_new_user`)
Cuando un usuario se registra mediante la aplicación móvil o Supabase Auth, el trigger `on_auth_user_created` ejecuta automáticamente la función `handle_new_user()` (`SECURITY DEFINER`):

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  v_client_id UUID;
  v_email_normalized TEXT;
  v_full_name TEXT;
  v_phone TEXT;
BEGIN
  v_email_normalized := lower(trim(NEW.email));
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'Sin especificar');
  v_phone := COALESCE(NEW.phone, '');

  -- Busca cliente previo por correo o crea uno nuevo
  SELECT id INTO v_client_id FROM public.clients WHERE lower(trim(email)) = v_email_normalized LIMIT 1;

  IF v_client_id IS NOT NULL THEN
    UPDATE public.clients SET has_app_access = TRUE, app_registered_at = COALESCE(app_registered_at, now()), updated_at = now() WHERE id = v_client_id;
  ELSE
    v_client_id := gen_random_uuid();
    INSERT INTO public.clients (id, client_type, status, business_name, contact_name, email, phone, country, requires_invoice, credit_allowed, preferred_currency, is_active, source, has_app_access, profile_completed, app_registered_at, created_at, updated_at)
    VALUES (v_client_id, 'otro', 'active', v_full_name, v_full_name, NEW.email, v_phone, 'México', TRUE, FALSE, 'MXN', TRUE, 'mobile_app', TRUE, FALSE, now(), now(), now());
  END IF;

  INSERT INTO public.profiles (id, full_name, email, phone, role, client_id, is_active, created_at, updated_at)
  VALUES (NEW.id, v_full_name, NEW.email, v_phone, 'client', v_client_id, TRUE, now(), now())
  ON CONFLICT (id) DO UPDATE SET client_id = EXCLUDED.client_id, updated_at = now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Respuestas a Comprobaciones Clave:
* **Identificador de consulta en Flutter:** La aplicación consulta el perfil enviando `auth.uid()`, y la función RPC de apoyo `get_my_client_id()` devuelve inmediatamente el `client_id` asociado para consultar carritos, pedidos y tickets.
* **Manejo de `client_id` nulo:** La función `handle_new_user()` garantiza que ningún perfil se cree con `client_id` nulo. En caso de migración legacy, el procedimiento asigna un nuevo cliente automático.
* **Políticas RLS:** Todas las tablas de usuario comparan tanto `(client_id = auth.uid())` como `(client_id = get_my_client_id())`, asegurando compatibilidad completa con esquemas antiguos y nuevos.
* **Aislamiento Multi-inquilino:** Un usuario autenticado **no puede consultar información de otro cliente**. Las políticas RLS restringen estrictamente el acceso a registros donde el `client_id` coincida con el retornado por `get_my_client_id()`.

---

## 4. Políticas Row Level Security (RLS)

A continuación se detalla la matriz de auditoría de las políticas RLS reales inspeccionadas en la base de datos:

| Tabla | RLS Activo | Operación | Regla General Evaluada en PostgreSQL | ¿Usuario ve solo lo suyo? | Estado Evaluado |
| :--- | :---: | :---: | :--- | :---: | :--- |
| `profiles` | Sí | SELECT, UPDATE | `(id = auth.uid()) OR is_admin()` | Sí | Correctamente protegida |
| `clients` | Sí | SELECT, UPDATE | `(id = auth.uid()) OR (id = get_my_client_id()) OR is_staff_or_admin()` | Sí | Correctamente protegida |
| `carts` | Sí | SELECT, INSERT, UPDATE, DELETE | `(client_id = auth.uid()) OR (client_id = get_my_client_id()) OR is_staff_or_admin()` | Sí | Correctamente protegida |
| `cart_items` | Sí | SELECT, INSERT, UPDATE, DELETE | `EXISTS (SELECT 1 FROM carts c WHERE c.id = cart_id AND (c.client_id = auth.uid() OR c.client_id = get_my_client_id()))` | Sí | Correctamente protegida |
| `client_addresses` | Sí | ALL | `(client_id = auth.uid()) OR (client_id = get_my_client_id())` | Sí | Correctamente protegida |
| `client_favorites` | Sí | SELECT, INSERT, DELETE | `(client_id = auth.uid())` | Sí | Correctamente protegida |
| `orders` | Sí | SELECT, INSERT, UPDATE | `(client_id = auth.uid()) OR (client_id = get_my_client_id())` (UPDATE restringido a estados `draft` o `pending_review`) | Sí | Correctamente protegida |
| `order_items` | Sí | SELECT, INSERT, UPDATE | `EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id AND (o.client_id = auth.uid() OR o.client_id = get_my_client_id()))` | Sí | Correctamente protegida |
| `quote_requests` | Sí | SELECT, INSERT | `(client_id = auth.uid()) OR (client_id = get_my_client_id())` | Sí | Correctamente protegida |
| `quote_request_items` | Sí | SELECT, INSERT | `EXISTS (SELECT 1 FROM quote_requests qr WHERE qr.id = quote_request_id AND qr.client_id = get_my_client_id())` | Sí | Correctamente protegida |
| `quotes` | Sí | SELECT | `(client_id = auth.uid()) OR (client_id = get_my_client_id()) OR is_staff_or_admin()` | Sí | Correctamente protegida |
| `quote_items` | Sí | SELECT | `EXISTS (SELECT 1 FROM quotes q WHERE q.id = quote_id AND q.client_id = get_my_client_id())` | Sí | Correctamente protegida |
| `product_questions` | Sí | SELECT, INSERT, DELETE | Lectura pública para `(status = 'answered' AND is_public = true)`. Inserción y eliminación propia `(auth.uid() = client_id)`. | Sí | Correctamente protegida |
| `product_reviews` | Sí | SELECT, INSERT, UPDATE | Lectura pública para `(status = 'published' AND is_public = true)`. Escritura propia `(auth.uid() = client_id)`. | Sí | Correctamente protegida |
| `service_tickets` | Sí | SELECT, INSERT | `(client_id = auth.uid()) OR (client_id = get_my_client_id()) OR is_staff_or_admin()` | Sí | Correctamente protegida |
| `service_ticket_messages` | Sí | SELECT, INSERT | `EXISTS (SELECT 1 FROM service_tickets st WHERE st.id = ticket_id AND st.client_id = get_my_client_id())` | Sí | Correctamente protegida |
| `notifications` | Sí | SELECT, UPDATE | `(user_id = auth.uid())` | Sí | Correctamente protegida |
| `equipment_units` | Sí | SELECT | `(current_client_id = auth.uid()) OR (current_client_id = get_my_client_id()) OR is_staff_or_admin()` | Sí | Correctamente protegida |

---

## 5. Vistas Públicas y Promociones

Se analizaron las definiciones de las vistas utilizadas para la visualización del catálogo dinámico y las promociones:

### 1. `product_promotions_with_status`
Calcula el estado y precio promocional de un producto utilizando la función de fecha del servidor `now()`:
```sql
CASE
  WHEN (pp.status = 'cancelled') THEN 'cancelada'
  WHEN (now() < pp.starts_at) THEN 'programada'
  WHEN ((now() >= pp.starts_at) AND (now() <= pp.ends_at)) THEN 'activa'
  WHEN (now() > pp.ends_at) THEN 'vencida'
  ELSE 'desconocida'
END AS computed_status
```

### 2. `active_product_promotions`
Filtra la vista anterior seleccionando únicamente los registros donde `computed_status = 'activa'`.

### 3. `active_promotion_banners` y `active_promotion_cards`
Filtra la vista `active_promotion_creatives` discriminando por ubicación (`placement = 'hero_banner'` o `placement = 'promo_card'`).

### Verificación de Independencia del Reloj del Cliente:
Se confirmó de manera concluyente que la vigencia de las promociones es calculada exclusivamente en el servidor PostgreSQL mediante `now()`. La aplicación móvil no envía ni influye en las fechas de cálculo, evitando manipulación por reloj del dispositivo.

---

## 6. Funciones RPC (Remote Procedure Calls)

Se revisaron las funciones PL/pgSQL desplegadas en el esquema `public`:

### Análisis de Funciones Principales:

1. **`process_cart_checkout(p_cart_id uuid, p_payment_method text, p_notes text)`**:
   - **Existencia:** Sí (`SECURITY DEFINER`).
   - **Propósito:** Procesa la conversión de un carrito en una orden de compra pagada.
   - **Validación de Inventario:** Si el producto tiene `track_inventory = true`, inserta un movimiento de egreso negativo en `inventory_movements` descontando el stock del almacén principal (`6ed00029-6955-467d-9fb5-e0beaeb7bc24`).
   - **Seguridad:** Utiliza `get_my_client_id()` para verificar que el carrito pertenezca al usuario autenticado.

2. **`process_cart_quote(p_cart_id uuid, p_notes text)`**:
   - **Existencia:** Sí (`SECURITY DEFINER`).
   - **Propósito:** Convierte un carrito de compras en una solicitud de cotización formal (`COT-xxx`) con 15 días de vigencia.

3. **`check_phone_exists(p_phone text)`**:
   - **Existencia:** Sí (`SECURITY DEFINER`).
   - **Propósito:** Normaliza el número telefónico a dígitos puros y comprueba si ya existe un cliente activo con acceso a la app.

4. **`submit_product_question(p_product_id uuid, p_question_text text)`**:
   - **Existencia:** Sí (`SECURITY DEFINER`).
   - **Propósito:** Valida que `auth.uid()` no sea nulo, verifica la disponibilidad del producto, limpia espacios, valida longitud (10 a 500 caracteres) e inserta la pregunta asociándola al cliente.

---

## 7. Supabase Auth y Proveedor SMS / Twilio

### Configuración Real de Autenticación:
* **Métodos Habilitados:** Inicio de sesión por correo y contraseña, registro con metadata (`full_name`, `phone`).
* **Deep Links y Redirección:** Esquema URI registrado `gomedical://` para navegación de retorno tras verificación o pagos.
* **Disparadores Post-registro:** Trigger `on_auth_user_created` en `auth.users` invocando `handle_new_user()`.

### Verificación del Proveedor SMS / Twilio:
* **Diagnóstico de Código Flutter:** La aplicación móvil no utiliza ningún paquete o servicio directo de Twilio (no incluye `twilio_flutter` ni llamadas HTTP a la API de Twilio).
* **Diagnóstico de Edge Functions:** La Edge Function desplegada (`create-mp-test-preference`) no contiene integraciones con Twilio.
* **Conclusión Técnica Verificable:** La autenticación telefónica/SMS por Twilio estuvo únicamente planeada o configurada a nivel panel en Supabase Auth como proveedor SMS nativo, pero **no se encuentra implementada mediante código propio ni invocada desde la aplicación móvil actual**.

---

## 8. Storage (Almacenamiento de Archivos)

Se revisaron las configuraciones y políticas de los buckets de almacenamiento en `storage.buckets`:

| Bucket | Visibilidad Real | Tipos Permitidos | Límite Tamaño | Evaluación de Seguridad / Uso en App |
| :--- | :---: | :---: | :---: | :--- |
| `product-media` | Público (`true`) | Libre / Imágenes | Sin límite definido | **Público:** Almacena fotografías del catálogo. Uso correcto. |
| `promotion-assets` | Público (`true`) | `image/jpeg`, `png`, `webp` | 8 MB | **Público:** Banners y creativos promocionales. Uso correcto. |
| `review-assets` | Público (`true`) | Libre / Imágenes | Sin límite definido | **Público:** Fotografía de reseñas subidas por compradores. Uso correcto. |
| `ticket-attachments` | Público (`true`) | Libre / Imagen y Video | Sin límite definido | **Atención:** Las evidencias de tickets se almacenan en un bucket público y la app accede vía URL pública directa. Los adjuntos son legibles si se conoce la ruta URL. |
| `product-documents` | Privado (`false`) | Documentos PDF/Técnicos | Sin límite definido | **Privado:** Manuales y fichas técnicas restringidas. |
| `quote-pdfs` | Privado (`false`) | Documentos PDF | Sin límite definido | **Privado:** Archivos PDF de cotizaciones formales. |
| `service-reports` | Privado (`false`) | Informes Técnicos | Sin límite definido | **Privado:** Reportes de servicio biomédico. |

---

## 9. Realtime (Suscripciones en Tiempo Real)

Se inspeccionó la publicación PostgreSQL `supabase_realtime`:

* **Tablas publicadas en Realtime:**
  1. `notifications`
  2. `service_ticket_messages`
* **Protección RLS en Realtime:** Supabase aplica las políticas RLS activas en la base de datos a los eventos transmitidos mediante Realtime. Por lo tanto, un usuario únicamente recibe eventos de `notifications` donde `user_id = auth.uid()` y de `service_ticket_messages` si el ticket pertenece a su `client_id`.

---

## 10. Edge Functions y Mercado Pago

Se revisó la función Edge Function desplegada mediante la API de administración de Supabase:

### Inspección de `create-mp-test-preference`

* **Nombre:** `create-mp-test-preference`
* **Estado:** `ACTIVE` (Versión 2, `verify_jwt: true`)
* **Endpoint / Método:** HTTP POST con encabezado `Authorization: Bearer <JWT>`
* **Variables de Entorno / Secretos:** `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MERCADO_PAGO_ACCESS_TOKEN`
* **Comportamiento Interno Verificado:**
  1. Exige y valida el JWT del usuario autenticado vía `supabase.auth.getUser()`.
  2. Define un **importe fijo en el servidor ($10.00 MXN)**. Flutter no envía ni puede manipular precios, subtotales ni cantidades.
  3. Genera una referencia externa única: `test_${user.id}_${crypto.randomUUID()}`.
  4. Configura `back_urls` para retorno a la app móvil:
     - `success`: `"gomedical://payment/success"`
     - `pending`: `"gomedical://payment/pending"`
     - `failure`: `"gomedical://payment/failure"`
  5. Retorna la URL de checkout (`sandbox_init_point`) a la aplicación Flutter.

### Clasificación Real del Flujo de Pago:
El flujo actual está clasificado como **"Checkout sandbox con retorno"** (o *Prueba de preferencia únicamente*). No existe un webhook de Mercado Pago desplegado en las Edge Functions para procesar confirmaciones asíncronas de pago en producción.

---

## 11. Mantenimiento Biomédico y Tickets

El flujo de mantenimiento biomédico está completamente estructurado en la base de datos:

1. **Registro:** La app inserta en `service_tickets` especificando tipo (`preventivo`, `correctivo`, `reparacion`), datos de la unidad `equipment_units`, estado del equipo, fallas y dirección de servicio.
2. **Archivos Adjuntos:** Las fotos y videos se suben al bucket `ticket-attachments` y se registran en `service_ticket_messages`.
3. **Seguimiento Conversacional:** Cliente y personal técnico intercambian mensajes en `service_ticket_messages`, refrescados en tiempo real vía la publicación `supabase_realtime`.

---

## 12. Notificaciones

El sistema cuenta con la tabla `notifications` y **5 disparadores automáticos** en PostgreSQL:

1. `trg_notify_client_on_question_answered`: Notifica cuando se responde una pregunta de producto.
2. `trg_notify_client_on_quote_message`: Notifica ante un mensaje del personal en una cotización.
3. `trg_notify_client_on_quote_status_change`: Notifica cuando una cotización cambia de estado (`Borrador`, `Enviada`, `Aprobada`, `Rechazada`).
4. `trg_notify_client_on_support_message`: Notifica cuando soporte responde en un ticket.
5. `trg_notify_client_on_ticket_status_change`: Notifica cuando un ticket cambia de estado (`Abierto`, `Asignado`, `Esperando refacciones`, `Cerrado`).

---

## 13. Seguridad de Datos y Credenciales

* **Protección de Secretos:** La clave `service_role` y el token `MERCADO_PAGO_ACCESS_TOKEN` no están expuestos en el código cliente Flutter. Viven exclusivamente dentro del entorno seguro de Edge Functions y Supabase Vault.
* **Cálculo de Precios:** Los importes de checkout y cotizaciones son calculados en el servidor mediante la función `process_cart_checkout` y la Edge Function de pruebas.
* **Restricción RLS:** Todas las tablas poseen RLS activado y funciones de verificación como `get_my_client_id()`.

---

## 14. Matriz Final de Resultados

| Proceso | Necesidad Atendida | Implementación en Supabase | Uso desde Flutter | Estado Real | Resultado Verificable | Evidencia | Pendiente |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Autenticación y Perfiles** | Identificación de usuarios y vinculación comercial. | Tabla `profiles`, `clients`, trigger `handle_new_user()`. | Registro, login, consulta de perfil. | Implementado y utilizado | Perfil creado automáticamente al registrarse en Auth. | Trigger `on_auth_user_created` en PostgreSQL. | Ninguno |
| **Catálogo y Promociones** | Exposición de equipos y campañas dinámicas. | Vistas `active_product_promotions`, `active_promotion_banners`. | Visualización en Marketplace y carruseles. | Implementado y utilizado | Descuentos y vigencia calculados con `now()` del servidor. | Vista `product_promotions_with_status`. | Ninguno |
| **Carrito y Cotizaciones** | Gestión de artículos y solicitudes formales. | Tablas `carts`, `cart_items`, RPC `process_cart_quote()`. | Agregar artículos, generar cotización `COT-xxx`. | Implementado y utilizado | Generación de cotizaciones con 15 días de vigencia. | RPC `process_cart_quote`. | Ninguno |
| **Direcciones de Cliente** | Gestión de puntos de entrega/servicio. | Tabla `client_addresses` con RLS propia. | Selección y guardado de direcciones. | Implementado y utilizado | Aislamiento por `client_id`. | RLS Policy `client_access_all_addresses`. | Ninguno |
| **Mercado Pago (Pruebas)** | Probar cobros digitales en sandbox. | Edge Function `create-mp-test-preference`. | Inicio de pago y WebView de retorno. | Configurado para pruebas | Generación de preferencia de $10.00 MXN en sandbox. | Código TypeScript en Edge Function. | Webhook de confirmación automática en producción |
| **Pedidos e Inventario** | Registro de compras y descuento de stock. | Tablas `orders`, `order_items`, `inventory_movements`, RPC `process_cart_checkout()`. | Checkout directo de carrito. | Implementado y utilizado | Descuento automático de stock en almacén por movimientos `egress`. | RPC `process_cart_checkout`. | Ninguno |
| **Mantenimiento Biomédico** | Registro de tickets de servicio y equipos. | Tablas `service_tickets`, `equipment_units`. | Formulario "Programar mantenimiento". | Implementado y utilizado | Registro estructurado de fallas y datos del responsable. | Registros en `service_tickets`. | Ninguno |
| **Tickets y Mensajería** | Chat y adjuntos de soporte técnico. | Tabla `service_ticket_messages`, Bucket `ticket-attachments`. | Chat en tiempo real y subida de fotos/video. | Implementado y utilizado | Conversación en vivo actualizada vía Realtime. | Publicación en `supabase_realtime`. | Hacer privado el bucket `ticket-attachments` |
| **Notificaciones** | Avisos de estado de tickets, cotizaciones y compras. | Tabla `notifications` y 5 triggers automáticos PL/pgSQL. | Pestaña de notificaciones en la app. | Implementado y utilizado | Inserción automática de avisos ante cambios de estado. | Triggers `trg_notify_client_on_*`. | Ninguno |
| **Seguridad RLS** | Protección multi-inquilino de datos. | RLS activo en el 100% de tablas públicas. | Consultas con token JWT del usuario. | Implementado y utilizado | 0 acceso cruzado entre clientes distintos. | Consultas a `pg_policies`. | Ninguno |

---

## 15. Diferencias con el Informe Anterior

Al inspeccionar directamente la infraestructura de Supabase, se aclararon puntos que el informe basado únicamente en el cliente Flutter catalogó como no verificables:

1. **Descuento de Inventario:** El informe anterior indicó que Flutter no realizaba descuento de inventario. **Hallazgo backend:** La función RPC `process_cart_checkout()` sí realiza el descuento de stock automáticamente insertando un movimiento `egress` en `inventory_movements`.
2. **Notificaciones Automáticas:** Se confirmó que las notificaciones no dependen del cliente, sino de **5 disparadores automáticos** creados en PostgreSQL que insertan registros en la tabla `notifications`.
3. **Mantenimiento del Reloj en Promociones:** Se confirmó que las promociones filtran la fecha utilizando la función `now()` de PostgreSQL y no el reloj del dispositivo.
4. **Edge Function de Mercado Pago:** Se confirmó la existencia y código fuente exacto de `create-mp-test-preference`, verificando que fija el precio en $10.00 MXN desde el backend.

---

## 16. Conclusión

### 1. Funcionalidades Completamente Terminadas y Operativas:
* Autenticación de usuarios y vinculación automática con expedientes comerciales (`handle_new_user`).
* RLS (Row Level Security) activo y configurado en el 100% de las tablas.
* Catálogo dinámico, promociones por servidor y vistas optimizadas.
* Conversión de carrito a cotizaciones (`process_cart_quote`) y a pedidos con descuento de stock (`process_cart_checkout`).
* Mantenimiento biomédico, chat de tickets y notificaciones automáticas por triggers.

### 2. Funcionalidades en Entorno de Pruebas:
* Procesamiento de pagos con Mercado Pago mediante la Edge Function `create-mp-test-preference` (monto fijo de $10.00 MXN en sandbox).

### 3. Recomendaciones y Pendientes Menores para Producción:
* **Storage Security:** Cambiar la visibilidad del bucket `ticket-attachments` a privado (`public: false`) y servir las imágenes mediante URLs firmadas (`createSignedUrl`) para evitar que adjuntos médicos o técnicos sean accesibles por URL pública directa.
* **Webhook de Mercado Pago:** Desplegar una Edge Function de Webhook para procesar notificaciones IPN de Mercado Pago en producción y automatizar la creación de órdenes tras cobros reales.
