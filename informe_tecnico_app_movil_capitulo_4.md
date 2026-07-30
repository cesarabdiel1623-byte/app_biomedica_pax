# Informe técnico de la aplicación móvil Go Medical

**Fecha de revisión:** 28 de julio de 2026  
**Alcance:** repositorio Flutter disponible en `C:\Users\cesar\Downloads\Go medical`  
**Propósito:** evidencia técnica para el capítulo 4 y diagnóstico del estado real de la aplicación.

## 0. Criterio y límites de la revisión

Este informe se basa exclusivamente en los archivos presentes en el repositorio
actual. Se inspeccionó el código Flutter, la configuración, las pruebas y el
historial Git. También se ejecutaron de forma no destructiva `flutter analyze`
y `flutter test`.

No se modificó código de la aplicación, no se ejecutaron migraciones y no se
realizaron operaciones de escritura en Supabase. Por lo tanto:

- La existencia de una consulta en Flutter no demuestra por sí sola que la
  tabla, vista, función, política RLS o bucket desplegado tenga la configuración
  correcta.
- El repositorio no contiene una carpeta `supabase/migrations` ni el código de
  la Edge Function desplegada. No es posible auditar desde aquí su lógica
  interna o el esquema completo de producción.
- Los resultados de RLS, webhooks y funciones desplegadas deben verificarse
  directamente en el proyecto de Supabase o en su repositorio privado.
- No se incluyen credenciales, tokens, claves ni URLs privadas.

## 1. Estructura real del proyecto

### 1.1 Pantallas

```text
lib/screens/
├── auth/
│   ├── login_screen.dart
│   ├── otp_verification_screen.dart
│   ├── register_screen.dart
│   └── registration_flow/
│       ├── registration_checklist_screen.dart
│       ├── step_1_email.dart
│       ├── step_1_otp.dart
│       ├── step_2_name.dart
│       ├── step_3_phone.dart
│       └── step_4_password.dart
├── home/
│   ├── address_picker_screen.dart
│   ├── home_screen.dart
│   ├── tabs/
│   │   ├── cart_tab.dart
│   │   ├── categories_tab.dart
│   │   ├── marketplace_tab.dart
│   │   └── profile_tab.dart
│   └── widgets/
│       ├── abandoned_cart_dialog.dart
│       ├── banner_carousel.dart
│       ├── checkout_sheet.dart
│       ├── product_card.dart
│       ├── promotion_cards_section.dart
│       ├── promotion_navigation.dart
│       ├── quote_request_sheet.dart
│       ├── scale_press_button.dart
│       ├── shimmer_card.dart
│       └── staggered_fade_slide.dart
├── payment/
│   └── payment_result_screen.dart
├── product/
│   ├── all_questions_screen.dart
│   ├── all_reviews_screen.dart
│   ├── ask_question_screen.dart
│   ├── category_catalog_screen.dart
│   ├── category_products_screen.dart
│   ├── favorites_screen.dart
│   ├── manage_history_screen.dart
│   ├── product_detail_screen.dart
│   ├── promotion_products_screen.dart
│   ├── quote_cart_screen.dart
│   ├── recently_viewed_screen.dart
│   ├── search_screen.dart
│   ├── single_question_screen.dart
│   └── write_review_screen.dart
├── profile/
│   ├── edit_profile_screen.dart
│   ├── maintenance_screen.dart
│   ├── notifications_screen.dart
│   ├── order_detail_screen.dart
│   ├── orders_screen.dart
│   ├── profile_helpers.dart
│   ├── quote_detail_screen.dart
│   ├── quote_request_detail_screen.dart
│   └── quotes_screen.dart
├── quotes/
│   ├── questions_screen.dart
│   └── reviews_screen.dart
└── tickets/
    ├── ticket_detail_screen.dart
    └── tickets_list_screen.dart
```

### 1.2 Servicios, modelos, widgets y utilidades

```text
lib/services/
├── address_service.dart
├── auth_identity_service.dart
├── cart_service.dart
├── catalog_service.dart
├── favorite_service.dart
├── location_service.dart
├── mercado_pago_test_service.dart
├── notification_service.dart
├── payment_deep_link_service.dart
├── product_service.dart
├── promotion_banner_service.dart
├── question_service.dart
├── quote_service.dart
├── review_service.dart
├── search_service.dart
└── ticket_service.dart

lib/models/
├── catalog_category.dart
├── payment_test_result.dart
├── product.dart
├── promotion_banner.dart
├── quote_item.dart
├── service_ticket.dart
└── ticket_message.dart

lib/widgets/
├── load_error_state.dart
├── review_video_tile.dart
└── standard_section_header.dart

lib/utils/
├── constants.dart
└── ui_helpers.dart
```

### 1.3 Recursos y pruebas

```text
assets/
└── images/
    ├── logo.png
    ├── splash_icon.png
    ├── splash_mark.png
    ├── 2.0x/
    │   └── logo.png
    ├── 3.0x/
    │   └── logo.png
    └── payments/
        ├── mastercard_v3.svg
        ├── mercadopago_v3.svg
        ├── oxxo_v3.svg
        └── visa_v3.svg

test/
├── widget_test.dart
├── services/
│   ├── mercado_pago_test_service_test.dart
│   └── payment_deep_link_service_test.dart
├── unit/
│   ├── address_test.dart
│   ├── catalog_category_test.dart
│   ├── product_test.dart
│   └── promotion_banner_test.dart
└── widgets/
    └── product_card_test.dart

integration_test/
└── app_integration_test.dart
```

### 1.4 Aclaraciones de rutas

- Marketplace: `lib/screens/home/tabs/marketplace_tab.dart`.
- Mantenimiento: `lib/screens/profile/maintenance_screen.dart`.
- No existe `maintenance_request_screen.dart`.
- Búsqueda: `lib/screens/product/search_screen.dart`.
- Direcciones: `lib/screens/home/address_picker_screen.dart`, con persistencia
  centralizada en `lib/services/address_service.dart`.
