# 📋 Checklist Auditoriado y Actualizado del Proyecto Go Medical

Este documento integra y valida el estado **real y verificado** del desarrollo entre la **Plataforma Web Administrativa (Angular)**, la **Aplicación Móvil (Flutter)**, la **Base de Datos y Backend (Supabase PostgreSQL + Edge Functions)** y la **Pasarela de Pagos (Mercado Pago Checkout Pro)**.

---

## 1. Base de Datos y Supabase (Backend & Serverless)

### ✅ Terminado y Verificado
- [x] Creación y organización de la base de datos PostgreSQL en Supabase.
- [x] Configuración de autenticación de usuarios (Email / Password y Verificación por OTP).
- [x] Relación entre perfiles de usuarios (`profiles`) y clientes (`clients`).
- [x] Estructura de catálogo de productos (`products`).
- [x] Estructura de imágenes, características, especificaciones y documentos de productos.
- [x] Estructura de inventario físico, reservas de inventario e historial de movimientos (`inventory_reservations`, `inventory_movements`).
- [x] Vista de disponibilidad en tiempo real: stock físico, reservado y disponible.
- [x] Estructura de pedidos (`orders`) y partidas del pedido (`order_items`).
- [x] Estructura de registro de pagos (`order_payments`) con soporte para `payment_id`, `external_reference`, `provider_status`, `status_detail`, `environment`, `live_mode` y `last_webhook_at`.
- [x] Estructura de cotizaciones (`quotations`) y partidas de cotización.
- [x] Estructura de preguntas y respuestas (`product_questions`) y reseñas (`product_reviews`).
- [x] Estructura de tickets de servicio técnico (`support_tickets`) y adjuntos.
- [x] Estructura de oportunidades comerciales (`opportunities`).
- [x] Estructura de cupones (`coupons`) y registro de canjes (`coupon_redemptions`).
- [x] Estructura de categorías y subcategorías con relaciones por `category_id` y `subcategory_id`.
- [x] Estructura de devoluciones y retrocompatibilidad con esquemas heredados.
- [x] Estructura de banners y creativos promocionales (`promotions`).
- [x] Políticas de Seguridad por Fila (RLS) principales en todas las tablas del esquema `public`.
- [x] Restricción de RLS en `orders` para evitar que usuarios clientes modifiquen `payment_status`, `paid_at` o `payment_id` directamente por REST.
- [x] Protección de documentos y archivos privados en Supabase Storage (Buckets de archivos y promociones).
- [x] Funciones atómicas (RPC) para preguntas, inventario, pedidos y reservas atómicas (`process_cart_checkout`, `process_cart_quote`, `get_my_client_id`).
- [x] Función atómica SQL de conciliación `public.reconcile_mercado_pago_payment` con `SECURITY DEFINER`, `search_path = public, pg_temp`, bloqueo `FOR UPDATE` e idempotencia de pagos aprobados.
- [x] Índices de rendimiento e idempotencia en PostgreSQL (`idx_order_payments_order_id`, `idx_order_payments_external_reference`, `idx_order_payments_payment_id_unique`).
- [x] Despliegue de Edge Functions en Deno/TypeScript:
  - `create-mp-order-preference` (Generación de preferencia de pago).
  - `mercado-pago-webhook` (Recepción y verificación HMAC-SHA256 de notificaciones; `verify_jwt: false`, Versión 18 ACTIVA).
  - `verify-mp-order-payment` (Verificación manual por `order_id` con autenticación JWT; `verify_jwt: true`, Versión 1 ACTIVA).
- [x] Configuración de Secretos Globales de Supabase (`MERCADO_PAGO_ACCESS_TOKEN`, `MERCADO_PAGO_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`).

