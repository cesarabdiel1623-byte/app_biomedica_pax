# Auditoria de estados mobile y preparacion SkyDropX

## A. Repositorio comprobado

- Ruta: `C:/Users/cesar/Downloads/app_biomedica_pax-main`
- Rama: `main`
- Framework: Flutter. Evidencia: `pubspec.yaml` declara `name: gomedical_app`, dependencia `flutter`, `supabase_flutter`, estructura `lib/`, `android/`, `ios/`, `web/`.
- `git status --short` inicial: el worktree ya tenia cambios previos en varias pantallas/archivos generados y archivos nuevos de tracking/migraciones. Esta auditoria no modifica codigo funcional.

## B. Arquitectura movil relacionada con pedidos

Flutter usa Supabase desde cliente autenticado para leer pedidos, detalle, productos y tracking visible al cliente.

- `lib/screens/profile/orders_screen.dart`: lista pedidos con `.from('orders').select('*').eq('client_id', widget.clientId).order('created_at', ascending: false)`.
- `lib/screens/profile/order_detail_screen.dart`: recibe el mapa `order` desde la lista, carga `order_items`, reseñas del cliente y tracking con `TrackingService.getShipmentForOrder(orderId)`.
- `lib/services/tracking_service.dart`: lee vistas seguras `customer_order_shipments` y `customer_shipment_events`.
- `lib/services/mercado_pago_service.dart`: inicia pago mediante Edge Function y verifica pago mediante Edge Function; su fallback solo lee `orders` y `order_payments`.

## C. Flujo de Mis Pedidos

Archivo: `lib/screens/profile/orders_screen.dart`.

- Consulta Supabase: lineas 32-37, `orders.select('*')`, filtro `client_id`, orden descendente por `created_at`.
- Campos cargados: `*`; usados directamente en UI: `id`, `order_number`, `status`, `created_at`, `total`.
- Traduccion de estado: `_statusLabel` lineas 53-73.
- Colores/badges: `_statusColor` lineas 76-90 y badge lineas 164-181.
- Navegacion: pasa el objeto completo `o` a `OrderDetailScreen(order: o)` lineas 143-145.
- Condiciones de acciones: no hay acciones de cambio de estado en esta pantalla; solo tap para detalle y refresh.

Estados traducidos en Mis Pedidos:

- `draft` -> `Borrador`, gris.
- `pending_review` -> `En Revision`, naranja.
- `pending_payment` -> `Pendiente de Pago`, naranja.
- `paid` -> `Pagado`, verde.
- `processing` -> `Procesando`, azul.
- `shipped` -> `Enviado`, azul.
- `delivered` -> `Entregado`, verde.
- `canceled` -> `Cancelado`, rojo.
- `cancelled` no aparece como estado de `orders.status` en esta pantalla.

Riesgo UI pendiente: el badge del estado en `orders_screen.dart` esta en el extremo derecho de un `Row` junto a un `Expanded` para el numero de orden. El texto del badge no usa `maxLines`, `overflow` ni ancho maximo; con textos largos o pantallas estrechas podria persistir riesgo de overflow. No se corrigio por instruccion.

## D. Flujo de Detalle del Pedido

Archivo: `lib/screens/profile/order_detail_screen.dart`.

- Entrada: recibe `widget.order` desde Mis Pedidos.
- Carga de productos: `_loadItems` lineas 31-42 consulta `order_items` por `order_id`.
- Carga tracking: `_loadItems` linea 44 invoca `TrackingService.getShipmentForOrder(orderId)`.
- Estado del Pedido: proviene de `o['status']`, donde `o = widget.order`; se muestra con `_statusColor(o['status'] ?? '')` y `_statusLabel(o['status'] ?? '').toUpperCase()` alrededor de lineas 632-640.
- Seguimiento del envio: proviene de `_shipment`, cargado desde `TrackingService`; `_buildOrderPhases(o['status'] ?? '')` usa `_shipment?.shippingStatus` si existe y solo cae a `orders.status` si no hay shipment.

Confirmacion: el codigo demuestra separacion actual:

- `Estado del Pedido` <- `orders.status`.
- `Seguimiento del envio` <- `customer_order_shipments.shipping_status` via `OrderShipment.shippingStatus`.

## E. Lecturas de orders.status

Lecturas directas o relevantes encontradas en Flutter:

