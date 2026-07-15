# Pendientes para Backend / Supabase

Fecha: 2026-07-15

Este archivo resume los puntos que no se pueden cerrar completamente desde la
app movil. Del lado Flutter ya se hicieron mejoras de configuracion, consultas
publicas y validacion de URLs, pero la seguridad final depende de como este
configurado Supabase.

## 1. Versionar schema, migrations y SQL

Hoy el repositorio movil no contiene una fuente verificable del backend:

- tablas
- vistas
- funciones RPC
- triggers
- ENUMs
- politicas RLS
- logica de inventario y checkout

Esto no rompe la app por si solo, pero impide auditar o reconstruir el backend
desde el repositorio.

### Recomendacion

El equipo que administra Supabase deberia exportar y versionar:

- schema SQL actual
- migrations oficiales
- funciones RPC criticas, especialmente checkout e inventario
- triggers de perfiles, pedidos y pagos
- policies RLS vigentes

## 2. Revisar y cerrar RLS real

La app movil no puede garantizar por si sola que una tabla este protegida. Si
una policy permite leer o escribir datos sensibles, cualquier cliente con la
anon key podria intentar usar esa superficie.

Puntos que backend debe validar:

- que `products` no exponga columnas internas como costos
- que cotizaciones, pedidos y pagos no se aprueben desde el cliente
- que tickets y mensajes solo sean visibles para su dueno o staff autorizado
- que los buckets de adjuntos no sean publicos si contienen informacion privada
- que `auth.uid()` y `profiles.client_id` tengan una relacion consistente
- que funciones sensibles se ejecuten con validaciones transaccionales

### Recomendacion

Revisar las policies desplegadas directamente en Supabase y probarlas con:

- usuario anonimo
- usuario cliente
- usuario staff
- usuario ajeno al registro

## Mensaje para enviar al equipo backend

Del lado movil ya se avanzaron correcciones de seguridad, pero estos puntos
requieren validacion desde Supabase. Necesitamos que revisen el schema real,
las migrations, las funciones RPC, los buckets y las policies RLS desplegadas.
La app puede limitar lo que consulta o muestra, pero no puede reemplazar las
restricciones del backend.