- Opiniones: `write_review_screen.dart`, `all_reviews_screen.dart` y pantallas
  auxiliares bajo `lib/screens/product/`.
- Preguntas: `ask_question_screen.dart`, `all_questions_screen.dart` y
  `single_question_screen.dart`.
- El apartado de facturación ya no tiene pantalla en el árbol actual.

## 2. Estado real de los módulos

### 2.1 Inicio de sesión y registro

- **Estado:** funcional parcial. Hay autenticación por correo/contraseña,
  Google, OTP y un flujo guiado de registro, pero conviven el registro antiguo
  y el flujo por pasos.
- **Pantallas:** `login_screen.dart`, `register_screen.dart`,
  `otp_verification_screen.dart` y `registration_flow/`.
- **Servicios/modelos/widgets:** Supabase Auth directo,
  `AuthIdentityService`; no hay modelo de dominio exclusivo.
- **Supabase:** Auth; lectura de `profiles`; compatibilidad con `clients`; RPC
  `check_phone_exists`.
- **Escrituras:** creación de usuario mediante Auth y metadatos de registro.
- **Validaciones:** sesión, correo, contraseña, nombre, teléfono, OTP y
  aceptación de términos. El teléfono puede omitirse en el flujo guiado.
- **Estados:** carga y errores de autenticación presentados en las pantallas.
- **Navegación:** `AuthGate` en `main.dart` decide entre autenticación y
  `HomeScreen`.
- **Riesgos:** duplicación de flujos de registro; la asociación entre
  `auth.uid()`, `profiles.client_id` y el identificador heredado requiere
  consistencia de backend y RLS.

### 2.2 Home y navegación inferior

- **Estado:** funcional.
- **Pantalla:** `home_screen.dart`.
- **Widgets:** pestañas Marketplace, Categorías, Carrito, Tickets y Perfil.
- **Datos:** cada pestaña carga sus propios servicios; Home inicia el listener
  de notificaciones.
- **Estados:** pantalla blanca de carga inicial antes de mostrar navegación;
  `IndexedStack` conserva el estado de las pestañas.
- **Navegación:** cambio por barra inferior y rutas `MaterialPageRoute`.
- **Riesgos:** no hay router declarativo central; varias rutas dependen de
  navegación directa y callbacks entre pantallas.

### 2.3 Marketplace

- **Estado:** funcional parcial, dependiente de vistas y RLS.
- **Pantalla:** `marketplace_tab.dart`.
- **Servicios:** `ProductService`, `CatalogService`,
  `PromotionBannerService`, `AddressService` y consultas del carrito.
- **Modelos/widgets:** `Product`, `CatalogCategory`, `PromotionBanner`,
  `ProductCard`, `BannerCarousel`, secciones de promociones y shimmer.
- **Lecturas:** `products`, `categories`, `subcategories`,
  `active_promotion_banners`, `active_promotion_cards`, `carts`.
- **Buckets:** `product-media` y `promotion-assets`.
- **Validaciones:** solo elementos activos, URLs remotas saneadas, contratos
  explícitos de columnas para productos.
- **Estados:** carga inicial, reintento, error de red, listas vacías y refresh.
- **Navegación:** detalle, búsqueda, categoría, promociones, direcciones,
  notificaciones y cotización.
- **Riesgos:** las vistas activas se consumen con `select('*')`; su contrato y
  filtro temporal pertenecen al backend y no están versionados aquí.

### 2.4 Categorías y subcategorías

- **Estado:** funcional parcial.
- **Pantallas:** `categories_tab.dart`, `category_catalog_screen.dart` y
  `category_products_screen.dart`.
- **Servicio/modelo:** `CatalogService`, `ProductService`,
  `CatalogCategory`, `CatalogSubcategory`, `Product`.
- **Lecturas:** `categories`, `subcategories`, `products`.
- **Bucket:** `product-media` para imágenes.
- **Validaciones:** activos, orden de catálogo, relación categoría-subcategoría.
- **Estados:** carga, error de red, reintento, categoría sin productos.
- **Navegación:** Home o pestaña Categorías → catálogo → productos → detalle.
- **Riesgos:** el resultado correcto depende de `sort_order`, IDs y slugs
  coherentes en Supabase.

### 2.5 Búsqueda

- **Estado:** funcional parcial.
- **Pantalla/servicio:** `search_screen.dart`, `search_service.dart`.
- **Modelo/widgets:** `Product`, `ProductCard`.
- **Lecturas:** productos y relaciones públicas de producto.
- **Datos locales:** búsquedas recientes e historial con
  `SharedPreferences`.
- **Validaciones:** texto normalizado, control de consulta vacía y resultado.
- **Estados:** inicial, buscando, sin resultados, error y resultados.
- **Navegación:** desde buscadores del Home o detalle; salida por retroceso.
- **Riesgos:** el filtro PostgREST construido con texto del usuario puede ser
  sensible a caracteres que alteren la sintaxis del filtro; no es SQL directo,
  pero conviene encapsular búsquedas complejas en una vista/RPC.

### 2.6 Detalle de producto

- **Estado:** funcional parcial.
- **Pantalla:** `product_detail_screen.dart`.
- **Servicios:** `ProductService`, `CartService`, `FavoriteService`,
  `QuestionService`, `ReviewService`.
- **Modelos/widgets:** `Product`, tarjetas de productos, preguntas, opiniones,
  multimedia y medios de pago.
- **Lecturas:** `products`, `product_media`, `product_specs`,
  `active_product_promotions`, preguntas, opiniones y favoritos.
- **Escrituras:** carrito y favoritos; preguntas mediante RPC.
- **Validaciones:** producto disponible, URLs de imágenes, sesión para acciones
  privadas y límites propios de preguntas/opiniones.
- **Estados:** carga, error, producto no disponible y secciones vacías.
- **Navegación:** desde listados; hacia carrito, preguntas, opiniones,
  cotización y productos relacionados.
- **Riesgos:** la disponibilidad comercial mostrada no reserva inventario.

### 2.7 Carrito

- **Estado:** funcional parcial. Administra artículos y cotización; la compra
  real no está finalizada.