- `lib/screens/profile/orders_screen.dart:33-37`: lee pedidos completos desde `orders`.
- `lib/screens/profile/orders_screen.dart:53-73`: convierte `orders.status` a texto.
- `lib/screens/profile/orders_screen.dart:76-90`: convierte `orders.status` a color.
- `lib/screens/profile/orders_screen.dart:168-176`: renderiza badge con `o['status']`.
- `lib/screens/profile/order_detail_screen.dart:68-88`: convierte `orders.status` a texto.
- `lib/screens/profile/order_detail_screen.dart:91-105`: convierte `orders.status` a color.
- `lib/screens/profile/order_detail_screen.dart:109-166`: `_buildOrderPhases(status)` usa `orders.status` solo como fallback si no hay `_shipment`.
- `lib/screens/profile/order_detail_screen.dart:632-640`: renderiza badge `Estado del Pedido`.
- `lib/screens/profile/order_detail_screen.dart:656`: pasa `o['status']` a fases.
- `lib/screens/profile/order_detail_screen.dart:796-797`: habilita reseña si `status` no es `draft` ni `canceled`.
- `lib/services/mercado_pago_service.dart:173-174`: fallback lee `id,status,payment_status,total,paid_at,payment_id` de `orders`.
- `lib/services/mercado_pago_service.dart:200`: considera confirmado si `payment_status == approved` o `orders.status == paid`.
- `lib/services/review_service.dart:232-236`: para verificar compra, excluye `draft` y `canceled`.
- `lib/services/review_service.dart:360-364`: para opiniones pendientes, excluye `draft` y `canceled`.

## F. Escrituras a orders.status encontradas

En Flutter:

- No se encontro escritura directa a `public.orders.status` en Flutter.
- Busquedas especificas realizadas: `.from('orders')`, `.update(`, `updateOrder`, `status:`.
- Los `.update(` encontrados en Flutter corresponden a carrito, direcciones, reseñas, tickets, perfil, notificaciones, followup de carrito o checkout sheet; no a `orders.status`.

Conclusion: Flutter solamente consume el estado de la orden; no es responsable de actualizar `public.orders.status`, segun el codigo local inspeccionado.

En backend local:

- `supabase/migrations/20260803000000_fix_mercado_pago_webhook_reconciliation.sql:147-153`: RPC `reconcile_mercado_pago_payment` actualiza `orders.payment_status = 'approved'` y `orders.status` a `paid` cuando el estado actual esta en `pending_payment`, `draft`, `pending_review`, `canceled`.
- `supabase/migrations/20260805120000_real_checkout.sql:202-207`: `prepare_web_checkout_order` inserta orden nueva con `status = 'pending_payment'`.
- `supabase/migrations/20260805120000_real_checkout.sql:187-190`: cancela orden pendiente reemplazada con `status = 'canceled'`.
- `supabase/migrations/20260805120000_real_checkout.sql:390-436`: `reconcile_mp_web_order_payment` actualiza `status = 'paid'`.
- `supabase/migrations/20260807121500_fix_web_payment_reconciliation.sql:153-199` y `20260807140000_convert_cart_after_web_payment.sql:154-215`: versiones posteriores de la reconciliacion web tambien actualizan `status = 'paid'`.

## G. Estados reales comprobados

Valores reales usados por codigo/migraciones locales para `public.orders.status`:

- `draft`
- `pending_review`
- `pending_payment`
- `paid`
- `processing`
- `shipped`
- `delivered`
- `canceled`

Evidencia:

- Flutter traduce todos esos excepto que `processing` existe en UI pero no se vio en migracion local como transicion.
- Migraciones/RPC usan `pending_payment`, `draft`, `pending_review`, `canceled`, `paid`.
- Trigger de ventas usa `paid`, `delivered`, `canceled`.
- Politica RLS local restringe update cliente a `draft`, `pending_review`, `pending_payment`.

NO VERIFICADO EN REPOSITORIO: no se encontro en migraciones locales la definicion original de `public.orders`, ni un enum/check formal para `orders.status`. Por tanto no se puede afirmar desde este repo que la base limite estrictamente esos valores.

Estados reales usados para `shipping_status` T1:

- Migracion T1 define columna `shipping_status TEXT DEFAULT 'pending'`, sin enum/check local.
- Modelo Flutter mapea: `pending`, `label_created`, `ready_to_ship`, `picked_up`, `in_transit`, `out_for_delivery`, `delivered`, `exception`, `canceled`.

## H. Relacion Mercado Pago -> orders.status

