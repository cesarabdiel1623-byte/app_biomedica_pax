# T2.2B - SkyDropX Sandbox quotation status smoke test

## Alcance

Se creo una Edge Function independiente para consultar el estado de una cotizacion SkyDropX Sandbox existente:

- `supabase/functions/skydropx-sandbox-quote-status-test/index.ts`

No se modifico `skydropx-sandbox-quote-test`, T2.1, Flutter, Mercado Pago, S1, BD, migraciones ni Supabase Cloud. No se desplego la funcion y no se llamo SkyDropX.

## Entrada

La funcion acepta solo `POST` y espera:

```json
{
  "quotation_id": "UUID"
}
```

Validaciones:

- `quotation_id` obligatorio
- debe ser string no vacio
- debe cumplir formato UUID razonable

## OAuth interno

La funcion obtiene internamente un token OAuth con:

- `SKYDROPX_SANDBOX_CLIENT_ID`
- `SKYDROPX_SANDBOX_CLIENT_SECRET`
- `SKYDROPX_SANDBOX_BASE_URL`

Nunca devuelve ni registra:

- `access_token`
- `client_id`
- `client_secret`

## Consulta SkyDropX preparada

Endpoint:

```text
GET {BASE_URL}/api/v1/quotations/{quotation_id}
```

Headers:

```text
Authorization: Bearer <token>
Accept: application/json
```

## Respuesta sanitizada

La funcion devuelve solo:

- `ok`
- `environment`
- `quotation_id`
- `is_completed`
- `rates`

Cada rate se limita a:

- `id`
- `provider_name`
- `provider_display_name`
- `provider_service_name`
- `status`
- `currency_code`
- `amount`
- `total`
- `days`
- `shipment_creation_type`

Si `is_completed = false`, devuelve `rates: []` sin inventar tarifas.

## Errores manejados

- JSON de entrada invalido
- validacion de `quotation_id`
- configuracion OAuth faltante
- error OAuth
- 400
- 401
- 403
- 404
- 422
- 429
- 5xx
- timeout
- network error
- JSON invalido en respuesta
- error interno

Los errores estan sanitizados y no incluyen credenciales, token ni respuesta completa de SkyDropX.

## Validacion local

Comando solicitado:

```powershell
deno check .\supabase\functions\skydropx-sandbox-quote-status-test\index.ts
```

Resultado: no se pudo ejecutar porque `deno` no esta instalado o no esta en `PATH` en este entorno.

Busqueda de credenciales hardcodeadas:

```powershell
rg -n "access_token|client_secret|client_id|APP_USR|TEST-|Bearer [A-Za-z0-9._-]+|SKYDROPX_SANDBOX_CLIENT_SECRET|SKYDROPX_SANDBOX_CLIENT_ID" .\supabase\functions\skydropx-sandbox-quote-status-test\index.ts
```

Resultado: solo aparecen nombres de variables, parametros OAuth y nombres de env vars esperados. No se encontro ningun valor de credencial ni token hardcodeado.