- **Pantalla/servicio:** `cart_tab.dart`, `cart_service.dart`.
- **Modelo/widgets:** `Product`, diálogo de carrito abandonado,
  `CheckoutSheet`, selector de cupón aún sin flujo completo de backend.
- **Lecturas/escrituras:** `profiles`, `clients`, `carts`, `cart_items`.
  Inserta, actualiza y elimina artículos.
- **RPC:** `process_cart_quote`; `check_phone_exists` en validaciones asociadas.
- **Validaciones:** sesión, cliente efectivo, cantidad, selección de artículos,
  teléfono y carrito no vacío.
- **Estados:** carga, vacío, error, disponibilidad y selección.
- **Navegación:** detalle/Home → carrito; carrito → cotización o checkout de
  prueba.
- **Riesgos:** no existe confirmación de pago productiva ni reserva de stock
  visible en este flujo.

### 2.8 Direcciones

- **Estado:** funcional parcial con persistencia en Supabase.
- **Pantalla/servicios:** `address_picker_screen.dart`,
  `address_service.dart`, `location_service.dart`.
- **Lecturas/escrituras:** `profiles`, `clients`, `client_addresses`; select,
  insert, update y delete, incluida dirección principal.
- **Servicios externos:** geolocalización, OpenStreetMap/Nominatim y consulta
  postal.
- **Validaciones:** sesión/cliente, dirección, ciudad/municipio, estado, código
  postal, datos de receptor y teléfono; los cambios se guardan al confirmar.
- **Estados:** geolocalización, mapa, formulario, lista vacía, error y guardado.
- **Navegación:** encabezado del Home, carrito y mantenimiento.
- **Riesgos:** la precisión de colonia depende del geocodificador y del catálogo
  postal externo; RLS debe limitar cada dirección a su propietario.

### 2.9 Cotizaciones

- **Estado:** funcional parcial.
- **Pantallas:** `quote_cart_screen.dart`, `quote_request_sheet.dart`,
  `quotes_screen.dart`, `quote_detail_screen.dart` y
  `quote_request_detail_screen.dart`.
- **Servicio/modelo:** `QuoteService`, `QuoteItem`.
- **Lecturas:** `quotes`, `quote_items`, `quote_requests`,
  `quote_request_items`.
- **Escrituras:** insert en `quote_requests` y `quote_request_items`; cambios
  de cotizaciones en flujos de aceptación disponibles.
- **Datos locales:** carrito de cotización en `SharedPreferences`.
- **Validaciones:** sesión, artículos, cantidades, datos de solicitud y notas.
- **Estados:** carga, lista vacía, error y detalle.
- **Navegación:** producto/carrito → solicitud → perfil/cotizaciones.
- **Riesgos:** aprobación, precio final y permisos dependen de políticas y
  procesos del backend no incluidos.

### 2.10 Mercado Pago

- **Estado:** prueba técnica, no compra productiva.
- **Pantallas/servicios:** `checkout_sheet.dart`,
  `mercado_pago_test_service.dart`, `payment_deep_link_service.dart`,
  `payment_result_screen.dart`.
- **Edge Function:** `create-mp-test-preference`.
- **Datos enviados:** cuerpo vacío `{}` desde un usuario autenticado. Flutter no
  envía precio, IVA, producto, cantidad ni total.
- **Respuesta esperada:** `checkout_url`, además de identificadores opcionales
  de preferencia y referencia externa.
- **Validaciones:** sesión, exclusión de doble apertura, HTTPS y dominio
  permitido de Mercado Pago.
- **Estados:** apertura, éxito técnico, pendiente, fallo y errores HTTP.
- **Navegación:** checkout en pestaña personalizada y retorno por
  `gomedical://payment/success|pending|failure`.
- **Riesgos:** no hay código de webhook en el repositorio; no se demuestra
  confirmación del pago, creación de pedido ni descuento de inventario.

### 2.11 Pedidos

- **Estado:** funcional parcial, principalmente consulta.
- **Pantallas:** `orders_screen.dart`, `order_detail_screen.dart`.
- **Lecturas:** `orders`, `order_items` y datos públicos de producto.
- **Validaciones:** sesión/cliente y selección del pedido.
- **Estados:** carga, vacío, error y detalle.
- **Navegación:** Perfil → Mis compras → detalle.
- **Riesgos:** el repositorio móvil no contiene el proceso productivo que crea
  el pedido tras un webhook de pago.

### 2.12 Favoritos e historial

- **Estado:** funcional.
- **Pantallas/servicios:** `favorites_screen.dart`,
  `recently_viewed_screen.dart`, `manage_history_screen.dart`,
  `favorite_service.dart`.
- **Supabase:** `client_favorites` con select, insert y delete.
- **Local:** productos vistos e indicador de historial en
  `SharedPreferences`.
- **Validaciones:** sesión para favoritos; deduplicación y límites locales para
  historial.
- **Estados:** carga, vacío y error.
- **Navegación:** Perfil o detalle → listado → producto.
- **Riesgos:** el historial local no se sincroniza entre dispositivos.

### 2.13 Preguntas

- **Estado:** funcional parcial.
- **Pantallas/servicio:** `ask_question_screen.dart`,
  `all_questions_screen.dart`, `single_question_screen.dart`,
  `question_service.dart`.
- **Supabase:** lectura y eliminación en `product_questions`; creación mediante
  RPC `submit_product_question`.
- **Validaciones:** sesión, producto, texto no vacío y longitud.
- **Estados:** carga, sin preguntas, error y envío.
- **Navegación:** detalle → preguntar/listado/detalle.
- **Riesgos:** moderación, respuesta administrativa y visibilidad dependen de
  RLS y procesos externos.

### 2.14 Opiniones

- **Estado:** funcional parcial.
- **Pantallas/servicio:** `write_review_screen.dart`,
  `all_reviews_screen.dart`, `reviews_screen.dart`, `review_service.dart`.
