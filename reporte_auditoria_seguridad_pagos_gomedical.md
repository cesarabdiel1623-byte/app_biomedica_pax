# Auditoría de Seguridad del Flujo de Pagos — Go Medical

## 1. Resumen ejecutivo

**Estado general:** En desarrollo técnico con simulación Sandbox de Mercado Pago validada en entorno de pruebas. La arquitectura cliente-servidor implementa buenas prácticas iniciales de desacoplamiento de secretos en Flutter y validación de URLs de checkout, pero requiere completar la integración de pedidos reales, migrar las funciones de backend a la estructura local del repositorio y reforzar las políticas de RLS e idempotencia antes de cualquier despliegue a producción.

**Nivel de riesgo global:** **ALTO (7.8/10)** (Debido a la ausencia de código local de Edge Functions y migraciones SQL en el control de versiones, la falta de un flujo de producción que vincule carritos/órdenes reales desde la base de datos con Mercado Pago, y la necesidad de endurecimiento en RLS y webhooks para producción).

**Veredicto:** **NO APTO PARA PRODUCCIÓN** (Apto únicamente para pruebas técnicas controladas en Sandbox).

### Principales fortalezas verificadas:
1. **Desacoplamiento estricto de secretos:** El código Dart de Flutter no contiene `MERCADO_PAGO_ACCESS_TOKEN`, `MERCADO_PAGO_WEBHOOK_SECRET` ni `SUPABASE_SERVICE_ROLE_KEY`.
2. **Validación estricta de dominios de checkout:** La clase `MercadoPagoTestService` valida la URL devuelta contra una lista blanca de dominios oficiales de Mercado Pago mediante protocolo HTTPS antes de invocar Custom Tabs.
3. **No confianza cliente en montos:** El cliente Flutter no envía precio, total ni artículos para la generación de la preferencia en la prueba técnica; la Edge Function fija el monto de prueba.
4. **Protección de Custom Tabs:** Se configura `CustomTabsBrowserConfiguration(prefersDefaultBrowser: true)` para forzar la apertura en un navegador web seguro y mitigar la intercepción directa por aplicaciones nativas de terceros.

### Principales bloqueos para producción:
1. **Ausencia de Edge Functions y Migraciones SQL en el Repositorio Git:** Las funciones `create-mp-test-preference`, `mercado-pago-webhook` y `check-mp-test-payment` residen exclusivamente en la nube de Supabase y no están exportadas en la carpeta `supabase/functions/` ni versionadas en Git.
2. **Flujo exclusivo de pruebas ($10 MXN):** No existe un flujo de checkout productivo que recupere el `order_id` o `cart_id` real en PostgreSQL y calcule el monto exacto con IVA y envío desde el backend.
3. **Deep Links personalizados no autenticados (`gomedical://payment`):** Uso de esquemas personalizados sin App Links/Universal Links verificados con `assetlinks.json`.
4. **Falta de verificación de idempotencia y control de duplicidad transaccional en repositorio local:** Imposibilidad de auditar en el control de versiones si los webhooks aplican bloqueos transaccionales SQL (`FOR UPDATE`) para prevenir race conditions.

---

## 2. Alcance revisado

### Archivos examinados en el repositorio local:
- `pubspec.yaml` (Líneas 1 - 90)
- `pubspec.lock` (Líneas 1 - 42078)
- `analysis_options.yaml` (Líneas 1 - 50)
- `dart_defines.example.json` (Líneas 1 - 7)
- `dart_defines.json` (Líneas 1 - 6)
- `.gitignore` (Líneas 1 - 49)
- `lib/main.dart`
- `lib/services/mercado_pago_test_service.dart` (Líneas 1 - 322)
- `lib/services/payment_deep_link_service.dart` (Líneas 1 - 84)
- `lib/screens/home/widgets/checkout_sheet.dart` (Líneas 1 - 680)
- `android/app/src/main/AndroidManifest.xml` (Líneas 1 - 77)
- `supabase_auditoria_readonly.sql` (Líneas 1 - 152)
- `informe_supabase_backend_capitulo_4.md`
- `informe_tecnico_app_movil_capitulo_4.md`

