# Reporte S1 - Sincronizacion shipping_status -> orders.status

## Alcance

Se preparo una migracion local para agregar la funcion explicita:

`public.sync_order_status_from_shipping(p_shipment_id UUID)`

La funcion no confia en un `shipping_status` suministrado externamente. Recibe el `shipment_id`, consulta `order_shipments.order_id` y, bajo bloqueo, usa como fuente autoritativa el `order_shipments.shipping_status` persistido en PostgreSQL.

No se conecto SkyDropX, no se agrego trigger automatico, no se ejecuto migracion, no se hizo `db push`, no se modifico Flutter, Mercado Pago, secretos, Edge Functions ni Supabase Cloud.

## Compatibilidad con sales_count

La evaluacion de compatibilidad usa como fuente de verdad la funcion actualmente desplegada en Supabase Cloud:

- Estados contados: `paid`, `processing`, `shipped`, `delivered`.
- Transiciones logisticas esperadas:
  - `paid -> shipped`: sin cambio en `sales_count`.
  - `shipped -> delivered`: sin cambio en `sales_count`.
  - `paid -> shipped -> delivered`: no produce doble conteo.

No se modifico `public.update_product_sales_count()` ni `trigger_update_sales_count`.

## Reglas implementadas

Estados logisticos que no cambian `orders.status`:

- `pending`
- `label_created`
- `ready_to_ship`
- `exception`
- `canceled`

Estados logisticos que promueven a `shipped` cuando la transicion comercial es valida:

- `picked_up`
- `in_transit`
- `out_for_delivery`

Estado logistico que promueve a `delivered` cuando la transicion comercial es valida:

- `delivered`

La promocion a `delivered` requiere que todos los `order_shipments` existentes para la misma orden tengan `shipping_status = delivered`.

Si el shipment procesado esta en `delivered`, pero todavia hay otros shipments en cualquier otro estado logistico, la orden no pasa a `delivered`. En ese caso:

- si la orden esta en `paid` o `processing`, se promueve como maximo a `shipped`
- si la orden ya esta en `shipped`, se conserva `shipped`
- el JSON retorna `waiting_for_remaining_shipments`, `total_shipments` y `delivered_shipments`

## Bloqueos transaccionales

La funcion realiza:

- consulta inicial de `order_shipments.order_id` para identificar la orden
- `SELECT ... FROM public.orders WHERE id = shipment.order_id FOR UPDATE`
- `SELECT ... FROM public.order_shipments WHERE order_id = ... ORDER BY id FOR UPDATE`
- relectura del shipment procesado bajo el conjunto bloqueado

Con esto sincroniza usando el estado logistico almacenado y evalua la condicion multipaquete sobre todas las filas de envio de la orden durante la operacion.

## Protecciones

La funcion preserva el estado comercial y reporta bloqueo en JSON para:

- `delivered -> shipped`
- cualquier intento de revivir una orden `canceled` hacia `shipped` o `delivered`

Tambien evita promociones desde estados no pagados/no logisticos como `draft`, `pending_review` o `pending_payment`.

## Campos no modificados

La funcion solo actualiza:

- `orders.status`
- `orders.updated_at`, unicamente cuando `status` cambia

No modifica:

- `orders.payment_status`
- `orders.paid_at`
- `orders.payment_id`

## Seguridad

La funcion es `SECURITY DEFINER`, con `search_path` fijado a `pg_catalog, public`.

Permisos:

- `REVOKE EXECUTE` para `PUBLIC`
- `REVOKE EXECUTE` para `anon`
- `REVOKE EXECUTE` para `authenticated`
- `GRANT EXECUTE` para `service_role`

## Evaluacion estatica solicitada

| Estado inicial de orden | Estado logistico | Resultado esperado |
|---|---|---|
| `paid` | `label_created` | `paid` |
| `paid` | `in_transit` | `shipped` |
| `processing` | `picked_up` | `shipped` |
| `shipped` | `in_transit` | `shipped` |
| `shipped` | `delivered` | `delivered` |
| `delivered` | `in_transit` | `delivered` |
| `canceled` | `in_transit` | `canceled` |
| `canceled` | `delivered` | `canceled` |

## Evaluacion estatica multipaquete

| Shipments de la orden | Estado inicial de orden | Resultado esperado |
|---|---|---|
| 1 shipment: `delivered` | `paid` | `delivered` |
| 2 shipments: A=`delivered`, B=`in_transit` | `paid` | `shipped` |
| 2 shipments: A=`delivered`, B=`in_transit` | `shipped` | `shipped` |
| 2 shipments: A=`delivered`, B=`delivered` | `shipped` | `delivered` |
| 2 shipments: A=`delivered`, B=`exception` | `paid` o `shipped` | no pasa a `delivered`; espera restantes |
| todos los shipments `delivered` | `canceled` | `canceled` |

## Archivo creado

- `supabase/migrations/20260808180000_sync_order_status_from_shipping.sql`
