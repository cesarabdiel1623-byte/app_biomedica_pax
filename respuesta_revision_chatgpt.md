# Respuesta a Revision Externa

Fecha: 2026-07-15

Este documento resume los hallazgos compartidos, explica cada punto en lenguaje
claro y distingue entre:

- lo que podemos corregir desde la app Flutter
- lo que depende de backend / Supabase / despliegue

## Resumen ejecutivo

La revision recibida es mayormente valida y esta bien enfocada.

Hay tres grupos de temas:

1. Configuracion y empaquetado del proyecto
2. Seguridad y arquitectura compartida con Supabase
3. Madurez de producto y calidad de pruebas

No todos los puntos tienen la misma gravedad:

- Hay puntos reales y corregibles desde la app
- Hay puntos reales pero que dependen del equipo de base de datos
- Hay puntos que no son una vulnerabilidad critica por si mismos, pero si una
  mala practica o señal de proyecto en desarrollo

## Matriz rapida

| Punto | Es correcto | Lo resolvemos desde Flutter | Depende de backend |
| --- | --- | --- | --- |
| Repositorio limpio no compila | Si | Corregido | No |
| Archivo example con valores reales | Si | Corregido | No |
| No hay SQL ni migraciones versionadas | Si | Parcial | Si |
| Riesgos ya detectados siguen pendientes | Si | Parcial | Si |
| Nombres de prueba `app_prueba` | Si | Corregido | No |
| Integracion superficial | Si | Corregido como smoke test | No |

## 1. El repositorio limpio no puede compilar directamente

### Explicacion

En [pubspec.yaml](<C:\Users\cesar\Downloads\Go medical\pubspec.yaml:1>) esta
declarado `dart_defines.json` como asset.

Eso significa que una clonacion limpia o un ZIP sin ese archivo puede fallar al
compilar, porque Flutter intentara empaquetar un asset que no existe.

### Estado

Este punto era correcto y ya se corrigio del lado movil.

`dart_defines.json` ya no esta declarado como asset obligatorio en
[pubspec.yaml](<C:\Users\cesar\Downloads\Go medical\pubspec.yaml:1>).

### Impacto

- rompe builds limpias
- complica CI/CD
- complica compartir el proyecto con otro desarrollador

### Lo podemos resolver nosotros

Si.

### Recomendacion

La opcion aplicada es la mas limpia para produccion:

- usar solo `--dart-define` o `--dart-define-from-file`
- no declarar `dart_defines.json` como asset

### Prioridad

Cerrado del lado Flutter.

## 2. El archivo de ejemplo contiene valores reales

### Explicacion

En [dart_defines.example.json](<C:\Users\cesar\Downloads\Go medical\dart_defines.example.json:1>)
aparecen:

- URL real de Supabase
- anon key real
- Google client IDs reales

Aunque eso no equivale a una `service_role`, un archivo `example` no deberia
traer valores reales del proyecto.

### Estado

Este punto era correcto y ya se corrigio.

El archivo [dart_defines.example.json](<C:\Users\cesar\Downloads\Go medical\dart_defines.example.json:1>)
ahora contiene placeholders, no valores reales.

### Impacto

- facilita que terceros apunten directamente al proyecto real
- normaliza mala practica de configuracion
- confunde sobre que es plantilla y que es entorno real

### Lo podemos resolver nosotros

Si.

### Recomendacion

Cambiarlo por placeholders:

```json
{
  "SUPABASE_URL": "https://TU-PROYECTO.supabase.co",
  "SUPABASE_ANON_KEY": "TU_ANON_KEY",
  "GOOGLE_ANDROID_CLIENT_ID": "TU_ANDROID_CLIENT_ID",
  "GOOGLE_WEB_CLIENT_ID": "TU_WEB_CLIENT_ID"
}
```

### Prioridad

Cerrado del lado Flutter.

## 3. Retiraron todos los SQL

### Explicacion

Hoy el repositorio ya no contiene migraciones SQL ni definicion local del
backend.

Eso evita mezclar SQL viejo con la app, pero tambien deja al repo sin una fuente
de verdad sobre:

- tablas
- vistas
- funciones RPC
- ENUMs
- triggers
- politicas RLS

### Estado

Este punto es correcto.

De hecho, al revisar el proyecto actual no aparecen archivos `.sql`.
Este punto queda documentado para backend en
[pendientes_backend_supabase.md](<C:\Users\cesar\Downloads\Go medical\pendientes_backend_supabase.md:1>).

### Impacto

- dificulta auditoria y mantenimiento
- impide reconstruir backend desde el repo
- vuelve a Supabase Productivo la unica fuente de verdad

### Lo podemos resolver nosotros

Parcialmente.

Desde la app no podemos regenerar la historia real de la base. Pero si podemos:

- documentar dependencias backend criticas
- pedir export oficial de schema/migrations
- evitar que la app asuma logica que no esta versionada

### Recomendacion

Si el proyecto va a seguir creciendo, conviene que el equipo backend exporte:

- schema SQL
- migrations
- funciones RPC
- policies RLS

### Prioridad

Media-Alta.

## 4. La auditoria reconoce problemas que siguen pendientes

### Explicacion

Este punto dice, en esencia, que ya se detectaron riesgos pero varios siguen
dependiendo del backend.

Es verdad.

En [auditoria_seguridad_supabase.md](<C:\Users\cesar\Downloads\Go medical\auditoria_seguridad_supabase.md:1>)
quedo documentado que persisten riesgos en:

- politicas RLS
- columnas internas expuestas
- adjuntos publicos
- operaciones sensibles directas

### Estado

Correcto.

### Impacto