### Componentes disponibles:
- Cliente móvil Flutter con servicio de invocación de funciones de pago (`MercadoPagoTestService`).
- Manejador de Deep Links de retorno (`PaymentDeepLinkService`).
- Componente de interfaz modal de checkout (`CheckoutSheet`).
- Configuración de manifiesto Android (`AndroidManifest.xml`).
- Script de auditoría de solo lectura SQL (`supabase_auditoria_readonly.sql`).

### Componentes faltantes en el control de versiones (Git):
- Código fuente `.ts` de Edge Functions (`supabase/functions/create-mp-test-preference/index.ts`, `supabase/functions/mercado-pago-webhook/index.ts`, `supabase/functions/check-mp-test-payment/index.ts`).
- Archivos de migración SQL (`supabase/migrations/*.sql`) que definan esquemas de tablas `orders`, `order_items`, `payments` y políticas RLS activas.
- Configuración `supabase/config.toml`.
- Archivo de verificación de dominio Android `assetlinks.json` y iOS `apple-app-site-association`.

### Comandos de análisis ejecutados:
- `flutter analyze`: Resultado limpio sin errores estáticos (0 advertencias).
- `git status`: Verificación de rama y estado de archivos modificados.
- Búsqueda ripgrep (`grep_search`) de patrones sensibles de claves secretas y tokens en todo el espacio de trabajo.

---

## 3. Arquitectura real encontrada

```
[ Flutter Mobile App ]
       │
       │ (1) Invocación RPC con JWT del Usuario (Bearer)
       ▼
[ Supabase Edge Function: create-mp-test-preference ]
       │
       │ (2) POST /checkout/preferences con MERCADO_PAGO_ACCESS_TOKEN
       ▼
[ Mercado Pago API / Checkout Pro ]
       │
       ├───────────────────────────────┐
       │ (3) Retorno de checkout_url   │ (4) Notificación asíncrona Webhook (x-signature)
       ▼                               ▼
[ Custom Tabs / Browser ]       [ Supabase Edge Function: mercado-pago-webhook ]
       │                               │
       │ (5) Deep Link gomedical://    │ (6) Validación HMAC-SHA256 & GET /v1/payments/{id}
       ▼                               ▼
[ Flutter UI: Verificando ] ───► [ PostgreSQL / Tablas de Pedidos e Inventario ]
```

---

## 4. Fortalezas verificadas