- **Supabase:** `product_reviews`, `orders`, `order_items`.
- **Storage:** `review-assets`; upload, eliminación y URL pública.
- **Validaciones:** compra previa, calificación, comentario, máximo 5 imágenes,
  1 video, límite de 40 MB y duración máxima configurada en la interfaz.
- **Estados:** pendientes, realizadas, sin opiniones, edición, carga y error.
- **Navegación:** Perfil → Opiniones; detalle → opiniones.
- **Riesgos:** las URLs públicas de fotografías/videos pueden exponer contenido
  del cliente; para contenido privado conviene bucket privado y URL firmada.

### 2.15 Perfil

- **Estado:** funcional parcial.
- **Pantallas:** `profile_tab.dart`, `edit_profile_screen.dart`.
- **Supabase:** lectura y actualización de `profiles`; enlaces a módulos del
  usuario.
- **Validaciones:** sesión, nombre, teléfono y campos editables.
- **Estados:** carga, error y cierre de sesión.
- **Navegación:** pestaña Perfil hacia compras, cotizaciones, favoritos,
  historial, preguntas, opiniones, mantenimiento, soporte y configuración.
- **Riesgos:** algunos módulos combinan `profiles.client_id` y fallback a
  `auth.uid()`; la equivalencia debe estar garantizada por backend.

### 2.16 Mantenimiento biomédico

- **Estado:** funcional parcial, con creación real de ticket.
- **Pantalla:** `maintenance_screen.dart`.
- **Servicios/modelos:** `AddressService`, `AuthIdentityService`,
  `TicketService`, `ServiceTicket`.
- **Lecturas:** `profiles`, `equipment_units` y productos relacionados.
- **Escrituras:** insert en `service_tickets`; adjuntos y mensajes posteriores.
- **Tipos actuales:** mantenimiento preventivo, correctivo y reparación.
- **Validaciones comunes:** nombre, modelo y marca del equipo; número de serie
  opcional; descripción; contacto; teléfono de 10 a 13 dígitos; área,
  institución y dirección.
- **Preventivo:** equipo enciende; mantenimiento preventivo previo; si la
  respuesta es sí, fecha del último mantenimiento.
- **Correctivo:** equipo enciende; si enciende, frecuencia de falla; desde
  cuándo ocurre o desde cuándo dejó de encender; código de error opcional.
- **Reparación:** equipo enciende; daños visibles; reparación anterior; código
  de error opcional.
- **Adjuntos:** máximo 5 fotografías y 1 video, video de hasta 1 minuto y
  archivo de hasta 40 MB.
- **Estados:** carga del formulario, selección, validación, envío y resultado.
- **Navegación:** Perfil → Mantenimientos → formulario; la solicitud aparece
  como ticket.
- **Riesgos:** área, institución y parte de los datos técnicos se incorporan a
  la descripción, no en columnas dedicadas. El ticket puede crearse aunque un
  adjunto falle, porque no hay transacción única entre insert y uploads.

### 2.17 Tickets y mensajes

- **Estado:** funcional parcial.
- **Pantallas/servicio:** `tickets_list_screen.dart`,
  `ticket_detail_screen.dart`, `ticket_service.dart`.
- **Modelos:** `ServiceTicket`, `TicketMessage`.
- **Supabase:** `service_tickets`, `service_ticket_messages`, lectura,
  inserción, actualización de estados y realtime.
- **Storage:** bucket privado `ticket-attachments`; se guardan referencias
  `storage://` y se generan URLs firmadas por una hora.
- **Validaciones:** sesión, contenido de mensaje, tipos/tamaños de adjunto,
  video de hasta 40 MB.
- **Estados:** filtros, carga, sin tickets, error, conversación y envío.
- **Navegación:** pestaña Soporte → lista → detalle.
- **Riesgos:** consultas por ID o número de ticket dependen de RLS para impedir
  acceso cruzado. Las marcas de leído/entregado usan hora del dispositivo y
  sería preferible que el servidor fijara esos timestamps.

### 2.18 Notificaciones

- **Estado:** funcional parcial.
- **Pantalla/servicio:** `notifications_screen.dart`,
  `notification_service.dart`.
- **Supabase:** `notifications` con select, update y suscripción realtime.
- **Local:** preferencias y notificaciones locales mediante
  `flutter_local_notifications`.
- **Validaciones:** sesión, propiedad del destinatario y estado leído.
- **Estados:** carga, vacío, error y actualizaciones en vivo.
- **Navegación:** Home o Perfil → Notificaciones.
- **Riesgos:** entrega push remota y generación del evento no se demuestran en
  este repositorio; RLS debe aislar cada bandeja.

## 3. Flujos reales de datos

### 3.1 Productos y categorías

```text
Usuario
→ Marketplace/Categorías/Búsqueda
→ ProductService o CatalogService
→ products, categories, subcategories y vistas de promociones
→ filas JSON
→ Product / CatalogCategory / PromotionBanner
→ ProductCard, carrusel y listados
→ Detalle de producto
```

Los productos usan listas explícitas de columnas. Las promociones de producto
llegan ya activas desde `active_product_promotions`; el modelo no usa la hora
del teléfono para decidir el descuento.

### 3.2 Carrito

```text
Usuario agrega o cambia cantidad
→ ProductDetailScreen/CartTab
→ CartService
→ resuelve profiles.client_id
→ carts y cart_items
→ respuesta actualizada
→ interfaz del carrito
→ process_cart_quote cuando se solicita cotización
```

Este flujo no confirma pagos ni descuenta inventario.

### 3.3 Direcciones

```text
Usuario abre selector
→ AddressPickerScreen
→ AddressService + LocationService
→ geolocalización/geocodificación/catálogo postal
→ formulario editable
→ confirmación
→ client_addresses insert/update
→ dirección principal visible en Home, carrito y mantenimiento
```

### 3.4 Cotizaciones

```text
Usuario selecciona productos
→ carrito local de cotización
→ QuoteService
→ quote_requests + quote_request_items
→ solicitud registrada
→ QuotesScreen
→ lectura de solicitud/cotización y detalle
```

### 3.5 Mercado Pago de prueba