### 🔍 Pendiente de Validación / Afinado Final
- [ ] Probar todas las políticas RLS con una cuenta sin permisos (rol público anon).
- [ ] Confirmar apertura fluida de documentos privados mediante URLs firmadas desde la App móvil.
- [ ] Prueba de concurrencia real simulando 2 compras simultáneas del último producto en stock sin sobreventa ni deducción doble.

---

## 2. Aplicación Móvil (Flutter)

### ✅ Terminado y Funcionando
- [x] Proyecto estructurado en Flutter con arquitectura modular (`clean architecture` / servicios desacoplados).
- [x] Módulo de Autenticación completo: Login, Registro de usuario y Verificación de código OTP.
- [x] Navegación principal con barra inferior curva personalizada (`BottomNavigationBar`).
- [x] Pantalla de Inicio (`Home`) con productos destacados, ofertas y catálogo.
- [x] Módulo de Categorías y Subcategorías con fallbacks de imágenes.
- [x] Catálogo de productos con filtros y búsqueda.
- [x] Pantalla de Detalle del Producto (Imágenes, precio, stock en tiempo real, especificaciones y características).
- [x] Sistema de Preguntas y Respuestas interactivo en la ficha del producto.
- [x] Sistema de Reseñas de productos.
- [x] Carrito de Compras móvil: Agregar/eliminar productos, modificar cantidades, cálculo de subtotales, IVA y total.
- [x] Perfil de Usuario con persistencia de sesión y actualización de datos de cuenta.
- [x] Módulo de Historial de Pedidos ("Mis Compras" / `orders_screen.dart` y `order_detail_screen.dart`) tipo Mercado Libre con estados y detalle de compra.
- [x] Lectura de documentos técnicos mediante URLs firmadas de Supabase Storage.
- [x] Integración del flujo de apertura del Checkout de Mercado Pago mediante Deep Links (`gomedical://payment/...`) y validación estricta de dominios (`validateCheckoutUri`).
- [x] Integración del servicio de verificación `verifyOrderPayment(String orderId)` invocando `verify-mp-order-payment` enviando únicamente `order_id` con el JWT del usuario autenticado.
- [x] Pantalla de resultado del pago (`PaymentResultScreen`) con secuencia de polling automático (0s, 2s, 5s, 10s), botón *"Verificar nuevamente"* con bandera de concurrencia (`_checking`), limpieza de timers en `dispose()` y estados reactivos (`confirmed`, `pending`, `failed`).
- [x] Visualización del pedido como **PAGADO** en la aplicación móvil tras confirmación del servidor.
- [x] Verificación estática con `flutter analyze` (**0 errores, 0 advertencias**) y suite de unit tests (50/50 pruebas pasadas).

### 🟡 En Proceso / Integración Final
- [ ] Visualización del banner promocional administrado desde la web en la Home móvil.
- [ ] Entrada y validación de Cupones de descuento directamente en la pantalla de carrito móvil.
- [ ] Prueba de comportamiento con la aplicación nativa de Mercado Pago instalada vs. navegador integrado en iOS y Android.

### 🔍 Pendiente / Próximas Mejoras
- [ ] Rastreo/Seguimiento en tiempo real del estado del pedido (Envío / Logística).
- [ ] Compilación y pruebas finales en APK / Bundle de Android e iOS en modo Release.

---

## 3. Método de Pago (Mercado Pago Checkout Pro)

