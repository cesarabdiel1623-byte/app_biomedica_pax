# Auditoria de Seguridad Supabase

Fecha: 2026-07-15

## Alcance

Revision basada en:

- El codigo Flutter actual en `lib/`
- Pruebas de lectura anonima con `SUPABASE_ANON_KEY`
- Flujo actual de credenciales con `dart_defines.json`

## Hallazgos

### 1. Critico: el catalogo publico expone columnas internas de productos

Riesgo:
El cliente anonimo puede consultar `products` sin autenticacion. Antes, la app
pedía `products(*)`, y el endpoint tambien devolvia `cost_price_mxn`.

Evidencia:

- [product_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\product_service.dart:1>)
- [question_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\question_service.dart:1>)
- [favorite_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\favorite_service.dart:1>)
- [review_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\review_service.dart:1>)

Accion realizada:
Se cambiaron las consultas del cliente para usar una lista explicita de columnas
publicas y excluir `cost_price_mxn`.

Pendiente en Supabase:

- Revocar acceso publico a columnas internas si hoy siguen disponibles.
- Idealmente publicar una `view` segura para catalogo, no la tabla base.

### 2. Alto: la aprobacion de cotizaciones crea pedidos desde el cliente

Riesgo:
La pantalla de detalle de cotizacion inserta en `orders`, inserta en
`order_items` y actualiza `quotes` desde el telefono. Eso deja una operacion de
negocio critica dependiendo de RLS y de datos enviados por el cliente.

Evidencia:

- [quote_detail_screen.dart](<C:\Users\cesar\Downloads\Go medical\lib\screens\profile\quote_detail_screen.dart:1>)

Recomendacion:

- Mover esta operacion a un RPC o Edge Function, por ejemplo `approve_quote`.
- El servidor debe validar:
  - que la cotizacion pertenece al usuario
  - que el estado permite aprobarla
  - que los totales se recalculen del lado servidor
  - que la orden y sus items se generen atomicos

### 3. Alto: adjuntos de tickets y reseñas usan URLs publicas

Riesgo:
Los buckets `ticket-attachments` y `review-assets` se consumen con
`getPublicUrl()`. Para reseñas puede ser aceptable; para tickets normalmente no.

Evidencia:

- [ticket_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\ticket_service.dart:1>)
- [review_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\review_service.dart:1>)

Recomendacion:

- `ticket-attachments`: bucket privado + signed URLs o descarga autenticada.
- `review-assets`: definir si realmente debe ser publico. Si si, limitar solo a
  contenido de reseñas aprobadas.
- Crear politicas en `storage.objects` por bucket y por ruta.

### 4. Medio: hay inconsistencia en el uso de `client_id`

Riesgo:
Parte de la app usa `profiles.client_id`; otras partes usan `auth.user.id`
directamente como `client_id`. Eso complica RLS y puede causar fugas o datos
partidos entre tablas.

Evidencia:

- [address_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\address_service.dart:1>)
- [cart_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\cart_service.dart:1>)
- [ticket_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\ticket_service.dart:1>)

Recomendacion:

- Elegir un solo criterio de ownership:
  - opcion A: todo cuelga de `auth.uid()`
  - opcion B: todo cuelga de `profiles.client_id`
- Ajustar servicios y politicas a ese criterio unico.

### 5. Medio: preguntas y reseñas publicas deben salir por superficie limitada

Riesgo:
`product_questions` y `product_reviews` parecen visibles al menos en lectura
anonima. Si eso es intencional, conviene exponer solo datos publicables.

Evidencia:

- [question_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\question_service.dart:1>)
- [review_service.dart](<C:\Users\cesar\Downloads\Go medical\lib\services\review_service.dart:1>)

Recomendacion:

- Exponer solo preguntas publicas y respuestas publicas.
- Exponer solo reseñas moderadas/publicadas.
- Considerar `views` publicas con columnas reducidas.

### 6. Medio: varias pantallas hacen operaciones directas sobre tablas privadas

Riesgo:
La logica de permisos queda repartida entre RLS y UI. Si una policy se abre de
mas, el cliente ya sabe operar directamente contra la tabla.

Evidencia:

- [maintenance_screen.dart](<C:\Users\cesar\Downloads\Go medical\lib\screens\profile\maintenance_screen.dart:1>)
- [notifications_screen.dart](<C:\Users\cesar\Downloads\Go medical\lib\screens\profile\notifications_screen.dart:1>)
- [orders_screen.dart](<C:\Users\cesar\Downloads\Go medical\lib\screens\profile\orders_screen.dart:1>)
- [quotes_screen.dart](<C:\Users\cesar\Downloads\Go medical\lib\screens\profile\quotes_screen.dart:1>)

Recomendacion:

- Mantener lecturas simples en cliente si RLS esta firme.
- Mover a RPC/Edge Function todo cambio de estado o flujo de negocio.

## Lo bueno que ya existe

- Las credenciales ya no viven en `lib/`.
- Las tablas privadas no devolvieron filas a un cliente anonimo en la prueba
  basica.
- Ya existen algunos RPCs con mejor enfoque:
  - `submit_product_question`
  - `process_cart_checkout`
  - `process_cart_quote`
  - `check_phone_exists`

## Tablas vistas desde la app

- Publicas o semipublicas por comportamiento observado:
  - `products`
  - `product_reviews`
  - `product_questions`

- Privadas por intencion funcional:
  - `profiles`
  - `clients`
  - `carts`
  - `cart_items`
  - `quotes`
  - `quote_items`
  - `quote_requests`
  - `quote_request_items`
  - `orders`
  - `order_items`
  - `client_addresses`
  - `client_favorites`
  - `notifications`
  - `service_tickets`
  - `service_ticket_messages`
  - `equipment_units`

## Checklist de politicas RLS recomendadas

### Catalogo

- `products`: lectura publica solo de columnas comerciales.
- `product_inventory`: lectura publica solo si mostrar stock al usuario es
  intencional.
- `active_product_promotions`: lectura publica si solo trae datos comerciales.

### Datos del cliente

- `profiles`: el usuario solo ve y actualiza su propio perfil.
- `clients`: el usuario solo lee/escribe su propio cliente asociado.
- `client_addresses`: solo el dueno puede `select/insert/update/delete`.
- `client_favorites`: solo el dueno puede `select/insert/delete`.

### Compra y cotizacion

- `carts` y `cart_items`: solo el dueno del carrito.
- `quotes`, `quote_items`, `quote_requests`, `quote_request_items`: solo el
  dueno y sin permitir cambios de estado sensibles desde cliente.
- `orders`, `order_items`: solo lectura del duenio; creacion idealmente por RPC.

### Soporte

- `service_tickets`: solo el duenio del ticket o su `client_id`.
- `service_ticket_messages`: solo participantes del ticket; bloquear mensajes
  internos para cliente.

### Notificaciones

- `notifications`: solo `user_id = auth.uid()`.

### Equipos

- `equipment_units`: solo equipos del `client_id` asociado al usuario.

## Siguiente paso recomendado

1. Exportar las policies actuales de Supabase.
2. Compararlas contra esta lista.
3. Corregir primero:
   - `products`
   - `quotes/orders`
   - `ticket-attachments`
4. Repetir prueba anonima despues de endurecer policies.