```text
Usuario autenticado
→ CheckoutSheet
→ MercadoPagoTestService
→ Edge Function create-mp-test-preference con {}
→ checkout_url HTTPS validada
→ flutter_custom_tabs
→ Mercado Pago
→ deep link gomedical://payment/...
→ PaymentDeepLinkService
→ PaymentResultScreen
```

La pantalla de resultado aclara que el retorno no sustituye un webhook. No se
observa un flujo productivo de pedido/inventario.

### 3.6 Opiniones

```text
Usuario
→ Mis opiniones / detalle
→ ReviewService
→ orders + order_items para verificar compra
→ product_reviews
→ upload opcional a review-assets
→ opinión y URLs
→ listado o detalle del producto
```

### 3.7 Mantenimiento y tickets

```text
Usuario completa formulario
→ MaintenanceScreen
→ AddressService/AuthIdentityService
→ insert service_tickets
→ TicketService sube adjuntos a ticket-attachments
→ insert service_ticket_messages
→ TicketsListScreen
→ TicketDetailScreen + realtime
```

### 3.8 Notificaciones

```text
Usuario autenticado
→ Home inicia NotificationService
→ select notifications + canal realtime
→ modelo dinámico
→ indicador/listado
→ update de estado leído
```

## 4. Matriz de integración con Supabase

| Módulo | Servicio/archivo | Recurso | Operación y filtros | Identidad | Riesgo observado | RLS |
|---|---|---|---|---|---|---|
| Autenticación | `main.dart`, pantallas auth | Supabase Auth | sesión, sign-in, sign-up, OTP, OAuth | `auth.uid()` | flujos de registro duplicados | Auth + sí |
| Identidad | `auth_identity_service.dart` | `profiles` | select por usuario; obtiene `client_id` | `auth.uid()` | fallback puede ocultar inconsistencias | Crítica |
| Registro | `cart_service.dart`/auth | RPC `check_phone_exists` | invoke con teléfono | sesión o pre-registro | enumeración si RPC queda abierta | Crítica |
| Marketplace | `product_service.dart` | `products` y relaciones | select explícito; activos, categoría, ID | público/autenticado | contrato aún contiene campos operativos menores | Sí |
| Promociones | `product_service.dart` | `active_product_promotions` | join select explícito | público | lógica temporal no versionada | Sí |
| Banners | `promotion_banner_service.dart` | `active_promotion_banners` | select `*`, order priority | público | contrato amplio de vista | Sí |
| Tarjetas | `promotion_banner_service.dart` | `active_promotion_cards` | select `*`, order priority | público | contrato amplio de vista | Sí |
| Catálogo | `catalog_service.dart` | `categories`, `subcategories` | select activos y orden | público | integridad de slugs/orden | Sí |
| Media catálogo | `catalog_service.dart` | `product-media` | getPublicUrl | público | cualquier archivo público es enumerable si se conoce ruta | Bucket |
| Carrito | `cart_service.dart` | `carts`, `cart_items` | select/insert/update/delete por carrito/cliente | `client_id` efectivo | acceso cruzado si falla RLS | Crítica |
| Cotización carrito | `cart_service.dart` | RPC `process_cart_quote` | invoke con carrito y notas | usuario/cliente | backend debe recalcular y autorizar | Crítica |
| Direcciones | `address_service.dart` | `client_addresses` | CRUD por cliente; principal | `client_id` efectivo | PII de domicilio y receptor | Crítica |
| Dirección heredada | `location_service.dart` | `clients` | select/update de dirección | `client_id` | coexistencia de formatos | Crítica |
| Solicitud cotización | `quote_service.dart` | `quote_requests`, `quote_request_items` | insert y select por cliente/solicitud | `client_id` | precio/aprobación deben ser backend | Crítica |
| Cotizaciones | pantallas perfil | `quotes`, `quote_items` | select/update según flujo | `client_id` | cambios sensibles desde cliente | Crítica |
| Pago prueba | `mercado_pago_test_service.dart` | Edge `create-mp-test-preference` | invoke con body vacío | sesión JWT | implementación Edge ausente del repo | Edge |
| Pedidos | pantallas perfil | `orders`, `order_items` | select por cliente/pedido | `client_id` | creación productiva no visible | Crítica |
| Favoritos | `favorite_service.dart` | `client_favorites` | select/insert/delete | `client_id` | acceso cruzado si falla RLS | Crítica |
| Preguntas | `question_service.dart` | `product_questions` | select/delete | usuario/producto | moderación y propiedad | Crítica |
| Crear pregunta | `question_service.dart` | RPC `submit_product_question` | invoke producto + texto | sesión | RPC debe validar identidad | Crítica |
| Opiniones | `review_service.dart` | `product_reviews` | select/insert/update/delete | usuario/cliente | edición ajena si falla RLS | Crítica |
| Verificar compra | `review_service.dart` | `orders`, `order_items` | select por cliente/producto | `client_id` | regla debe reforzarse en backend | Crítica |
| Multimedia opinión | `review_service.dart` | `review-assets` | upload/remove/getPublicUrl | sesión | contenido del cliente en URL pública | Bucket |
| Mantenimiento | `maintenance_screen.dart` | `equipment_units` | select equipo + producto | `client_id` | usa un select amplio en ruta principal/fallback | Crítica |
| Crear mantenimiento | `maintenance_screen.dart` | `service_tickets` | insert con contacto/ubicación | usuario/cliente | campos técnicos parcialmente en descripción | Crítica |
| Tickets | `ticket_service.dart` | `service_tickets` | select por cliente, ID o número | `client_id`/sesión | consultas por ID dependen totalmente de RLS | Crítica |
| Mensajes | `ticket_service.dart` | `service_ticket_messages` | select/insert/update/realtime | sesión | privacidad de conversación | Crítica |
| Adjuntos ticket | `ticket_service.dart` | `ticket-attachments` | upload y signed URL de 1 h | sesión | referencias antiguas pueden ser URL remota | Bucket privado |
| Notificaciones | `notification_service.dart` | `notifications` | select/update/realtime por destinatario | sesión | exposición de bandeja si falla RLS | Crítica |
| Perfil | pantallas perfil | `profiles` | select/update | `auth.uid()` | datos personales | Crítica |