### ✅ Terminado y Verificado
- [x] Definición del modelo de integración: **Checkout Pro**.
- [x] Creación de App en Mercado Pago Developers (`gomedical_prueba`).
- [x] Configuración de credenciales de prueba Sandbox (`APP_USR-...`).
- [x] Desarrollo y despliegue de Edge Function `create-mp-order-preference` (Generación de preferencia de pago).
- [x] Desarrollo y despliegue de Edge Function `mercado-pago-webhook` (Recepción, validación de firma HMAC-SHA256 `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` y consulta a API de Mercado Pago).
- [x] Desarrollo y despliegue de Edge Function `verify-mp-order-payment` (Verificación manual por `order_id` autenticada con JWT).
- [x] Configuración de URLs de retorno (`success`, `pending`, `failure`) vinculadas al esquema `gomedical://`.
- [x] Recepción pública del webhook verificada desde Mercado Pago Developers con respuesta `HTTP 200 OK`.
- [x] Coincidencia de `MERCADO_PAGO_WEBHOOK_SECRET` y validación de notificaciones oficiales firmadas con HMAC-SHA256.
- [x] Rechazo de solicitudes no autorizadas o falsas sin firma válida (`HTTP 401 Unauthorized` / `{"error":"invalid_signature"}`), impidiendo conciliaciones no verificadas.
- [x] Conciliación automática del pago verificada en logs (`payment_id: 170982196423`, `environment: test`, `live_mode: true`, `provider_status: approved`, `status_detail: accredited`, `order_number: ORD-20260803-809B2BBB`, `total: 4060.00 MXN`).
- [x] Actualización automática del pedido en PostgreSQL: `orders.status = 'paid'`, `orders.payment_status = 'approved'`, registro de `paid_at` y `last_webhook_at`.
- [x] Persistencia garantizada de `payment_id`, `external_reference`, `amount` y `currency_id`.
- [x] Idempotencia en Base de Datos verificada mediante consulta SQL de duplicados (`Success. No rows returned`), asegurando que no existen registros duplicados en `order_payments`.
- [x] Verificación técnica del flujo completo de extremo a extremo: Flutter → preferencia → Checkout Pro → pago aprobado → Webhook HMAC-SHA256 → conciliación en PostgreSQL → actualización de pedido → estado **PAGADO** en la App.
- [x] Protección de secretos: Ningún Access Token ni Webhook Secret está presente en Flutter, Git ni archivos versionados.

### 🟡 En Proceso
- [ ] Confirmar la etapa de integración en el panel de Mercado Pago Developers (avanzar del 13% en el checklist de Mercado Pago).
- [ ] Pruebas completas de flujos secundarios (pagos rechazados y pagos pendientes en sandbox).

### ⏸ Bloqueado temporalmente por dependencia externa

El pase a producción de Mercado Pago se realizará cuando la empresa proporcione la nueva cuenta comercial que se utilizará oficialmente para recibir los pagos. La integración técnica ya se encuentra validada en el entorno de pruebas Sandbox, por lo que esta etapa no está detenida por errores de desarrollo, sino por la falta de acceso a las credenciales productivas definitivas.

- [ ] Recibir acceso a la nueva cuenta oficial de Mercado Pago de Go Medical.
- [ ] Crear o vincular la aplicación productiva de Mercado Pago en la nueva cuenta.
- [ ] Obtener las credenciales productivas definitivas.
- [ ] Sustituir `MERCADO_PAGO_ACCESS_TOKEN` de prueba por el Access Token productivo en los Secrets de Supabase.
- [ ] Configurar la URL del webhook dentro del apartado **Modo productivo** de Mercado Pago Developers.
- [ ] Copiar la nueva clave secreta del webhook productivo al Secret `MERCADO_PAGO_WEBHOOK_SECRET`.
- [ ] Cambiar `MERCADO_PAGO_ENV` de `test` a `production`, si esta variable continúa siendo utilizada por las Edge Functions.
- [ ] Verificar que `create-mp-order-preference`, `mercado-pago-webhook` y `verify-mp-order-payment` utilicen las credenciales del mismo entorno.
- [ ] Desplegar nuevamente las Edge Functions después de actualizar las credenciales y la configuración productiva, si es necesario.
- [ ] Ejecutar una compra real controlada con un producto o monto pequeño.
- [ ] Confirmar que el pago real actualice correctamente `order_payments`.
- [ ] Confirmar que el pago real actualice `orders.payment_status`, `orders.status` y `orders.paid_at`.
- [ ] Confirmar que la aplicación móvil muestre el pedido productivo como **PAGADO**.
- [ ] Realizar un reembolso controlado para validar el flujo productivo de devolución.
- [ ] Rotar las credenciales de prueba que hayan quedado expuestas en capturas anteriores.

