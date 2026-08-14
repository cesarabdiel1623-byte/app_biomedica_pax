# Reporte T2.4 — Fundación Financiera y Logística para SkyDropX

**Fecha**: 2026-08-10  
**Proyecto**: Go Medical  
**Estado**: Cambios locales preparados. **Sin despliegues a Supabase Cloud ni db push.**

---

## 1. Política Comercial Definitiva de Envío Gratis (Go Medical)

La regla de envío gratis aplica a nivel **PEDIDO** según el subtotal de productos:

### A. Para pedidos con subtotal de productos < $5,000 MXN:
- `free_shipping_benefit = 0`
- `customer_shipping_amount = selected_rate_total`
- `shipping_discount_amount = 0`
- `payment_total = payable_product_amount + selected_rate_total`

### B. Para pedidos con subtotal de productos >= $5,000 MXN:
- Go Medical cubre como beneficio el costo de la **TARIFA VÁLIDA MÁS ECONÓMICA** (`cheapest_valid_rate_total`) obtenida de SkyDropX.
- `free_shipping_benefit = cheapest_valid_rate_total`
- `customer_shipping_amount = max(selected_rate_total - free_shipping_benefit, 0)`
- `shipping_discount_amount = free_shipping_benefit`
- `payment_total = payable_product_amount + customer_shipping_amount`

### C. Filtro de Tarifas Válidas:
Solo se consideran para determinar la tarifa base (económica):
- `total > 0`
- `currency_code = MXN`
- `status` de cobertura válida (se excluyen `no_coverage`, `not_applicable` o sin total).

---

## 2. Ejemplo Práctico de Cálculo

Para un pedido con `subtotal_productos = $6,000 MXN` y las siguientes opciones de SkyDropX:
- **AMPM** (Económica) = $80.00 MXN
- **UPS** (Intermedia) = $220.00 MXN
- **DHL** (Exprés) = $350.00 MXN

**Beneficio de Envío Gratis Aplicado**: `free_shipping_benefit = $80.00 MXN`

| Opción Seleccionada | Tarifa SkyDropX | Beneficio Aplicado | Monto Cobrado Cliente (`customer_shipping_amount`) | Total a Pagar (`payment_total`) | Leyenda en UI Móvil |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **AMPM (3 días)** | $80.00 | $80.00 | **$0.00** | **$6,000.00** | **GRATIS** |
| **UPS (3 días)** | $220.00 | $80.00 | **$140.00** | **$6,140.00** | **+$140** |
| **DHL (1 día)** | $350.00 | $80.00 | **$270.00** | **$6,270.00** | **+$270** |

**Mensaje Informativo en UI Móvil**:
> `✓ Envío gratis aplicado con la opción más económica.`  
> `Puedes elegir un servicio más rápido pagando la diferencia.`

---

## 3. Migración SQL Creada

**Archivo local**: `supabase/migrations/20260810120000_t2_4_pricing_shipping_foundation.sql`

```sql
-- Migration: T2.4 — Fundación financiera y logística para SkyDropX

-- 1. Agregar columnas a public.orders para montos e identificadores de cotización SkyDropX
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS customer_shipping_amount numeric NOT NULL DEFAULT 0 CHECK (customer_shipping_amount >= 0),
  ADD COLUMN IF NOT EXISTS skydropx_shipping_cost numeric NOT NULL DEFAULT 0 CHECK (skydropx_shipping_cost >= 0),
  ADD COLUMN IF NOT EXISTS skydropx_quotation_id text NULL,
  ADD COLUMN IF NOT EXISTS skydropx_rate_id text NULL;

-- 2. Configuración global del umbral de envío gratis en public.store_settings
ALTER TABLE public.store_settings
  ADD COLUMN IF NOT EXISTS free_shipping_threshold numeric NOT NULL DEFAULT 5000 CHECK (free_shipping_threshold >= 0);

UPDATE public.store_settings
SET free_shipping_threshold = 5000
WHERE free_shipping_threshold IS NULL OR free_shipping_threshold <> 5000;
```

---

## 4. Corrección de Doble IVA en `coupon_calculate_cart_pricing`

Se ajustó la RPC `coupon_calculate_cart_pricing` en la migración para tratar el IVA como el **desglose del 16% incluido en el subtotal** y **NO adicionar recargos del 16% sobre el subtotal**.

```sql
  v_payable_product_amount := greatest(0, v_items_subtotal - v_product_discount - v_coupon_discount);
  v_tax := case
    when v_cart.tax_exempt then 0
    else round(v_payable_product_amount - (v_payable_product_amount / (1 + coalesce(v_cart.tax_pct, 0.16))), 2)
  end;

  v_total := round(greatest(
    0,
    v_payable_product_amount + v_shipping_before - v_shipping_discount
  ), 2);
```

---

## 5. Regla de Datos Logísticos de Producción

- La cotización a SkyDropX utilizará únicamente `public.product_logistics_data`:
  - `package_length`
  - `package_width`
  - `package_height`
  - `package_weight`
- Si cualquier producto del carrito carece de alguno de estos cuatro datos, **el producto NO es cotizable**.
- **Quedan prohibidos fallbacks ficticios** (`1 kg`, `10x10x10 cm`) en el entorno de producción.