## 5. Seguridad observada

### 5.1 Configuración y credenciales

- `SUPABASE_URL`, `SUPABASE_ANON_KEY` y client IDs de Google se obtienen con
  `String.fromEnvironment` en `constants.dart`.
- La ejecución esperada usa `--dart-define` o
  `--dart-define-from-file=dart_defines.json`.
- `dart_defines.json`, `.env` y variantes están ignorados por Git.
- El archivo versionado `dart_defines.example.json` contiene marcadores, no
  valores reales.
- `pubspec.yaml` no empaqueta `dart_defines.json` como asset.
- No se encontró una `service_role` dentro de `lib/` ni en archivos
  versionados. La aplicación solo debe usar la clave pública de Supabase.

La URL del proyecto y la anon key son identificadores públicos para el cliente,
pero no sustituyen RLS. La `service_role` sí sería secreta y no debe incluirse
en Flutter.

### 5.2 Sesión e identidad

- Las operaciones privadas verifican sesión en servicios relevantes.
- `AuthIdentityService` intenta resolver `profiles.client_id`; si no existe,
  usa `auth.uid()` por compatibilidad.
- Este fallback evita bloqueos en datos heredados, pero exige que las políticas
  entiendan ambos esquemas o que se unifique la identidad en backend.

### 5.3 Columnas y datos sensibles

- `ProductService` usa columnas públicas explícitas y no solicita
  `cost_price_mxn` ni inventario interno.
- Todavía expone algunos datos operativos de catálogo, como
  `track_inventory` y `lead_time_days`; deben confirmarse como parte del
  contrato público.
- La consulta de `equipment_units` usa una selección amplia en mantenimiento.
  Debe protegerse con RLS y, de ser posible, una vista/contrato explícito.

### 5.4 Storage

- `product-media` y `promotion-assets` se consumen como recursos públicos.
- `review-assets` genera URLs públicas; representa el mayor riesgo de
  privacidad para contenido subido por clientes.
- `ticket-attachments` usa referencias privadas y URLs firmadas por una hora,
  un enfoque adecuado para evidencia de soporte.

### 5.5 Pagos, precios y tiempo

- Flutter no envía montos al crear la preferencia de Mercado Pago de prueba.
- La URL de checkout se restringe a HTTPS y dominios permitidos.
- Las promociones de producto se aceptan desde la respuesta del backend; el
  modelo no compara vigencia con `DateTime.now()`.
- Los banners se leen desde vistas llamadas `active_*`. La seguridad frente a
  cambiar la hora del teléfono depende de que esas vistas filtren con tiempo de
  base de datos. Esa definición SQL no está en el repositorio y debe
  verificarse.
- La hora del teléfono sí se usa en metadatos no financieros, por ejemplo
  marcas de lectura de mensajes. Es preferible un timestamp de servidor.

### 5.6 Operaciones sensibles pendientes de verificación

- RLS de todas las tablas con `client_id`, usuario, direcciones, pedidos,
  opiniones, tickets, mensajes y notificaciones.
- Permisos de ejecución de `process_cart_quote`, `check_phone_exists` y
  `submit_product_question`.
- Código y secretos de `create-mp-test-preference`.
- Webhook firmado de Mercado Pago.
- Creación idempotente de pedido y descuento de inventario después del webhook.
- Contratos SQL de las vistas `active_*`.

## 6. Estado exacto de Mercado Pago

1. `CheckoutSheet` presenta una prueba técnica de $10 MXN y llama a
   `MercadoPagoTestService.startTestPayment()`.
2. El servicio exige una sesión activa y evita dos aperturas simultáneas.
3. Invoca `create-mp-test-preference` con `body: <String, dynamic>{}`.
4. Espera un mapa con `checkout_url`; también puede interpretar identificadores
   de preferencia y referencia externa.
5. Rechaza HTTP, hosts vacíos y dominios ajenos a Mercado Pago.
6. Abre la URL mediante `flutter_custom_tabs`.
7. `PaymentDeepLinkService` escucha el enlace inicial y el stream de
   `app_links`.
8. Reconoce los resultados `success`, `pending` y `failure` bajo el esquema
   `gomedical://payment/...`.
9. `PaymentResultScreen` indica que el retorno no es confirmación definitiva.

**No encontrado en el repositorio:**

- código de la Edge Function;
- webhook de Mercado Pago;
- validación de firma del webhook;
- idempotencia por evento/pago;
- creación productiva del pedido;
- confirmación de pago antes de modificar inventario;
- conciliación de estados;
- proceso de reembolso.

Conclusión: el flujo está preparado para una prueba autenticada de Checkout Pro,
pero no debe describirse como compra funcional de producción.

## 7. Mantenimiento y tickets

### 7.1 Solicitud de mantenimiento biomédico

El formulario crea un registro en `service_tickets`. Los datos estructurados
incluyen cliente, usuario solicitante, contacto, teléfono, correo, ubicación,
ciudad, estado/región, código de error, tipo, prioridad y estado abierto. La
descripción compuesta conserva datos técnicos adicionales.

Obligatorios actuales:

- nombre, modelo y marca del equipo;
- tipo de servicio y estado de encendido;
- descripción;
- nombre y teléfono del responsable;
- área/departamento;
- hospital, clínica o institución;
- dirección seleccionada.

Opcionales o condicionales:

- número de serie;
- fecha del último mantenimiento, solo cuando se declara uno previo;
- frecuencia de falla, si el correctivo todavía enciende;
- antigüedad de la falla;
- daños visibles y reparación previa para reparación;
- código de error;
- fotografías y video.

La prioridad se asigna internamente según el tipo; la interfaz actual no expone
un selector de urgencia. Esto reduce complejidad para el usuario, pero el equipo
administrativo debe poder reclasificarla.

### 7.2 Ticket de soporte y conversación