> **Estado actual de Mercado Pago:** Integración Sandbox terminada y validada de extremo a extremo. La creación de preferencias, Checkout Pro, firma HMAC-SHA256, webhook, conciliación idempotente, actualización automática del pedido y rechazo de solicitudes falsas funcionan correctamente. El pase a producción permanece bloqueado únicamente hasta recibir la cuenta oficial y las credenciales productivas.

---

## 4. Plataforma Web Administrativa (Angular)

### ✅ Terminado y Funcionando
- [x] Inicio de sesión, recuperación de contraseña y persistencia de sesión.
- [x] Protección de rutas mediante Guards de seguridad.
- [x] Layout principal: Sidebar responsivo, Topbar y componentes compartidos.
- [x] Módulo Dashboard con indicadores generales.
- [x] Módulo de Productos: Listado, creación, edición, activación, imágenes, especificaciones, características y documentos.
- [x] Módulo de Categorías y Subcategorías con asignación de imágenes.
- [x] Módulo de Inventario: Stock físico, reservado, disponible y ajustes atómicos.
- [x] Módulo de Cupones: Creación, vigencia, porcentajes, montos mínimos y reglas de inclusión/exclusión.
- [x] Módulo de Banners y promociones visuales.
- [x] Módulo de Cotizaciones: Creación, edición, cálculo de impuestos y generación de PDF corporativo.
- [x] Módulo de Tickets de Servicio Técnico e interacción con clientes.
- [x] Módulo de Devoluciones y seguimiento de solicitudes.
- [x] Despliegue automático en Firebase Hosting (`https://gomedical-8983c.web.app`).

### 🔍 Pendiente / Próximas Integraciones
- [ ] Visualización administrativa detallada del estado de pago, `payment_id` y `external_reference` en el módulo de pedidos.
- [ ] Botón de reembolso directo desde el panel administrativo conectado a Mercado Pago API.
- [ ] Confirmar sincronización de banners publicados en la web hacia la App móvil.
- [ ] Probar flujo completo de aprobación de devolución e impacto en stock físico desde la Web.
- [ ] Conversión formal de cotización aprobada a pedido final desde el panel.

---

## 5. Resumen del Estado Global del Proyecto

| Área del Proyecto | Estado Anterior | Estado Actual | Progreso |
| :--- | :--- | :--- | :---: |
| **Base de Datos & Supabase** | 95% | **Completo y Operativo (RPC de reconciliación e índices activos)** | **98%** |
| **Plataforma Web Admin (Angular)** | 90% | Desarrollado y Desplegado en Firebase | **90%** |
| **Aplicación Móvil (Flutter)** | 85% | **Flujo de pago, polling y estado PAGADO verificado** | **92%** |
| **Integración Mercado Pago** | 80% | **Integración Sandbox terminada y verificada. Producción bloqueada temporalmente hasta recibir la nueva cuenta oficial de Mercado Pago.** | **90% técnico / producción pendiente** |
| **Pruebas de Extremo a Extremo** | 75% | **Flujo Sandbox probado correctamente. Prueba productiva pendiente por falta de credenciales de la nueva cuenta oficial.** | **88%** |

---

> 💡 **Nota Técnica de Seguridad:** La arquitectura aplica medidas de seguridad importantes: los Access Tokens y las claves del webhook se almacenan en Supabase Secrets y son utilizados únicamente por las Edge Functions. La aplicación Flutter emplea exclusivamente credenciales públicas de Supabase. Antes de la salida a producción todavía deben completarse las pruebas de RLS, concurrencia, rotación de credenciales de prueba, validación de pagos secundarios y pruebas finales del entorno Release.