Flutter:

- `startOrderPayment` invoca Edge Function `create-mp-order-preference`.
- `verifyOrderPayment` invoca Edge Function `verify-mp-order-payment`.
- Fallback lee `orders` y `order_payments`, pero no escribe.

Backend:

- `verify-mp-order-payment` consulta Mercado Pago y, si encuentra pago aprobado, llama RPC `reconcile_mercado_pago_payment`.
- `mercado-pago-webhook` valida firma, consulta Mercado Pago como fuente de verdad y llama RPC `reconcile_mercado_pago_payment`.
- `reconcile_mercado_pago_payment` es quien cambia `orders.status` a `paid` al aprobar.

NO VERIFICADO EN REPOSITORIO: `create-mp-order-preference` esta referenciada por Flutter, pero no existe en `supabase/functions` local. Solo hay `mercado-pago-webhook` y `verify-mp-order-payment`.

## I. Tracking T1

Archivos:

- `lib/models/tracking_info.dart`
- `lib/services/tracking_service.dart`
- `supabase/migrations/20260807150000_t1_minimal_tracking_infrastructure.sql`
- `supabase/migrations/20260807151000_t1_3_harden_tracking_privileges.sql`

Consulta shipment:

- `TrackingService.getShipmentForOrder(orderId)` revisa sesion; si no hay sesion retorna `null`.
- Consulta `customer_order_shipments`, filtra `order_id`, ordena por `created_at desc`, limita a 1 y usa `maybeSingle`.

Consulta eventos:

- Si hay shipment, usa `shipmentData['id']`.
- Consulta `customer_shipment_events`, filtra `shipment_id`, ordena por `event_at desc`.

Modelos:

- `ShipmentEvent`: `id`, `shipmentId`, `status`, `description`, `location`, `eventAt`.
- `OrderShipment`: `id`, `orderId`, `carrier`, `serviceName`, `trackingNumber`, `trackingUrl`, `shippingStatus`, `estimatedDelivery`, `events`.

Mapping de `shipping_status`:

- `pending` -> `En preparacion`, naranja.
- `label_created` -> `Guia generated`, naranja.
- `ready_to_ship` -> `Listo para envio`, azul.
- `picked_up` / `in_transit` -> `En camino`, azul.
- `out_for_delivery` -> `En reparto`, azul.
- `delivered` -> `Entregado`, verde.
- `exception` -> `Incidencia`, rojo.
- `canceled` -> `Cancelado`, rojo.

Fallback cuando no hay shipment:

- `TrackingService` retorna `null`.
- `order_detail_screen.dart` muestra fases basadas en `orders.status`: `shipped` -> paso envio, `delivered` -> paso entregado, otros -> preparando.

Manejo de errores:

- `TrackingService` captura cualquier excepcion y retorna `null`.

## J. Relacion orders.status vs shipping_status

El codigo existente permite que ambos evolucionen por separado:

- `orders.status = paid` puede coexistir con `shipping_status = in_transit`.
- La UI de detalle usa `orders.status` para el badge financiero/comercial y `_shipment.shippingStatus` para tracking logistico.
- `_buildOrderPhases` prioriza `shipping_status` si hay shipment, y usa `orders.status` solo cuando no hay tracking.

Arquitectura esperada con estados reales encontrados:

- Mercado Pago aprobado -> backend/RPC deja `orders.status = paid`.
- Guia SkyDropX creada -> backend crea/actualiza `order_shipments.shipping_status = label_created` o estado real equivalente recibido/mapeado.
- Paqueteria recoge/en transito -> backend actualiza `shipping_status = picked_up` o `in_transit`; entonces una sincronizacion backend puede promover `orders.status = shipped`.
- Entrega confirmada -> backend actualiza `shipping_status = delivered`; entonces promueve `orders.status = delivered`.

No se recomienda que Flutter promueva `paid` -> `shipped` -> `delivered`.

## K. Responsabilidad recomendada para sincronizacion

Opcion coherente con la arquitectura real: Edge Function/webhook backend con service role, apoyada por RPC transaccional si hay que tocar varias tablas.

Por que:

- Mercado Pago ya usa Edge Functions y RPC `SECURITY DEFINER` para conciliacion.
- Tracking T1 da permisos completos de `order_shipments` y `shipment_events` a `service_role`; el usuario autenticado solo lee vistas/columnas publicas.
- Los secretos de SkyDropX deben permanecer en backend.
- La decision `shipping_status -> orders.status` es estado autoritativo logistico/comercial y no debe depender del cliente movil.