La app movil ya esta mas segura que antes, pero la seguridad fuerte sigue
dependiendo del backend.

### Lo podemos resolver nosotros

Parcialmente.

Ya resolvimos del lado Flutter:

- sacar credenciales de `lib/`
- dejar de pedir `products(*)` en rutas publicas
- quitar la conversion de cotizacion a pedido desde cliente
- validar URLs remotas de tickets y notificaciones
- usar `client_id` efectivo en direcciones y mantenimiento

Lo pendiente fuerte sigue en Supabase y quedo separado en
[pendientes_backend_supabase.md](<C:\Users\cesar\Downloads\Go medical\pendientes_backend_supabase.md:1>).

### Recomendacion

Presentarlo como deuda compartida:

- movil: bastante endurecido
- backend: requiere cierre de policies y buckets

### Prioridad

Alta.

## 5. El proyecto aun conserva nombres de prueba

### Explicacion

Antes de la correccion, en [pubspec.yaml](<C:\Users\cesar\Downloads\Go medical\pubspec.yaml:1>)
el nombre seguia como `app_prueba`, y en Android el package seguia como
`com.example.app_prueba`.

Ahora quedo actualizado en:

- [android/app/build.gradle.kts](<C:\Users\cesar\Downloads\Go medical\android\app\build.gradle.kts:1>)
- [MainActivity.kt](<C:\Users\cesar\Downloads\Go medical\android\app\src\main\kotlin\com\gomedical\marketplace\MainActivity.kt:1>)

### Estado

Este punto era correcto y ya se corrigio del lado movil.

El proyecto ahora usa:

- `gomedical_app` como nombre Dart
- `com.gomedical.marketplace` como identificador Android

### Impacto

- señal clara de proyecto no finalizado
- afecta branding, despliegue y publicacion
- puede complicar migraciones futuras del package name

### Lo podemos resolver nosotros

Si.

### Recomendacion

Renombrar:

- `name` del proyecto
- `applicationId` de Android
- package Kotlin
- equivalentes de iOS si aplica

Para algo como:

- `gomedical_app`
- `com.gomedical.marketplace`

### Prioridad

Cerrado del lado Flutter para Android y referencias principales del proyecto.

## 6. Las pruebas de integracion son superficiales

### Explicacion

La observacion es correcta al revisar
[integration_test/app_integration_test.dart](<C:\Users\cesar\Downloads\Go medical\integration_test\app_integration_test.dart:1>).

La prueba actual:

- puede saltarse login
- navega por UI de forma oportunista
- presiona botones si existen
- no valida efectos reales en backend o pagos

No prueba:

- creacion real de pedido o pago
- integridad de inventario
- webhooks
- consistencia de totales
- rechazos de pago

### Estado

Este punto era correcto y ya se corrigio en alcance inicial.

La prueba de integracion se reclasifico como smoke test de navegacion, sin
presionar acciones sensibles como confirmar compra o enviar mensajes.

### Impacto

- da confianza limitada
- sirve mas como smoke test UI que como prueba de negocio
- no alcanza para certificar compra real

### Lo podemos resolver nosotros

Si, pero requiere definir alcance.

### Recomendacion

Separar pruebas en 3 niveles:

1. Smoke UI
2. Integracion controlada con backend de staging
3. Flujos criticos end-to-end reales o simulados con contratos bien definidos

### Prioridad

Cerrado como smoke test. Las pruebas E2E reales de pago/inventario quedan como
siguiente etapa.

## Que ya mejoramos nosotros en la app

Estos puntos ya se trabajaron del lado Flutter:

- credenciales fuera de `lib/`
- soporte de `flutter run` para desarrollo local
- exclusión de columnas internas en consultas publicas de productos
- eliminación de conversion directa de cotizacion a pedido desde cliente
- validación de URLs remotas para tickets y notificaciones
- uso consistente de `client_id` efectivo en direcciones y mantenimiento

## Que todavia podemos corregir desde la app

- seguir endureciendo pantallas con escrituras directas a Supabase
- crear pruebas E2E reales contra staging para pago, webhooks e inventario

## Que depende del backend / Supabase

- RLS real
- buckets publicos
- columnas sensibles expuestas por SELECT
- RPCs y funciones transaccionales
- schema y migrations versionadas

## Conclusión

La revision recibida es util y, en terminos generales, acertada.

No significa que la app sea inutilizable, pero si confirma que:

- el proyecto sigue en estado de desarrollo
- hay deuda tecnica real
- parte ya la estamos corrigiendo en Flutter
- otra parte requiere trabajo del equipo que controla Supabase

## Mensaje corto para reenviar

Se revisaron los 6 puntos observados y, en general, la evaluacion es correcta.
De esos 6 puntos, 4 se pueden corregir directamente desde la app Flutter
configuracion, archivo example, nombres finales del proyecto y calidad de
pruebas. Los otros 2 dependen parcial o principalmente del backend de Supabase:
versionado de schema/migraciones y cierre real de RLS, buckets y funciones
sensibles.

En resumen: la app ya mejoro en varias medidas de seguridad del cliente, pero
todavia hay trabajo pendiente tanto de hardening movil como de backend.

## Estado despues de las correcciones

Del lado movil ya quedaron corregidos estos puntos:

1. quitar `dart_defines.json` como asset obligatorio
2. reemplazar valores reales en `dart_defines.example.json`
3. renombrar `app_prueba` a identificadores finales
4. convertir la prueba de integracion en smoke test honesto

Lo pendiente de backend quedo separado en
[pendientes_backend_supabase.md](<C:\Users\cesar\Downloads\Go medical\pendientes_backend_supabase.md:1>).
