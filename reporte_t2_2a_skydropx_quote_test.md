# T2.2A - SkyDropX Sandbox quotation smoke test

## Alcance

Se creo una Edge Function independiente para probar `POST /api/v1/quotations` contra SkyDropX Sandbox:

- `supabase/functions/skydropx-sandbox-quote-test/index.ts`

No se modifico la funcion T2.1 `skydropx-sandbox-auth-test`, no se modifico Flutter, Mercado Pago, S1, tablas, migraciones ni Supabase Cloud. No se desplego la funcion y no se llamo SkyDropX.

## Funcion creada

La funcion acepta solo `POST` y `OPTIONS` para CORS.

El body esperado es explicito y no esta hardcodeado:

```json
{
  "address_from": {
    "country_code": "MX",
    "postal_code": "...",
    "area_level1": "...",
    "area_level2": "...",
    "area_level3": "..."
  },
  "address_to": {
    "country_code": "MX",
    "postal_code": "...",
    "area_level1": "...",
    "area_level2": "...",
    "area_level3": "..."
  },
  "parcels": [
    {
      "length": 10,
      "width": 10,
      "height": 10,
      "weight": 2
    }
  ]
}
```

## Validaciones

- `address_from` y `address_to` deben ser objetos.
- `country_code`, `postal_code`, `area_level1`, `area_level2`, `area_level3` son obligatorios y no vacios.
- `country_code` se normaliza a mayusculas.
- Solo se acepta `MX`.
- `parcels` debe ser un arreglo no vacio.
- Cada paquete exige `length`, `width`, `height`, `weight` como numeros positivos finitos.
- Se rechazan cero, negativos, strings, `NaN`, objetos invalidos y arreglos vacios.

## Seguridad

La funcion obtiene internamente:

- `SKYDROPX_SANDBOX_CLIENT_ID`
- `SKYDROPX_SANDBOX_CLIENT_SECRET`
- `SKYDROPX_SANDBOX_BASE_URL`

Nunca devuelve ni imprime:

- `access_token`
- `client_id`
- `client_secret`

No hay logs. Los errores estan sanitizados y no incluyen payloads completos de SkyDropX.

## Llamadas preparadas

OAuth:

- `POST {BASE_URL}/api/v1/oauth/token`
- `Content-Type: application/x-www-form-urlencoded`
- `grant_type=client_credentials`

Cotizacion:

- `POST {BASE_URL}/api/v1/quotations`
- `Authorization: Bearer <token>`
- `Content-Type: application/json`
- body:

```json
{
  "quotation": {
    "address_from": {},
    "address_to": {},
    "parcels": []
  }
}
```

## Respuesta sanitizada

La funcion devuelve solo:

- `ok`
- `environment`
- `quotation_created`
- `quotation_id`
- `is_completed`
- `rates` sanitizados

Si `is_completed=false`, conserva `quotation_id` y devuelve `rates: []`.

## Errores manejados

- body JSON invalido
- error de validacion
- configuracion OAuth faltante
- error OAuth
- 400, 401, 403, 422, 429
- 5xx
- timeout
- network error
- respuesta JSON invalida
- error interno

## Validacion local

Comando solicitado:

```powershell
deno check .\supabase\functions\skydropx-sandbox-quote-test\index.ts
```

Resultado: no se pudo ejecutar porque `deno` no esta instalado o no esta en `PATH` en este entorno:

```text
deno : El termino 'deno' no se reconoce como nombre de un cmdlet, funcion, archivo de script o programa ejecutable.
```

Busqueda de credenciales hardcodeadas:

```powershell
rg -n "access_token|client_secret|client_id|APP_USR|TEST-|Bearer [A-Za-z0-9._-]+|SKYDROPX_SANDBOX_CLIENT_SECRET|SKYDROPX_SANDBOX_CLIENT_ID" .\supabase\functions\skydropx-sandbox-quote-test\index.ts
```

Resultado: solo aparecen nombres de variables, parametros OAuth y nombres de env vars esperados. No se encontro ningun valor de credencial ni token hardcodeado.