- `TicketsListScreen` filtra por estados.
- `TicketDetailScreen` muestra el ticket y sus mensajes.
- `TicketService` inserta mensajes como cliente y excluye mensajes internos.
- La conversación se actualiza por realtime.
- Los adjuntos se suben al bucket privado `ticket-attachments`.
- En la base se guarda una referencia `storage://bucket/ruta`.
- Al visualizar se solicita una URL firmada con una hora de vigencia.
- Se actualizan marcas de entregado/leído desde el cliente.

### 7.3 Riesgos operativos

- El insert del ticket y los uploads no forman una transacción única.
- Parte de los datos del mantenimiento solo queda en texto de descripción, lo
  que dificulta filtros administrativos.
- La aplicación administrativa debe mostrar contacto, institución, área,
  ubicación, datos técnicos, evidencia y conversación.
- RLS debe impedir que un cliente consulte tickets, mensajes o adjuntos ajenos.

## 8. Pruebas

### 8.1 Inventario de pruebas

| Archivo | Tipo | Componente | Escenario principal |
|---|---|---|---|
| `test/widget_test.dart` | unitaria mínima | configuración de tests | verificación aritmética; no prueba UI |
| `test/unit/address_test.dart` | unitaria | dirección | formato, CP, truncado y compatibilidad de datos |
| `test/unit/catalog_category_test.dart` | unitaria | categorías | flags, subcategorías y adaptación de slugs |
| `test/unit/product_test.dart` | unitaria | producto/promoción | condición, stock, precio, promociones y reloj |
| `test/unit/promotion_banner_test.dart` | unitaria | banner | prioridad de assets, móvil y JSON |
| `test/services/mercado_pago_test_service_test.dart` | unitaria de servicio | Mercado Pago | URL, sesión, body vacío, doble apertura y errores |
| `test/services/payment_deep_link_service_test.dart` | unitaria de servicio | deep links | interpretación y deduplicación de resultados |
| `test/widgets/product_card_test.dart` | widget | tarjeta de producto | precio, stock, campaña, más vendido y condición |
| `integration_test/app_integration_test.dart` | integración smoke | app y navegación | arranque y rutas principales sin excepción |

### 8.2 Resultados ejecutados

- `flutter analyze`: **sin problemas**, finalizó con código 0.
- `flutter test`: **46 pruebas aprobadas**, código 0.
- `integration_test/app_integration_test.dart`: no se ejecutó en esta revisión
  porque requiere dispositivo/emulador y configuración del entorno.

La integración existente es superficial: puede omitir autenticación y solo
comprueba que algunas rutas no produzcan una excepción. No valida datos reales,
RLS, pago, webhook, pedido ni inventario.

### 8.3 Cobertura faltante prioritaria

- autenticación/registro y recuperación;
- CRUD de carrito con Supabase;
- direcciones y geocodificación;
- RLS mediante usuarios distintos;
- cotizaciones;
- pedido y detalle;
- opiniones con multimedia;
- formulario dinámico de mantenimiento;
- tickets, mensajes, realtime y URLs firmadas;
- notificaciones;
- banners con carga automática y errores;
- E2E de Mercado Pago en staging con webhook e idempotencia.

## 9. Evidencias recomendadas para un reporte académico

| Evidencia | Acción | Qué demuestra | Título sugerido | Ocultar |
|---|---|---|---|---|
| Login/registro | mostrar login y flujo por pasos | control de acceso y validación | “Flujo de autenticación móvil” | correo, teléfono, OTP |
| Home | cargar catálogo, banner y navegación | integración del marketplace | “Pantalla principal de Go Medical” | CP si es real |
| Categorías | abrir categoría y subcategoría | jerarquía de catálogo | “Navegación por categorías” | nada |
| Producto | abrir detalle y medios de pago | contrato público del producto | “Consulta de producto médico” | SKU interno si aplica |
| Carrito | agregar producto y cambiar cantidad | persistencia del carrito | “Gestión del carrito de compra” | identificadores |
| Direcciones | listar y editar una dirección de prueba | geolocalización y CRUD | “Administración de direcciones” | domicilio, teléfono, receptor |
| Cotizaciones | enviar solicitud y abrir detalle | flujo comercial alternativo | “Solicitud de cotización” | notas/identidad |
| Mercado Pago | abrir checkout sandbox y regresar | integración técnica de prueba | “Prueba autenticada de Checkout Pro” | preference ID, correo |
| Opiniones | mostrar editor y multimedia | reseñas verificadas | “Gestión de opiniones del comprador” | fotos personales |
| Mantenimiento | cambiar tipo y mostrar campos dinámicos | captura biomédica contextual | “Solicitud de servicio biomédico” | serie, clínica, contacto |
| Tickets | abrir conversación con adjunto | trazabilidad y realtime | “Seguimiento de ticket de servicio” | mensajes y URLs firmadas |
| Supabase | mostrar esquema/policies sin secretos | persistencia y seguridad | “Integración de datos con Supabase” | URL, keys, tokens, datos |
| Servicios Dart | mostrar método con select explícito | separación de responsabilidades | “Capa de servicios de la aplicación” | ninguna credencial |
| Pruebas | capturar salida de analyze/test | calidad estática y automatizada | “Validación automatizada del proyecto” | rutas de usuario si se desea |

## 10. Historial y autoría técnica

El historial disponible contiene cuatro commits:

| Fecha | Commit | Evidencia del historial |
|---|---|---|
| 15-07-2026 | `387a617` | estructura inicial del proyecto |
| 15-07-2026 | `70a933e` | seguridad, pendientes de backend y ajustes de pantallas |
| 15-07-2026 | `a25ffdf` | estados vacíos, errores y avisos visuales |
| 27-07-2026 | `b927932` | opiniones, direcciones, marketplace, mantenimiento, tickets, servicios y pruebas |

El último commit concentra cambios amplios: autenticación, Home, direcciones,
carrito, catálogo dinámico, banners, Mercado Pago de prueba, opiniones,
mantenimiento, tickets y pruebas. También eliminó pantallas anteriores como
facturación y equipos.