Diseno recomendado sin implementar:

- Edge Function `skydropx-webhook` o worker backend recibe eventos/consulta tracking.
- Normaliza estados SkyDropX a los estados locales de `shipping_status`.
- Inserta eventos en `shipment_events`.
- Actualiza `order_shipments.shipping_status`.
- Llama RPC transaccional para promover `orders.status` solo en transiciones permitidas:
  - de `paid`/`processing` a `shipped` cuando `shipping_status` indique recogido/en transito/reparto.
  - a `delivered` cuando `shipping_status = delivered`.
  - no retroceder estados finales sin regla explicita.

## L. Preparacion para SkyDropX T2

Infraestructura reutilizable:

- Tablas base `order_shipments` y `shipment_events`.
- Campos listos para proveedor: `skydropx_shipment_id`, `carrier`, `service_name`, `tracking_number`, `tracking_url`, `label_url`, `estimated_delivery`.
- Vistas seguras para Flutter que excluyen `label_url` y `skydropx_shipment_id`.
- Permisos: service role puede insertar/actualizar; authenticated solo selecciona columnas/vistas seguras.
- Modelo Flutter y UI ya consumen carrier, servicio, guia, tracking_url, entrega estimada e historial de eventos.

T2 deberia incorporar:

- Credenciales SkyDropX solo como secrets de Edge Functions.
- Autenticacion SkyDropX en backend.
- Cotizacion y creacion de guia en backend.
- Persistencia de shipment y eventos en Supabase.
- Webhook o polling backend de tracking.
- Sin API keys en Flutter.

## M. Riesgos

- No hay enum/check local verificado para `orders.status`; podria haber estados existentes en Cloud no representados por las migraciones disponibles.
- `processing` aparece en UI, pero no se encontro transicion local que lo establezca.
- `create-mp-order-preference` no esta en `supabase/functions` local; falta contexto de creacion de preferencia.
- `order_detail_screen.dart` y `orders_screen.dart` estan modificados en worktree antes de esta auditoria; el analisis toma el contenido actual local.
- El badge de estado en Mis Pedidos podria overflow en algunos anchos/estados largos.
- `TrackingService` silencia errores retornando `null`; la UI no diferencia "sin envio" de "fallo al consultar tracking".
- `shipping_status` es `TEXT` sin check local; conviene normalizar/mantener mapping backend con cuidado.

## N. NO VERIFICADO

- Definicion original de `public.orders` en migraciones locales.
- Enum/check formal de `public.orders.status`.
- Estado real de Supabase Cloud.
- Existencia local de `supabase/functions/create-mp-order-preference`.
- Flujo SkyDropX real: no hay integracion local inspeccionada y no se hicieron llamadas externas.

## O. Evidencia

- Repo: `git rev-parse --show-toplevel` -> `C:/Users/cesar/Downloads/app_biomedica_pax-main`; `git branch --show-current` -> `main`.
- Flutter: `pubspec.yaml` contiene dependencia `flutter` y `supabase_flutter`.
- Mis Pedidos: `lib/screens/profile/orders_screen.dart:32-37`, `53-90`, `164-181`.
- Detalle: `lib/screens/profile/order_detail_screen.dart:31-44`, `68-166`, `632-656`, `796-797`.
- Tracking: `lib/services/tracking_service.dart:8-41`, `lib/models/tracking_info.dart:4-128`.
- Tracking DB: `supabase/migrations/20260807150000_t1_minimal_tracking_infrastructure.sql:10-17`, `25-31`, `82-139`.
- Hardening tracking: `supabase/migrations/20260807151000_t1_3_harden_tracking_privileges.sql:8-51`.
- Mercado Pago Flutter: `lib/services/mercado_pago_service.dart:74-168`, `171-211`.
- Mercado Pago webhook: `supabase/functions/mercado-pago-webhook/index.ts:365-382`.
- Verificacion MP: `supabase/functions/verify-mp-order-payment/index.ts:84-102`, `159-182`.
- Reconciliacion MP: `supabase/migrations/20260803000000_fix_mercado_pago_webhook_reconciliation.sql:23-190`.
- Checkout/reconciliacion web: `supabase/migrations/20260805120000_real_checkout.sql:9-247`, `249-461`.
- Ventas por estado: `supabase/migrations/20260713174205_migration_sales_count.sql:17-28`.
