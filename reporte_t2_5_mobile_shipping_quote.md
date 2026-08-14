# Reporte T2.5 — Conectar Cotización SkyDropX al Checkout Móvil (Correcciones Finales)

**Fecha**: 2026-08-10  
**Proyecto**: Go Medical  
**Estado**: Implementación exclusivamente LOCAL completada y verificada. **Sin despliegues en Supabase Cloud, sin db push y sin cobros reales.**

---

## 1. Correcciones de Backend Aplicadas en `skydropx-mobile-quote`

Se actualizó la Edge Function local en [supabase/functions/skydropx-mobile-quote/index.ts](file:///c:/Users/cesar/Downloads/app_biomedica_pax-main/supabase/functions/skydropx-mobile-quote/index.ts):

1. **Payload SkyDropX Top-Level Wrapper**:
   - `POST /api/v1/quotations` utiliza el envoltorio en el nivel superior `quotation`:
     ```json
     {
       "quotation": {
         "address_from": { ... },
         "address_to": { ... },
         "parcels": [ ... ]
       }
     }
     ```
2. **Ajuste de Polling y Timeouts**:
   - Polling de 2000 ms por intento (máximo 5 intentos).
   - Si tras 5 intentos `is_completed !== true`, responde con error explícito:
     ```json
     {
       "ok": false,
       "error": "quotation_still_processing",
       "message": "La cotización aún se encuentra procesando en el proveedor logístico."
     }
     ```
3. **`quotation_id` Obligatorio**:
   - Valida la existencia de `id` devuelto por SkyDropX. Si falta, responde con error `missing_quotation_id`.
4. **Validación Estricta de Dirección (`address_id`)**:
   - Si Flutter envía `address_id` y este no existe o no pertenece al cliente autenticado, devuelve error `shipping_address_not_found` (404) sin hacer fallback silencioso a la dirección por defecto.
5. **Extracción Segura de Colonia (`area_level3`)**:
   - Implementa un extractor `extractNeighborhood` que analiza el texto estructurado o delimitado por comas de `client_addresses.address`.
   - Si no es posible determinar una colonia válida, responde con `invalid_shipping_address` (400) sin inventar la colonia.
6. **Encapsulamiento del Origen Sandbox**:
   - La dirección del remitente Sandbox se encapsula en la constante `SKYDROPX_SANDBOX_TEST_ORIGIN`:
     ```typescript
     const SKYDROPX_SANDBOX_TEST_ORIGIN = {
       country_code: "MX",
       postal_code: "97392",
       area_level1: "Yucatán",
       area_level2: "Umán",
       area_level3: "Piedra de Agua",
     };
     ```
7. **Validación de Configuración de Servidor**:
   - Valida la presencia de `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY`. Si falta alguna, devuelve `missing_server_configuration` (500) sin exponer secretos.

---

## 2. Conexión Completa en Flutter

- **`lib/services/shipping_quote_service.dart`**: Cliente de servicio para invocar `skydropx-mobile-quote`.
- **`lib/screens/home/widgets/checkout_sheet.dart`**:
  - Al abrir o cambiar de dirección, muestra en tiempo real `Calculando opciones de envío...`.
  - Si un producto carece de peso o dimensiones (`product_not_shippable`), despliega una alerta roja indicando el producto no cotizable y **bloquea la continuación al pago**.
  - Si la cotización es exitosa, despliega la lista de tarifas disponibles con sus días estimados y costo (`GRATIS`, `+$140.00`, `+$270.00`).
  - Para pedidos `>= $5,000`, muestra la barra verde informativa:
    > `✓ Envío gratis aplicado con la opción más económica. Puedes elegir un servicio más rápido pagando la diferencia.`
  - Al seleccionar una opción de envío, almacena internamente la tarifa elegida (`quotationId`, `rateId`, `carrier`, `service`, `actualShippingCost`, `customerShippingAmount`, `shippingDiscountAmount`) para el handoff posterior.

---

## 3. Propuesta de Handoff hacia `prepare_mp_order` (Fase Posterior)

Actualmente el botón de pago **NO envía estos montos** a `prepare_mp_order`. Cuando se habilite en la siguiente fase:

1. Flutter enviará al backend:
   ```json
   {
     "cart_id": "...",
     "address_id": "...",
     "skydropx_quotation_id": "...",
     "skydropx_rate_id": "..."
   }
   ```
2. `prepare_mp_order` (o la Edge Function backend de preferencia) re-validará la tarifa seleccionada directamente contra la cotización del servidor.
3. El backend recalculará `payable_product_amount`, `cheapest_valid_rate_total` y `customer_shipping_amount = max(actual_cost - discount, 0)`, generando el cobro en Mercado Pago de forma autoritativa.