Los commits figuran bajo el autor Git `NoobMaster64`. Esto demuestra la identidad
configurada en Git, pero la autoría individual de cada decisión o línea fuera de
esos commits es **no verificable mediante el historial disponible**.

## 11. Discrepancias con documentos anteriores

### 11.1 `documentacion_proyecto.txt`

Rutas desactualizadas:

- documenta `lib/screens/home/marketplace_tab.dart`; la ruta real es
  `lib/screens/home/tabs/marketplace_tab.dart`;
- documenta `lib/screens/search/search_screen.dart`; la ruta real es
  `lib/screens/product/search_screen.dart`;
- documenta `lib/screens/profile/maintenance_request_screen.dart`; la ruta real
  es `lib/screens/profile/maintenance_screen.dart`.

Otras diferencias:

- menciona `process_cart_checkout` como función revisada, pero el código móvil
  actual no la invoca; usa `process_cart_quote` para cotización y una Edge
  Function separada para la prueba de pago;
- describe correctamente la ausencia de `service_role`, los buckets principales
  y el carácter de prueba de Mercado Pago;
- no sustituye una definición versionada de esquema, RLS o Edge Functions.

### 11.2 `mapa_codigo_app_go_medical.txt`

- Usa correctamente las rutas actuales de marketplace, búsqueda, direcciones,
  opiniones y mantenimiento.
- Registra que Facturación fue retirada.
- Está más alineado con la implementación actual que
  `documentacion_proyecto.txt`.
- Enumera `dart_defines.json` como archivo local; debe aclararse siempre que
  está ignorado y no forma parte de una clonación limpia.
- Al igual que el documento general, menciona comprobaciones pendientes sobre
  `process_cart_checkout`, aunque la app actual no la consume.

### 11.3 Funciones nuevas o no representadas como fuente de verdad

- El código actual incluye catálogo/banners administrables, direcciones
  enriquecidas, multimedia de opiniones, formulario dinámico de mantenimiento,
  adjuntos privados de ticket, deep links y pruebas específicas.
- Ninguno de los dos documentos aporta migraciones, políticas RLS o código de
  Edge Functions. Esas piezas deben documentarse desde el repositorio privado
  de Supabase.

## 12. Matriz final para redacción académica

| Objetivo o actividad | Implementación realizada | Archivos principales | Datos utilizados | Resultado verificable | Evidencia recomendada | Pendiente |
|---|---|---|---|---|---|---|
| Autenticar usuarios | correo, contraseña, Google, OTP y flujo de registro | `main.dart`, `screens/auth/` | Auth, `profiles` | acceso condicionado por sesión/perfil | login y checklist | unificar registros y probar E2E |
| Mostrar marketplace | catálogo, banners y secciones dinámicas | `marketplace_tab.dart`, servicios de producto/catálogo/promoción | productos, categorías, vistas activas | Home carga contenido administrable | captura del Home | versionar vistas y probar RLS |
| Navegar catálogo | categorías, subcategorías y listados | `categories_tab.dart`, `category_catalog_screen.dart` | `categories`, `subcategories`, `products` | navegación hasta detalle | secuencia de pantallas | validar integridad del catálogo |
| Consultar productos | detalle, media, especificaciones, disponibilidad | `product_detail_screen.dart`, `product_service.dart` | contrato público de producto | información sin costo interno | detalle + servicio | revisar campos operativos públicos |
| Gestionar carrito | alta, cantidad, selección y eliminación | `cart_tab.dart`, `cart_service.dart` | `carts`, `cart_items` | carrito persistente | antes/después | pruebas y stock/reserva |
| Guardar direcciones | mapa, formulario y CRUD | `address_picker_screen.dart`, `address_service.dart` | `client_addresses` | dirección principal reutilizable | selector con datos anonimizados | probar geocodificación/RLS |
| Solicitar cotización | carrito local y solicitud en Supabase | pantallas de cotización, `quote_service.dart` | solicitudes, ítems y cotizaciones | solicitud consultable en Perfil | envío + detalle | permisos y aprobación backend |
| Probar Mercado Pago | preferencia de prueba y deep link | servicios de pago, `checkout_sheet.dart` | Edge Function, checkout URL | checkout sandbox autenticado | checkout y resultado | webhook, pedido e inventario |
| Gestionar opiniones | compra verificada, edición y multimedia | `write_review_screen.dart`, `review_service.dart` | reviews, pedidos, `review-assets` | opinión editable | pestañas y editor | privacidad de multimedia |
| Solicitar mantenimiento | formulario dinámico y creación de ticket | `maintenance_screen.dart` | equipos, direcciones, tickets | ticket abierto con evidencia | tres tipos de servicio | normalizar columnas administrativas |
| Dar seguimiento | lista, conversación, adjuntos y realtime | pantallas tickets, `ticket_service.dart` | tickets, mensajes, bucket privado | mensajes actualizados | conversación | pruebas de RLS/realtime |
| Notificar al usuario | bandeja, lectura y realtime | `notification_service.dart`, pantalla | `notifications` | actualización en vivo | bandeja | origen push y pruebas |
| Validar calidad | análisis estático y 46 pruebas | `test/`, `integration_test/` | código local | analyze limpio y tests aprobados | terminal | ampliar integración/E2E |

## Conclusión

La aplicación móvil posee una base funcional amplia: autenticación, catálogo,
carrito, direcciones, cotizaciones, contenido social, mantenimiento, tickets y
notificaciones. La capa visual está conectada a Supabase en la mayoría de los
módulos y existen medidas relevantes de seguridad en el cliente, como
configuración por `dart-define`, ausencia de `service_role`, selección explícita
de columnas de producto, validación de dominio de pago y adjuntos privados para
tickets.

El principal límite para considerarla lista para producción no está en la
existencia de pantallas, sino en la verificación del backend: RLS, contratos de
vistas, RPC, Edge Functions, webhook de Mercado Pago, idempotencia, creación de
pedidos e inventario. Estas piezas deben auditarse en Supabase y probarse en un
entorno de staging antes de afirmar que la compra completa es productiva.
