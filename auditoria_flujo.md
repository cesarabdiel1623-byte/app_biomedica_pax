# Auditoría de Flujo, Manejo de Estado y Errores (Go Medical)

Esta auditoría analiza los flujos de navegación, el control de estados asíncronos y el manejo de excepciones en la aplicación **Go Medical** para identificar áreas propensas a congelamientos visuales, pantallas rojas (crashes) y trampas de navegación.

---

## 1. Estados de Carga Perdidos (Missing Loading States)
*Asíncronía donde la interfaz no muestra un indicador de carga claro (`CircularProgressIndicator`), bloquea la interacción, o desactiva botones durante peticiones.*

* **Carga de Datos Fiscales (lib/screens/profile/billing_screen.dart):**
  * **Problema:** En `_loadBillingData()`, si la consulta a Supabase tarda mucho debido a una mala conexión, la pantalla se queda mostrando el spinner general de `_loading`. Sin embargo, en el bloque `catch`, solo cambia `_loading = false` y los campos del formulario se muestran completamente vacíos sin indicar al usuario que la carga de sus datos anteriores falló. El usuario podría sobreescribir sus datos pensando que es la primera vez que ingresa.
* **Carga de Equipos para Reportes (lib/screens/profile/maintenance_screen.dart):**
  * **Problema:** En `_loadEquipments()`, si la red falla, el bloque `catch` establece silenciosamente `_loading = false` sin indicación alguna. El dropdown de equipos mostrará únicamente la opción "Otro" y los campos de marca/modelo permanecerán ocultos o vacíos, confundiendo al usuario respecto a por qué no aparecen sus equipos registrados.
* **Carga Inicial del Perfil en Edición (lib/screens/profile/edit_profile_screen.dart):**
  * **Problema:** Al igual que los anteriores, en `_loadProfile()`, si la petición falla en el `catch (_)`, se apaga el loader sin alertar al usuario. Los campos de Nombre y Teléfono aparecerán vacíos.

---

## 2. Manejo de Errores Ausente o Insuficiente (Unsafe Error Catching)
*Bloques `try-catch` ausentes o vacíos, impresiones a consola silenciosas (`print`), y potenciales puntos de "pantalla de error roja" por variables nulas.*

* **Búsqueda Silenciosa en el Buscador (lib/screens/product/search_screen.dart):**
  * **Problema:** En `_executeSearch()`, si la petición a `ProductService.searchProducts` lanza una excepción (por ejemplo, timeout de base de datos), el catch hace un `print` a consola y establece `_isLoading = false`. Para el usuario final, la pantalla simplemente deja de cargar y muestra "0 resultados", simulando que el equipo médico no existe cuando en realidad fue un error de red o de API.
* **Excepciones Silenciosas en Sugerencias de Búsqueda (lib/screens/product/search_screen.dart):**
  * **Problema:** En `_onQueryChanged()`, el bloque `catch (e)` únicamente imprime el error en consola (`print('Error loading search suggestions: $e')`). Si hay intermitencia de red, el autocompletado fallará de manera silenciosa sin permitir reintentar ni informar.
* **Potencial Crash de Nulos en Detalle de Equipos (lib/screens/profile/equipment_screen.dart):**
  * **Problema:** En `EquipmentDetailScreen`, las variables locales del producto se recuperan haciendo cast directo a `Map?` (`final product = equipment['products'] as Map?`). Si la base de datos de Supabase devuelve un nulo o un formato inesperado para `products` (por ejemplo, debido a una desvinculación o purga de catálogo), los accesos a `product?['name']` no fallarán, pero llamadas subsiguientes podrían crashear la pantalla si se asume que ciertos campos relacionales obligatorios existen sin un valor por defecto robusto.

---

## 3. Callejones Sin Salida (Navigation & UI Traps)
*Flujos de navegación de los cuales el usuario no puede regresar o cancelar de forma intuitiva.*

* **Pantalla de Lista de Registro Pendiente (lib/main.dart):**
  * **Problema:** Si el usuario es redirigido a `RegistrationChecklistScreen` porque su registro de perfil está incompleto (falta teléfono o términos aceptados), esta pantalla actúa como un guardián rígido. Si el usuario desea cerrar sesión para entrar con otra cuenta, o volver temporalmente al login, no cuenta con un botón de "Cerrar Sesión" o "Regresar" en la UI. Está atrapado en esa vista hasta que complete obligatoriamente el formulario o reinstale la app.
* **Falta de Acción de Reintento (Retry) en Errores de Pantalla Completa:**
  * **Soporte / Tickets:** En las pantallas de listas que cargan datos al iniciar (como `QuotesScreen`, `OrdersScreen`), si se atrapa un error inicial, la UI muestra un texto simple de `'Error: $e'`. Aunque se cuenta con `RefreshIndicator`, no hay un botón explícito de "Reintentar" grande y accesible que guíe al usuario a refrescar la pantalla de forma intuitiva si el primer intento falló por problemas de cobertura móvil.

---

## 4. Recomendaciones Arquitectónicas

1. **Manejo de Errores Unificado (SnackBar/State Alert):** Nunca dejar bloques `catch` vacíos o limitados a `print()`. Siempre mostrar un `SnackBar` informativo o actualizar un estado de error (`_error`) que pinte un botón de reintento en pantalla.
2. **Bypass Temporal e Interrupción de Guardián:** Añadir la opción de "Cerrar sesión" en la pantalla de checklist de registro (`RegistrationChecklistScreen`) para evitar atascos permanentes.
3. **Carga en Botones de Envío:** Asegurar que todos los botones que realizan peticiones de escritura a la base de datos (como el botón de "Confirmar compra" o "Solicitar Cotización") se deshabiliten (`onPressed: null`) mientras `_loading` sea `true` para evitar clics dobles y duplicación de transacciones en base de datos.
