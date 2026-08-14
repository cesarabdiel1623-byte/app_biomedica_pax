# Reporte T2.6 / T2.6.1 — Handoff Autoritativo SkyDropX → Mercado Pago

**Fecha**: 2026-08-10  
**Proyecto**: Go Medical  
**Estado**: Implementación exclusivamente LOCAL completada y probada. **Sin db push, sin despliegues en Supabase Cloud, sin transacciones ni cobros reales.**

---

## 1. Correcciones Obligatorias Aplicadas (T2.6.1)

1. **Eliminación del Monto Fijo de $10 en Mercado Pago**:
   - `create-mp-test-preference` ya **NO** hardcodea `unit_price: 10.0`.
   - Utiliza de forma estrictamente autoritativa el `payment_total` devuelto por `prepare_mp_order`:
     ```typescript
     const paymentTotal = getNumber(orderData, "payment_total");
     if (!paymentTotal || !Number.isFinite(paymentTotal) || paymentTotal <= 0) {
       return jsonResponse({ ok: false, error: "invalid_payment_total", message: "..." }, 500);
     }
     unit_price: Number(paymentTotal.toFixed(2))
     ```
   - **Ejemplo**: Para $3,500 de productos + $80 de envío, el total cobrado en la preferencia de Mercado Pago es **$3,580.00 MXN** (NO $10.00, NO $4,060.00, NO $4,140.00).

2. **SkyDropX Obligatorio en `create-mp-test-preference`**:
   - Exige la presencia simultánea de `cart_id`, `address_id`, `skydropx_quotation_id` y `skydropx_rate_id`.
   - Si falta cualquiera, retorna `missing_shipping_selection` (400) sin permitir envíos gratis accidentales por valores nulos.

3. **Protección Estricta de Permisos en `prepare_mp_order`**:
   - Para evitar manipulaciones directas desde clientes sin pasar por la Edge Function:
     ```sql
     REVOKE ALL ON FUNCTION public.prepare_mp_order(uuid, uuid, text, text, numeric, numeric, text) FROM PUBLIC;
     REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, text, text, numeric, numeric, text) FROM anon;
     REVOKE EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, text, text, numeric, numeric, text) FROM authenticated;
     GRANT EXECUTE ON FUNCTION public.prepare_mp_order(uuid, uuid, text, text, numeric, numeric, text) TO service_role;
     ```
   - Se confirmó que Flutter **NO** invoca la RPC directamente, sino a través de la Edge Function con la clave de servicio `service_role`.

4. **Idempotencia en `order_payments`**:
   - Cuando una orden en estado `pending_payment` es reutilizada (`v_reused = true`), `prepare_mp_order` busca un intento existente con estado `'pending'::public.payment_record_status`.
   - Si existe, **actualiza** `amount = v_payment_total` y `updated_at = now()`, en lugar de insertar una fila duplicada.
   - Si no existe, inserta una única fila completando todos los campos requeridos por las constraints de Cloud (`client_id`, `provider = 'mercado_pago'`, `environment = 'test'`, `external_reference = v_order_number`, `currency_id = 'MXN'`).

5. **Manejo Controlado de Respuestas SkyDropX**:
   - `parseJsonResponse(quoteRes)` está envuelto en bloque `try-catch` para interceptar respuestas JSON malformadas o errores de red de SkyDropX, retornando respuestas sanitizadas (`skydropx_invalid_response` o `skydropx_network_error`).

---

## 2. Archivos Modificados / Creados

### Migraciones y Funciones Backend:
1. **[supabase/migrations/20260810140000_t2_6_skydropx_mp_handoff.sql](file:///c:/Users/cesar/Downloads/app_biomedica_pax-main/supabase/migrations/20260810140000_t2_6_skydropx_mp_handoff.sql)** [LOCAL]
2. **[supabase/functions/create-mp-test-preference/index.ts](file:///c:/Users/cesar/Downloads/app_biomedica_pax-main/supabase/functions/create-mp-test-preference/index.ts)** [LOCAL]

### Flutter & Pruebas Unitarias:
3. **[lib/services/mercado_pago_test_service.dart](file:///c:/Users/cesar/Downloads/app_biomedica_pax-main/lib/services/mercado_pago_test_service.dart)**
4. **[lib/screens/home/widgets/checkout_sheet.dart](file:///c:/Users/cesar/Downloads/app_biomedica_pax-main/lib/screens/home/widgets/checkout_sheet.dart)**
5. **[test/services/mercado_pago_test_service_test.dart](file:///c:/Users/cesar/Downloads/app_biomedica_pax-main/test/services/mercado_pago_test_service_test.dart)**

---

## 3. Pruebas Numéricas y de Seguridad

| Caso | Productos | Tarifa Elegida | Base Gratis | Cobro Envío Cliente | Preference Mercado Pago | Estatus |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Caso A** | $3,500.00 | $80.00 (Standard) | N/A (< $5,000) | $80.00 | **$3,580.00 MXN** | **ÉXITO** |
| **Caso B** | $5,000.00 | $80.00 (Standard) | $80.00 | $0.00 | **$5,000.00 MXN** | **ÉXITO** |
| **Caso C** | $6,000.00 | $220.00 (UPS Saver) | $80.00 | $140.00 | **$6,140.00 MXN** | **ÉXITO** |
| **Caso D** | $6,000.00 | $350.00 (DHL Express) | $80.00 | $270.00 | **$6,270.00 MXN** | **ÉXITO** |

### Pruebas de Seguridad Adicionales:
- **Missing Quotation / Rate**: Rechazado con `missing_shipping_selection` (400).
- **Invocación directa a `prepare_mp_order` desde cliente**: Denegada por `REVOKE TO authenticated/anon`.
- **Segunda llamada idéntica de preferencia**: Reutiliza la orden y actualiza la fila `order_payments` existente sin duplicar ni romper constraints.

### Resultados de Suite Flutter:
- `flutter test`: **50/50 tests passed!**
- `flutter analyze`: **No issues found!**

---

## 4. Git Diff Stat

```text
 lib/screens/home/widgets/checkout_sheet.dart       |   8 +-
 lib/services/mercado_pago_test_service.dart        |  19 +-
 reporte_t2_6_shipping_payment_handoff.md           |  84 ++++++
 supabase/functions/create-mp-test-preference/      | 285 ++++++++++++++++++++
 .../20260810140000_t2_6_skydropx_mp_handoff.sql     | 255 ++++++++++++++++++
 test/services/mercado_pago_test_service_test.dart |  16 +-
```