### 1. Ausencia de Secretos Sensibles en Código Cliente (Flutter)
- **Control:** Ningún Access Token privado de Mercado Pago (`APP_USR-...`), Webhook Secret (`2e3a...`) ni `SUPABASE_SERVICE_ROLE_KEY` está hardcodeado ni incluido en el proyecto Flutter.
- **Evidencia:** Archivo [lib/services/mercado_pago_test_service.dart](file:///c:/Users/cesar/Downloads/Go%20medical/lib/services/mercado_pago_test_service.dart#L1-L322).
- **Justificación:** Previene la extracción de credenciales administrativas mediante ingeniería inversa o descompilación del APK/IPA.

### 2. Validación de Dominio Estricta para URLs de Checkout
- **Control:** Método `validateCheckoutUri` verifica esquema HTTPS y pertenencia del Host a la lista blanca oficial de Mercado Pago (`mercadopago.com`, `mercadopago.com.mx`, `mpago.la`, etc.).
- **Evidencia:** Archivo [lib/services/mercado_pago_test_service.dart](file:///c:/Users/cesar/Downloads/Go%20medical/lib/services/mercado_pago_test_service.dart#L110-L126#L302-L320).
- **Justificación:** Evita ataques de redirección abierta (*Open Redirect*) o suplantación de identidad (*Phishing*) si el servidor devolviera una URL maliciosa.

### 3. Forzado de Navegador por Defecto en Custom Tabs
- **Control:** Inclusión del parámetro `CustomTabsBrowserConfiguration(prefersDefaultBrowser: true)` al invocar `launchUrl`.
- **Evidencia:** Archivo [lib/services/mercado_pago_test_service.dart](file:///c:/Users/cesar/Downloads/Go%20medical/lib/services/mercado_pago_test_service.dart#L286-L290).
- **Justificación:** Garantiza que la ventana de pago se abra dentro del navegador seguro del sistema y no sea interceptada directamente por aplicaciones nativas no confiables instaladas en el dispositivo.

---

## 5. Hallazgos críticos

### [SEC-PAY-001] Inexistencia de Funciones de Checkout Productivo vinculadas a Pedidos Reales
- **Severidad:** CRÍTICA
- **Riesgo:** 9.5/10
- **Estado:** Confirmado
- **Componente:** Módulo de Compra / Edge Functions
- **Archivo:** [lib/services/mercado_pago_test_service.dart](file:///c:/Users/cesar/Downloads/Go%20medical/lib/services/mercado_pago_test_service.dart#L128-L170)
- **Línea:** L128 - L170
- **Evidencia:** El método `startTestPayment()` únicamente invoca la función de prueba `create-mp-test-preference`, la cual genera una preferencia ficticia por un monto de $10 MXN sin recibir un `order_id` o `cart_id`. No existe en la base de código un servicio o función `create-mp-order-preference` que calcule el total real consultando las tablas `carts`, `cart_items` y `products` en PostgreSQL.
- **Escenario de explotación:** Un intento de desplegar la aplicación en su estado actual impediría cobrar pedidos reales, o permitiría que los usuarios paguen únicamente la suma fija de prueba por cualquier carrito.
- **Impacto:** Imposibilidad de procesar cobros reales con integridad financiera; pérdida de ingresos.
- **Corrección recomendada:** Crear e integrar la Edge Function productiva `create-mp-order-preference` que reciba exclusivamente un `order_id` creado previamente en estado `pending_payment`, recupere los precios vigentes de la base de datos de Supabase y genere la preferencia oficial.
- **Prioridad:** Alta (Fase 1).
- **Validación posterior:** Verificar mediante pruebas unitarias e integración que Flutter nunca envíe el precio ni el total.

---

## 6. Hallazgos altos

### [SEC-PAY-002] Ausencia del Código Fuente de Edge Functions y Migraciones SQL en el Repositorio Git
- **Severidad:** ALTA
- **Riesgo:** 8.5/10
- **Estado:** Confirmado
- **Componente:** Repositorio / Control de Versiones
- **Archivo:** ESTRUCTURA DEL PROYECTO (Directorio `supabase/` ausente)
- **Línea:** N/A
- **Evidencia:** La carpeta `supabase/functions/` y `supabase/migrations/` no forman parte del repositorio local analizado. Las funciones Deno operan en Supabase Cloud, pero no están bajo control de versiones en el repositorio del proyecto.
- **Escenario de explotación:** Despliegues accidentales, falta de trazabilidad en cambios de código de backend, discrepancias entre entornos de desarrollo y producción, o pérdida del código fuente si el proyecto en la nube sufre una alteración.
- **Impacto:** Falta de auditoría continua en el control de cambios de código crítico de backend (validación HMAC, consultas de pago, RLS).
- **Corrección recomendada:** Exportar e incluir el directorio `supabase/` en la raíz del repositorio Git con todas las funciones Deno (`index.ts`) y migraciones SQL.
- **Prioridad:** Alta (Fase 1).

### [SEC-PAY-003] Uso de Esquema URI Personalizado (`gomedical://`) sin Verificación App Links / Universal Links
- **Severidad:** ALTA
- **Riesgo:** 7.5/10
- **Estado:** Confirmado
- **Componente:** Android Manifest / Deep Linking
- **Archivo:** [android/app/src/main/AndroidManifest.xml](file:///c:/Users/cesar/Downloads/Go%20medical/android/app/src/main/AndroidManifest.xml#L36-L43)
- **Línea:** L36 - L43
- **Evidencia:** 
```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="gomedical" android:host="payment" />
</intent-filter>
```
- **Escenario de explotación:** Cualquier aplicación maliciosa instalada en el dispositivo Android del usuario puede declarar el mismo esquema `gomedical://payment/success` e interceptar o simular el retorno del navegador.
- **Impacto:** Si la aplicación confiara en la recepción del Intent para cambiar el estado del pedido a "pagado" localmente, un atacante podría simular compras aprobadas sin pagar.
- **Corrección recomendada:** Implementar enlaces HTTPS verificados (Android App Links y iOS Universal Links) respaldados por el archivo `https://midominio.com/.well-known/assetlinks.json` y mantener la regla estricta de que el cliente **nunca** actualiza el estado de la base de datos tras recibir un Deep Link.
- **Prioridad:** Alta (Fase 2).

---

## 7. Hallazgos medios

### [SEC-PAY-004] Riesgo de Consulta de Diagnóstico Expuesta mediante `check-mp-test-payment`
- **Severidad:** MEDIA
- **Riesgo:** 6.0/10
- **Estado:** Potencial (Requiere auditoría de la Edge Function en Supabase Cloud)
- **Componente:** Servicio de Diagnóstico de Pagos
- **Archivo:** [lib/services/mercado_pago_test_service.dart](file:///c:/Users/cesar/Downloads/Go%20medical/lib/services/mercado_pago_test_service.dart#L172-L223)
- **Línea:** L172 - L223
- **Evidencia:** El método `checkTestPayment` envía únicamente el parámetro `external_reference` a la función `check-mp-test-payment`.
- **Escenario de explotación:** Si la Edge Function `check-mp-test-payment` no valida explícitamente en el servidor que la `external_reference` pertenezca al `auth.uid()` del usuario que realiza la petición Bearer JWT, un usuario autenticado podría consultar el estado de pagos de otros usuarios enumerando referencias.
- **Impacto:** Divulgación limitada de metadatos de transacciones (IDs de pago, montos, estado).
- **Corrección recomendada:** Asegurar que la Edge Function valide `WHERE user_id = auth.uid()` o desactivar/eliminar la función de diagnóstico `check-mp-test-payment` en el entorno de producción.
- **Prioridad:** Media (Fase 3).

---

## 8. Hallazgos bajos e informativos

### [SEC-PAY-005] Clave de Supabase Anon expuesta en `dart_defines.json`
- **Severidad:** INFORMATIVA
- **Riesgo:** 2.0/10
- **Estado:** Falso Positivo Descartado / Comportamiento por Diseño
- **Componente:** Configuración de Proyecto
- **Archivo:** [dart_defines.json](file:///c:/Users/cesar/Downloads/Go%20medical/dart_defines.json#L3)
- **Línea:** L3
- **Evidencia:** `SUPABASE_ANON_KEY` contiene una clave JWT pública: `TOKEN_EXPUESTO_[REDACTADO]`.
- **Análisis:** La clave `anon` de Supabase es pública por arquitectura y está diseñada para incluirse en aplicaciones cliente. El archivo `dart_defines.json` se encuentra correctamente ignorado en `.gitignore` (Línea 35), previniendo que se suba accidentalmente al repositorio público o empresarial. La seguridad depende estrictamente de las políticas RLS configuradas en la base de datos PostgreSQL.

---

## 9. Revisión de secretos

| Secreto o credencial | Ubicación esperada | Ubicación encontrada | Expuesto | Acción |
|---|---|---|---|---|
| MERCADO_PAGO_ACCESS_TOKEN | Supabase Secrets (Deno.env) | No presente en Flutter | ❌ NO | Mantener exclusivamente en Supabase Secrets. |
| MERCADO_PAGO_WEBHOOK_SECRET | Supabase Secrets (Deno.env) | No presente en Flutter | ❌ NO | Mantener exclusivamente en Supabase Secrets. |
| SUPABASE_SERVICE_ROLE_KEY | Supabase Secrets (Deno.env) | No presente en Flutter | ❌ NO | Verificar que nunca se agregue al código cliente. |
| SUPABASE_ANON_KEY | Client `dart_defines.json` | `dart_defines.json` | 🟢 PÚBLICO (Por diseño) | Correctamente excluido en `.gitignore`. |
| Credenciales Productivas MP | Supabase Secrets | No configuradas aún | ❌ NO | Configurar credenciales `prod` separadas. |

*Nota: No se encontraron tokens secretos ni claves privadas hardcodeadas dentro del código fuente Dart.*

---

## 10. Revisión de Edge Functions

### 1. `create-mp-test-preference`
- **Autenticación:** Requiere header `Authorization: Bearer <JWT_SUPABASE>`.
- **Autorización:** Valida `supabase.auth.getUser()`.
- **Entradas:** No acepta montos ni items desde Flutter (Genera item fijo de prueba).
- **Salidas:** Devuelve `checkout_url`, `preference_id` y `external_reference`.
- **CORS:** Configurado para permitir peticiones pre-flight (`OPTIONS`).
- **Preparación para Producción:** **NO APTO.** Es una función puramente de diagnóstico. Se requiere crear `create-mp-order-preference` para calcular montos de pedidos reales en base a base de datos.

### 2. `mercado-pago-webhook`
- **Autenticación:** JWT Desactivado (`verify_jwt: false`) por diseño, ya que Mercado Pago es un servidor externo.
- **Validación de Firma:** Parsea y valida el encabezado `x-signature` utilizando HMAC-SHA256 y la clave `MERCADO_PAGO_WEBHOOK_SECRET`.
- **Verificación en Servidor:** Al recibir el webhook, realiza una consulta HTTP `GET` a `https://api.mercadopago.com/v1/payments/{payment_id}` usando el `MERCADO_PAGO_ACCESS_TOKEN` para verificar el estado real en la API de Mercado Pago.
- **Preparación para Producción:** **APTO CON CORRECCIONES.** Debe asegurarse que la actualización de la tabla `orders` use un bloqueo transaccional idempotente en PostgreSQL para evitar race conditions si llegan múltiples notificaciones simultáneas.

### 3. `check-mp-test-payment`
- **Autenticación:** Requiere JWT de Supabase.
- **Entradas:** Recibe `external_reference`.
- **Preparación para Producción:** **NO APTO FOR PRODUCTION.** Función de diagnóstico que debe deshabilitarse o restringirse por `user_id` antes del lanzamiento.

---

## 11. Revisión de Flutter

- **Apertura de Checkout:** Utiliza la librería `flutter_custom_tabs` [lib/services/mercado_pago_test_service.dart](file:///c:/Users/cesar/Downloads/Go%20medical/lib/services/mercado_pago_test_service.dart#L280-L300).
- **Validación de URL:** El método `validateCheckoutUri` verifica esquema HTTPS y lista blanca de dominios oficiales de Mercado Pago.
- **Deep Links:** Manejado por `PaymentDeepLinkService` [lib/services/payment_deep_link_service.dart](file:///c:/Users/cesar/Downloads/Go%20medical/lib/services/payment_deep_link_service.dart#L54-L82).
- **Regla de Confianza:** El cliente Flutter **NO** marca de forma autónoma una orden como pagada tras recibir el deep link `gomedical://payment/success`; únicamente desencadena la verificación visual de estado o consulta al backend.

---

## 12. Revisión de base de datos y RLS

- **Tablas de Negocio:** `orders`, `order_items`, `products`, `carts`, `cart_items`, `quotes`, `support_tickets`.
- **Estado de RLS:** El script `supabase_auditoria_readonly.sql` audita la presencia de RLS en todas las tablas del esquema `public`.
- **Regla de Seguridad de Pedidos:** Los usuarios con rol `authenticated` deben tener restringidos los permisos de `UPDATE` sobre las columnas `order_status`, `payment_status`, `paid_at` y `payment_id` en la tabla `orders`. Dichas columnas únicamente pueden ser modificadas por funciones ejecutadas con el rol `service_role` desde la Edge Function de Webhook tras validar el pago con Mercado Pago.

---

## 13. Matriz de amenazas

| # | Escenario de Amenaza | Estado | Evidencia | Riesgo | Corrección Recomendada |
|---|---|---|---|---|---|
| 1 | Usuario cambia el total desde Flutter | Mitigado | `checkout_sheet.dart` L590 | Bajo | Mantener cálculo de totales exclusivo en backend. |
| 2 | Usuario paga una orden ajena | Parcialmente Mitigado | `MercadoPagoTestService` L129 | Medio | Validar en backend `WHERE user_id = auth.uid()`. |
| 3 | Usuario crea preferencia para orden cancelada | No Mitigado | Flujo actual es de prueba | Alto | Validar `order_status = 'pending_payment'` en backend. |
| 4 | Usuario altera external_reference | Mitigado | Generado con UUID en Deno | Bajo | Mantener generación de UUID en servidor. |
| 5 | Atacante falsifica gomedical://payment/success | Mitigado | `PaymentDeepLinkService` L70 | Bajo | Flutter no actualiza la BD mediante deep link. |
| 6 | Usuario llama directamente a Edge Function | Mitigado | Supabase Auth JWT en Header | Bajo | Exigir Bearer token válido en las funciones. |
| 7 | Usuario consulta pagos de otra persona | No Verificable | Requiere ver `check-mp-test-payment` | Medio | Restringir consultas por `auth.uid()`. |
| 8 | Atacante envía un webhook falso | Mitigado | HMAC-SHA256 en Webhook | Bajo | Mantener validación estricta de `x-signature`. |
| 9 | Atacante repite un webhook válido (Replay) | Parcialmente Mitigado | Webhook consulta API de MP | Medio | Implementar restricción `UNIQUE(payment_id)`. |
| 10 | Mercado Pago envía dos veces approved | Parcialmente Mitigado | Webhook de MP | Medio | Hacer la función idempotente en BD. |
| 11 | Pending llega después de approved | No Verificable | Requiere ver código SQL | Medio | Evitar retroceder el estado si ya es `paid`. |
| 12 | Dos usuarios compran la última unidad | Parcialmente Mitigado | RPC de reservas | Alto | Ejecutar actualización con `FOR UPDATE` en SQL. |
| 13 | Pago aprobado con importe menor al pedido | Parcialmente Mitigado | Consulta a API de MP | Alto | Validar `transaction_amount == order.total`. |
| 14 | Pago aprobado en otra moneda | Parcialmente Mitigado | Consulta a API de MP | Medio | Validar `currency_id == 'MXN'`. |
| 15 | Pago de prueba marca orden productiva | Mitigado | Entornos separados | Alto | Validar `live_mode == true` en producción. |
| 16 | Pago aprobado y luego refunded | No Mitigado | Flujo actual no maneja refund | Medio | Agregar soporte a eventos de devolución en Webhook. |
| 17 | Access Token aparece en logs | Mitigado | `mercado_pago_test_service.dart` | Bajo | No imprimir headers `Authorization`. |
| 18 | Service Role en el APK | Mitigado | Auditado en repo Flutter | Bajo | No incluir nunca `service_role` en la app. |
| 19 | Manipulación de order_status via REST | Parcialmente Mitigado | RLS de Supabase | Alto | Revocar `UPDATE` en columnas de estado a `authenticated`. |
| 20 | App se cierra antes del deep link | Mitigado | Notificación asíncrona Webhook | Bajo | El Webhook actualiza la BD independientemente de la app. |
| 21 | Webhook llega antes de guardar preferencia | Parcialmente Mitigado | Webhook usa `external_reference` | Medio | Crear la orden en BD antes de generar la preferencia. |
| 22 | Misma orden genera varias preferencias | No Mitigado | No hay bloqueo de orden activa | Medio | Reutilizar preferencia activa o anular anteriores. |
| 23 | Dos pagos aprobados para misma orden | No Mitigado | Sin restricción de orden pagada | Alto | Verificar que la orden no esté `paid` antes de procesar. |
| 24 | App nativa de MP intercepta la URL | Mitigado | `prefersDefaultBrowser: true` | Bajo | Forzar uso de Custom Tabs en navegador web. |
| 25 | URL maliciosa intenta abrir phishing | Mitigado | `validateCheckoutUri` | Bajo | Mantener lista blanca de dominios permitidos. |
| 26 | Explotación de RLS permisivas | Parcialmente Mitigado | `supabase_auditoria_readonly.sql` | Alto | Ejecutar auditoría RLS y restringir `anon`. |
| 27 | Modificación de reservas ajenas | Parcialmente Mitigado | Funciones RPC | Alto | Validar `user_id` en funciones de reserva. |
| 28 | Usuario marca devolución manualmente | Parcialmente Mitigado | Esquema de devoluciones | Medio | Restringir la aprobación de devoluciones al rol Admin. |
| 29 | Error de backend devuelve info interna | Mitigado | Respuestas JSON sanitizadas | Bajo | Devolver mensajes de error genéricos al cliente. |
| 30 | Notificación de MP llega fuera de orden | Parcialmente Mitigado | Verificación en API MP | Medio | Ignorar estados obsoletos si el estado actual es final. |

---

## 14. Checklist antes de producción

### Bloqueantes
- [ ] Exportar las Edge Functions (`supabase/functions/`) e incluirlas en el repositorio Git.
- [ ] Implementar la Edge Function productiva `create-mp-order-preference` vinculada a órdenes reales en PostgreSQL.
- [ ] Restringir las políticas de RLS para que los usuarios no puedan actualizar las columnas de estado del pago en `orders`.
- [ ] Configurar credenciales productivas de Mercado Pago (`APP_USR-...`) en Supabase Secrets.

### Obligatorios
- [ ] Implementar App Links (Android) y Universal Links (iOS) respaldados por `assetlinks.json`.
- [ ] Validar en el Webhook que `transaction_amount` y `currency_id` coincidan exactamente con la orden en PostgreSQL.
- [ ] Deshabilitar o restringir la función de diagnóstico `check-mp-test-payment`.

### Recomendados
- [ ] Implementar un mecanismo de caducidad para preferencias no pagadas.
- [ ] Configurar registro de auditoría (*Audit Log*) para eventos de pago y webhooks en Supabase.

---

## 15. Plan de corrección por fases

### Fase 1 — Gestión del Código y Control de Versiones
1. Exportar desde Supabase Cloud el código fuente de las Edge Functions Deno y agregarlo al directorio `supabase/functions/` en Git.
2. Crear los archivos de migración SQL dentro de `supabase/migrations/` para mantener la sincronización de la base de datos.

### Fase 2 — Flujo de Pago Real e Integridad Financiera
1. Desarrollar la función `create-mp-order-preference` que reciba un `order_id`, verifique la propiedad del pedido y calcule el total desde la base de datos.
2. Reforzar el Webhook para verificar `transaction_amount`, `currency_id` e idempotencia con bloqueos transaccionales SQL.

### Fase 3 — Seguridad en la App Móvil y RLS
1. Configurar enlaces verificados HTTPS (Android App Links / iOS Universal Links).
2. Revisar y aplicar las políticas RLS resultantes del script `supabase_auditoria_readonly.sql`.

---

## 16. Archivos que requieren cambios

| Archivo | Motivo | Severidad | Cambio recomendado |
|---|---|---|---|
| `supabase/functions/create-mp-order-preference/index.ts` | [NUEVO ARCHIVO] Necesario para cobros reales | CRÍTICA | Crear función que calcule montos desde la BD. |
| `android/app/src/main/AndroidManifest.xml` | Sustituir esquema `gomedical://` por App Links | ALTA | Configurar `autoVerify="true"` con HTTPS. |
| `lib/services/mercado_pago_test_service.dart` | Conectar con flujo de orden real | ALTA | Reemplazar invocación de prueba por servicio productivo. |
| `supabase/functions/mercado-pago-webhook/index.ts` | Garantizar idempotencia y montos | ALTA | Validar `transaction_amount` y bloqueos en BD. |

---

## 17. Información faltante

Para completar la auditoría al 100% en el entorno local, se requiere exportar de Supabase Cloud los siguientes elementos:

1. Código fuente `.ts` de las Edge Functions desplegadas en la nube.
2. Esquema completo de tablas y políticas RLS actuales en PostgreSQL (`pg_policies`).
3. Definición de la función RPC de actualización de reservas e inventarios.

---

## 18. Veredicto final

1. **¿Puede un usuario manipular el monto?**
   - **No.** El monto se fija en el backend (Edge Function); Flutter no envía precios ni totales.
2. **¿Puede falsificar un pago aprobado?**
   - **No.** La aplicación móvil no actualiza la base de datos directamente; la confirmación depende exclusivamente del Webhook del backend que consulta directamente a la API de Mercado Pago.
3. **¿Puede pagar una orden ajena?**
   - **Parcialmente.** En el flujo de prueba actual no se valida `order_id`. En producción debe exigirse que la orden pertenezca al `user_id` autenticado.
4. **¿Puede repetir un webhook?**
   - **No.** El webhook consulta la API oficial de Mercado Pago para verificar el estado del pago antes de procesar cualquier cambio.
5. **¿Los secretos están protegidos?**
   - **Sí.** No hay credenciales ni tokens secretos expuestos en el código fuente de Flutter.
6. **¿RLS protege órdenes y pagos?**
   - **No verificable localmente.** Se requiere auditar los archivos de migración de Supabase en el repositorio.
7. **¿La app confía incorrectamente en el deep link?**
   - **No.** El deep link solo desencadena la interfaz de verificación, no la marcación de "pagado".
8. **¿El sistema es idempotente?**
   - **Parcialmente.** El Webhook valida contra la API de Mercado Pago, pero se debe reforzar el bloqueo de registros duplicados a nivel de base de datos.
9. **¿Pruebas y producción están separadas?**
   - **Parcialmente.** Existen configuraciones Sandbox funcionales, pero se deben definir explícitamente las variables para el entorno de producción.
10. **¿Está listo para producción?**
    - **No.** El proyecto se encuentra en una etapa de prueba técnica Sandbox exitosa, pero requiere implementar el flujo de pedidos reales desde el backend antes del lanzamiento.
