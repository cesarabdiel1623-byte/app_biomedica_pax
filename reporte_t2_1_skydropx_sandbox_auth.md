# Reporte T2.1 — Prueba de Autenticación SkyDropX Sandbox

## A. Archivos Revisados
- `supabase/functions/verify-mp-order-payment/index.ts`: Revisado para seguir las convenciones nativas del proyecto en Supabase Edge Functions (CORS headers, manejo de respuestas JSON `jsonResponse`, patrón `Deno.serve`, etc.).
- `supabase/functions/mercado-pago-webhook/index.ts`: Inspeccionado para asegurar que ninguna Edge Function existente ni de Mercado Pago sea alterada.

## B. Archivo Creado
- `supabase/functions/skydropx-sandbox-auth-test/index.ts`: Nueva Edge Function minimalista aislada, diseñada exclusivamente para validar las credenciales OAuth en Sandbox de SkyDropX sin afectar producción ni la base de datos.

## C. Endpoint Utilizado
- `${SKYDROPX_SANDBOX_BASE_URL}/api/v1/oauth/token`
  - URL Base por defecto: `https://sb-pro.skydropx.com`
  - URL Completa: `https://sb-pro.skydropx.com/api/v1/oauth/token`

## D. Mecanismo OAuth
- **Método HTTP**: `POST`
- **Header**: `Content-Type: application/x-www-form-urlencoded`
- **Cuerpo (Form URL Encoded)**:
  - `grant_type`: `client_credentials`
  - `client_id`: Obtenido directamente de `Deno.env.get('SKYDROPX_SANDBOX_CLIENT_ID')`
  - `client_secret`: Obtenido directamente de `Deno.env.get('SKYDROPX_SANDBOX_CLIENT_SECRET')`

## E. Variables de Entorno Utilizadas
- `SKYDROPX_SANDBOX_CLIENT_ID`
- `SKYDROPX_SANDBOX_CLIENT_SECRET`
- `SKYDROPX_SANDBOX_BASE_URL` (Valor: `https://sb-pro.skydropx.com`)

## F. Manejo Seguro de Secretos
- **Lectura**: Exclusivamente mediante `Deno.env.get(...)` en tiempo de ejecución en el entorno serverless de Supabase Edge Functions.
- **Protección de fuga**:
  - Ningún secreto ni credencial literal está hardcodeado en la función.
  - No hay sentencias `console.log` ni impresiones a bitácoras de logs que incluyan `client_id` o `client_secret`.
  - En caso de error (400, 401, timeout o error de red), los mensajes de retorno están sanitizados y NUNCA retornan ni transmiten las credenciales.

## G. Estructura de Respuesta Segura
La Edge Function evalúa si SkyDropX responde un `access_token` válido pero **NUNCA expone el token real al cliente ni en logs**.

### Respuesta de Éxito (HTTP 200):
```json
{
  "ok": true,
  "environment": "sandbox",
  "token_received": true,
  "token_type": "Bearer",
  "expires_in": 7200,
  "scope": null
}
```

### Respuesta de Error Sanitizado (HTTP 4xx / 5xx / Timeout):
```json
{
  "ok": false,
  "environment": "sandbox",
  "token_received": false,
  "status_code": 401,
  "error": "skydropx_auth_error",
  "message": "Mensaje de error seguro provisto por la API sin incluir secretos"
}
```

## H. Validaciones Ejecutadas
1. **Inspección Estática de Seguridad**:
   - Confirmado 0 apariciones de `console.log`.
   - Confirmado 0 credenciales hardcodeadas (Keys, Secrets, Tokens).
2. **Métodos HTTP**:
   - `OPTIONS`: Manejo de Preflight CORS (200 OK).
   - `POST`: Procesamiento de autenticación.
   - Cualquier otro método (`GET`, `PUT`, `DELETE`): Retorna `405 Method Not Allowed`.
3. **Resiliencia & Timeout**:
   - Incorporación de `AbortController` con un timeout máximo de 10,000 ms (10s) para evitar bloqueos por llamadas pendientes.
4. **Verificación de Deno en Entorno Local**:
   - Se intentó ejecutar `deno check supabase/functions/skydropx-sandbox-auth-test/index.ts`.
   - **Resultado**: `deno` no está instalado localmente en el PATH del sistema operativo Windows del usuario.

## I. Información No Verificada (Pendiente de Ejecución Remota)
- **Ejecución HTTP real a SkyDropX Sandbox**: No se ha realizado ninguna petición en vivo contra `https://sb-pro.skydropx.com` debido a que la función Edge NO ha sido desplegada todavía (`NO DESPLIEGUES LA FUNCIÓN TODAVÍA. NO LLAMES A SKYDROPX TODAVÍA. Detente para revisión.`).
- **Validez de las credenciales remotas**: La comprobación final de si las credenciales en Supabase Secrets son 100% funcionales ocurrirá una vez aprobada y desplegada la Edge Function.
