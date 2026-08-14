# T2.2 - Auditoria rapida de datos para cotizacion SkyDropX

## Resumen

Auditoria de solo lectura para preparar `POST /api/v2/quotations`. No se reviso OAuth SkyDropX, no se llamo SkyDropX, no se modifico Flutter, Supabase, S1, Mercado Pago, Edge Functions ni Cloud.

MCP Supabase no esta disponible en este chat. Se intento descubrir herramientas/recursos MCP y solo aparecen recursos de plantillas/Sites, no una conexion de base de datos. Por eso la orden `ORD-20260803-809B2BBB` no pudo consultarse en Cloud desde aqui.

## A. productos

No encontre columnas fisicas estructuradas en `products` ni tablas relacionadas que almacenen peso/dimensiones con estos nombres:

- `weight`, `peso`
- `length`, `largo`
- `width`, `ancho`
- `height`, `alto`
- `depth`
- `dimensiones`, `dimension`
- `package_weight`, `package_length`, `package_width`, `package_height`

Evidencia local:

| tabla | columna | tipo | nullable | evidencia |
|---|---|---|---|---|
| `products` | `shipping_info` | no demostrado en migracion local; modelo `String?` | si en modelo | `lib/services/product_service.dart:32`, `lib/models/product.dart:29`, `lib/models/product.dart:219` |
| `product_specs` | `spec_key` | no demostrado en migracion local; modelo `String` | no en modelo | `lib/services/product_service.dart:45`, `lib/models/product.dart:356` |
| `product_specs` | `spec_value` | no demostrado en migracion local; modelo `String` | no en modelo | `lib/services/product_service.dart:46`, `lib/models/product.dart:357` |

`product_specs` podria contener especificaciones tecnicas arbitrarias, pero no hay evidencia local de que peso/largo/ancho/alto existan como datos normalizados ni con unidades. No se deben inventar valores.

## B. order_items

`public.order_items` guarda el desglose comercial y snapshots del producto al crear la orden.

Columnas demostradas por `prepare_web_checkout_order`:

| tabla | columna | tipo | nullable | evidencia |
|---|---|---|---|---|
| `order_items` | `order_id` | no demostrado en migracion local | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:224` |
| `order_items` | `product_id` | `uuid` inferido desde `cart_items.product_id`; no definido localmente | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:214`, `:224` |
| `order_items` | `sku_snapshot` | no demostrado | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:225` |
| `order_items` | `product_name_snapshot` | no demostrado | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:225` |
| `order_items` | `product_category_snapshot` | no demostrado | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:226` |
| `order_items` | `quantity` | numerico/integer no definido localmente | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:88`, `:226` |
| `order_items` | `unit_price` | numerico no definido localmente | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:141`, `:226` |
| `order_items` | `total_line_price` | numerico no definido localmente | no demostrado | `supabase/migrations/20260805120000_real_checkout.sql:226`, `:230` |

Flutter lee `order_items` y usa `quantity`, `unit_price`, `total_line_price`, `product_name_snapshot`; tambien hace join a `products` solo para marca/media de UI. No se encontro peso/dimensiones en `order_items`.

Conclusion para cotizacion: si en el futuro se agregan datos fisicos a producto, la cotizacion debe ir `order_items -> products` o a una tabla fisica relacionada. Hoy esa informacion no existe normalizada en `order_items`.

## C. destino

La app captura una direccion estructurada en pantalla y la guarda en `client_addresses`.

Campos de captura:

- calle/lugar: `_addressController`
- municipio: `_cityController`
- estado: `_stateController`
- codigo postal: `_postalCodeController`
- localidad: `_localityController`
- colonia: `_neighborhoodController`
- interior: `_interiorController`
- indicaciones: `_instructionsController`
- receptor: `_recipientNameController`
- telefono receptor: `_recipientPhoneController`

Evidencia: `lib/screens/home/address_picker_screen.dart:24-33`, `:378-387`, `:1103-1341`.

Persistencia real:

| tabla | columna | tipo | nullable | contenido |
|---|---|---|---|---|
| `client_addresses` | `address` | no demostrado en migracion local; modelo `String` | no en modelo | texto multilinea etiquetado: Direccion, Interior, Colonia, Localidad, Municipio, Estado, Codigo postal, Indicaciones, Recibe, Telefono |
| `client_addresses` | `city` | no demostrado; modelo `String?` | si en modelo | municipio/ciudad |
| `client_addresses` | `state` | no demostrado; modelo `String?` | si en modelo | estado |
| `client_addresses` | `postal_code` | no demostrado; modelo `String?` | si en modelo | CP |
| `client_addresses` | `latitude` | no demostrado; modelo `double?` | si en modelo | coordenada |
| `client_addresses` | `longitude` | no demostrado; modelo `double?` | si en modelo | coordenada |
| `client_addresses` | `is_default` | no demostrado; modelo `bool?` con fallback | si en modelo | direccion principal |

`AddressService` parsea el campo `address` por etiquetas para extraer `streetAddress`, `municipality`, `locality`, `neighborhood`, `interior`, `instructions`, `recipientName`, `recipientPhone`. Evidencia: `lib/services/address_service.dart:25-92`, `:96-107`, `:139-157`.

`order_detail_screen.dart` muestra `orders.shipping_address` como texto en detalle del pedido, no vuelve a leer `client_addresses`. Evidencia: `lib/screens/profile/order_detail_screen.dart:680`, `:691`. La RPC de checkout web guarda `orders.shipping_address` como `concat_ws(', ', address, city, state, postal_code)`, por lo que puede perder estructura si depende solo de ese snapshot. Evidencia: `supabase/migrations/20260805120000_real_checkout.sql:74-78`, `:204-207`.

Mapeo posible a `address_to`:

- CP: `client_addresses.postal_code` o etiqueta `Codigo postal` dentro de `address`
- estado: `client_addresses.state` o etiqueta `Estado`
- municipio: `client_addresses.city` o etiqueta `Municipio`
- colonia: etiqueta `Colonia`
- calle/numero exterior: etiqueta `Direccion` en `address`
- numero interior: etiqueta `Interior`
- referencias/indicaciones: etiqueta `Indicaciones`
- nombre receptor: etiqueta `Recibe`
- telefono receptor: etiqueta `Telefono`

Advertencia: no encontre `address_id` persistido en `orders`; solo snapshot `shipping_address`. Para cotizar una orden ya creada, podria faltar una FK directa a `client_addresses`.

## D. origen

Existe `store_settings`, pero no contiene direccion de origen/remitente.

| tabla | columna | tipo | nullable | evidencia |
|---|---|---|---|---|
| `store_settings` | `store_name` | `TEXT` | `NOT NULL` | `supabase/migrations/20260701200419_create_store_settings_table.sql:4` |
| `store_settings` | `whatsapp_number` | `TEXT` | nullable | `supabase/migrations/20260701200419_create_store_settings_table.sql:11` |
| `store_settings` | `contact_email` | `TEXT` | nullable | `supabase/migrations/20260701200419_create_store_settings_table.sql:12` |

No encontre en migraciones locales tablas `warehouses`, `company_settings`, `shipping_settings` ni direccion empresarial/origen con calle, numero, colonia, municipio, estado, CP, telefono y correo. La documentacion menciona inventario por almacen, pero no hay definicion local de tabla ni relacion verificable con pedido.

## E. paquetes

T1 creo `order_shipments` con soporte multipaquete: no hay `UNIQUE(order_id)` y el comentario indica multiples paquetes futuros. Evidencia: `supabase/migrations/20260807150000_t1_minimal_tracking_infrastructure.sql:7-18`.

Campos existentes en `order_shipments`: `id`, `order_id`, `skydropx_shipment_id`, `carrier`, `service_name`, `tracking_number`, `tracking_url`, `label_url`, `shipping_status`, `estimated_delivery`, `created_at`, `updated_at`.

No encontre logica actual para agrupar productos de una orden en uno o varios paquetes antes de crear un shipment. Tampoco encontre campos de paquete como peso/largo/ancho/alto por shipment o parcel.

## F. orden de prueba

Orden solicitada: `ORD-20260803-809B2BBB`.

No se pudo consultar por MCP porque no hay herramienta Supabase/base de datos disponible en este chat. No se uso ninguna alternativa con secretos locales, no se modifico la orden y no se modifico el shipment ficticio.

Consulta que se habria realizado en modo lectura:

```sql
select
  o.id,
  o.order_number,
  o.client_id,
  o.shipping_address,
  o.status,
  oi.product_id,
  oi.quantity,
  oi.sku_snapshot,
  oi.product_name_snapshot,
  oi.unit_price,
  oi.total_line_price
from public.orders o
left join public.order_items oi on oi.order_id = o.id
where o.order_number = 'ORD-20260803-809B2BBB';
```

Y, si existieran campos fisicos en Cloud:

```sql
select
  p.id,
  p.weight,
  p.length,
  p.width,
  p.height
from public.products p
where p.id in (...product_ids_de_la_orden...);
```

## G. matriz de disponibilidad

| DATO | EXISTE | FUENTE |
|---|---|---|
| origen CP | no | no hay direccion de origen en `store_settings` ni tabla local equivalente |
| origen estado | no | no hay direccion de origen en `store_settings` ni tabla local equivalente |
| destino CP | si | `client_addresses.postal_code` y etiqueta en `address`; `orders.shipping_address` solo snapshot texto |
| destino estado | si | `client_addresses.state` y etiqueta en `address`; `orders.shipping_address` solo snapshot texto |
| peso | no | no hay columna normalizada encontrada en `products`, `order_items`, `order_shipments` |
| largo | no | no hay columna normalizada encontrada |
| ancho | no | no hay columna normalizada encontrada |
| alto | no | no hay columna normalizada encontrada |
| cantidad | si | `order_items.quantity` |
| telefono receptor | si | etiqueta `Telefono` dentro de `client_addresses.address`; no estructurado como columna propia |
| nombre receptor | si | etiqueta `Recibe` dentro de `client_addresses.address`; no estructurado como columna propia |

## H. datos faltantes

¿Podemos construir actualmente un payload valido de cotizacion SkyDropX usando unicamente datos reales de Go Medical?

NO

Datos faltantes:

- origen CP
- origen estado
- origen municipio
- origen calle/numero/colonia
- origen telefono/correo de remitente estructurado
- peso
- largo
- ancho
- alto
- unidades normalizadas de peso y dimensiones
- datos de paquete/parcel para una o varias cajas

## I. archivos revisados

1. `supabase/migrations/20260805120000_real_checkout.sql`
2. `lib/services/address_service.dart`
3. `lib/screens/home/address_picker_screen.dart`
4. `lib/screens/profile/order_detail_screen.dart`
5. `lib/models/product.dart`
6. `lib/services/product_service.dart`
7. `supabase/migrations/20260701200419_create_store_settings_table.sql`
8. `supabase/migrations/20260807150000_t1_minimal_tracking_infrastructure.sql`
9. `lib/screens/home/widgets/checkout_sheet.dart`
10. `informe_supabase_backend_capitulo_4.md`
11. `documentacion_proyecto.txt`
12. `informe_tecnico_app_movil_capitulo_4.md`

Total: 12 archivos revisados.

## J. consultas realizadas

Busquedas locales de solo lectura:

- `rg -n -i "weight|peso|width|ancho|height|alto|length|largo|depth|dimensiones|dimension|package|package_weight|package_length|package_width|package_height|parcel|box|shipment|warehouse|store_settings|shipping settings|company|address|direccion|dirección" .`
- `rg -n -i "create table.*order_items|public\.order_items|order_items\s*\(" supabase/migrations ...`
- `rg -n -i "CREATE TABLE|client_addresses|products|order_items" supabase`
- `rg -n -i "warehouse|warehouses|inventory_movements|product_inventory|stock|almacen|almacén" supabase/migrations lib/services lib/models`

MCP:

- `tool_search`: no encontro herramienta Supabase.
- `list_mcp_resources`: solo mostro recursos `codex_apps` de plantillas/Sites; sin conexion de base de datos.
