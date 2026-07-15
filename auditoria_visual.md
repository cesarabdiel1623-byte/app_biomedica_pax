# Auditoría Visual y UI/UX (Go Medical)

Esta auditoría analiza las pantallas e interfaces de **Go Medical** desde la perspectiva de un Desarrollador Frontend Senior. Se detallan problemas de responsividad, inconsistencias en el uso de temas centralizados, el uso correcto de áreas seguras (`SafeArea`) y recomendaciones para mejorar los espaciados y la armonía visual de la aplicación.

---

## 1. Falta de Responsividad (Potenciales Desbordamientos)
*Uso de dimensiones fijas (hardcoded heights/widths) en contenedores con textos o inputs, propensos a lanzar el error de "overflow" en teléfonos de pantalla pequeña o con escalado de fuente del sistema activado.*

* **Alturas de Carga y Errores Fijas (lib/screens/tickets/tickets_list_screen.dart):**
  * **Problema:** En el loader de tickets, se usa `SizedBox(height: 300, child: Center(...))`. Si bien permite el gesto de deslizar para refrescar, en pantallas pequeñas (como un iPhone SE o teléfonos compactos) este valor fijo empuja el contenido fuera de los márgenes útiles, pudiendo causar recortes visuales o desbordamientos innecesarios.
  * **Solución:** Utilizar porcentajes relativos a la pantalla mediante `MediaQuery.of(context).size.height * 0.4` en lugar de una constante fija.
* **Alturas de Chat y Listas de Mensajes (lib/screens/tickets/ticket_detail_screen.dart):**
  * **Problema:** En la pantalla de chat, se definen secciones con `SizedBox(height: 350)` y `SizedBox(height: 400)`. Si la pantalla del usuario es compacta y se despliega el teclado virtual del sistema, el espacio útil vertical se reduce críticamente. Un contenedor de altura fija causará inevitablemente el clásico warning amarillo de desbordamiento en el renderizado de Flutter.
  * **Solución:** Envolver el área del chat en un widget `Expanded` dentro de una estructura `Column` para que el tamaño se ajuste dinámicamente al espacio restante, en lugar de predefinir tamaños en píxeles físicos.

---

## 2. Gestión de Zonas Seguras (SafeArea)
*Validación del notch físico, esquinas redondeadas y barras de gestos del sistema operativo que pueden obstruir la lectura o interacción.*

* **Ausencia de SafeArea Inferior en Formularios:**
  * **Pantallas afectadas:** lib/screens/profile/edit_profile_screen.dart, lib/screens/profile/billing_screen.dart, y lib/screens/profile/maintenance_screen.dart.
  * **Problema:** Los formularios y botones de acción principal (como "Guardar Cambios" o "Guardar Datos") se renderizan al final de un `ListView`. En dispositivos modernos con navegación por gestos (sin botones físicos, como iOS o Android moderno), el botón inferior queda superpuesto o extremadamente pegado a la "píldora" o barra de gestos del sistema. Esto dificulta la pulsación del botón y luce poco profesional.
  * **Solución:** Envolver el botón o el final del `ListView` en un `SafeArea` con `top: false, left: false, right: false, bottom: true` o agregar un padding dinámico utilizando `MediaQuery.of(context).padding.bottom`.

---

## 3. Inconsistencia de Tema (Valores Hardcodeados)
*Colores y estilos de texto definidos manualmente en los widgets en lugar de ser leídos dinámicamente desde el tema global (`ThemeData`).*

* **Definición de Colores en Archivo Auxiliar (lib/screens/profile/profile_helpers.dart):**
  * **Problema:** Se exportan constantes globales de color como `kPrimary = Color(0xFF0D9488)` y `kNavy = Color(0xFF1E3A5F)`. Estas constantes se usan directamente en todas las vistas de perfil y soporte.
  * **Consecuencia:** Si la marca de la aplicación cambia a un verde más claro o se decide implementar un Modo Oscuro (Dark Mode) en el futuro, estas vistas no responderán al tema del sistema, ya que tienen los colores incrustados directamente de forma estática.
  * **Solución:** Consumir los colores desde la paleta semántica del tema del contexto actual:
    * `Theme.of(context).colorScheme.primary` en lugar de `kPrimary`.
    * `Theme.of(context).colorScheme.secondary` o `Theme.of(context).colorScheme.onSurface` en lugar de `kNavy`.
* **Múltiples Copias de Colores Primarios:**
  * En lib/screens/home/widgets/abandoned_cart_dialog.dart y lib/screens/product/quote_cart_screen.dart se definen de forma local variables duplicadas para representar los colores primarios. Esto incrementa la deuda técnica del frontend.

---

## 4. Márgenes, Espaciados y "Aire" Visual (Visual Breathing)
*Uso inconsistente de márgenes que hace que el diseño se sienta "apretado" o denso.*

* **Separación de Campos de Formulario Rígida:**
  * En los formularios de mantenimiento y facturación se observa un uso uniforme de `SizedBox(height: 12)` o `SizedBox(height: 16)`. Esto hace que los campos luzcan muy juntos entre sí. Es recomendable agrupar visualmente los inputs relacionados mediante paddings asimétricos o envolviéndolos en `Card` que tengan un fondo gris claro o blanco bien delimitado para dar mayor legibilidad.
* **Márgenes Laterales en Listas de Cards:**
  * En la lista de pedidos (lib/screens/profile/orders_screen.dart) y cotizaciones, las tarjetas tienen márgenes externos de `12` y paddings internos de `12`. En pantallas muy angostas, esto deja poco espacio para el texto de información de la cotización o folio, forzando cortes abruptos con elipsis. Se sugiere reducir el padding lateral en móviles pequeños para optimizar el área de visualización de datos.

---

## 5. Resumen de Recomendaciones de UI/UX
1. **Migración a ThemeData:** Reemplazar las importaciones de `kPrimary` y `kNavy` por el uso de `Theme.of(context)` para garantizar compatibilidad con cambios de marca y soporte de modos oscuro/claro en un solo paso.
2. **Uso de Flexible/Expanded:** Reemplazar los `SizedBox` de alturas fijas en chats por layouts fluidos (`Expanded` con `ListView` y `scrollController`) para evitar desbordamientos visuales por teclado.
3. **Paddings de Seguridad:** Asegurar que todas las pantallas con botones flotantes o listas largas apliquen un `SafeArea(bottom: true)` para evitar solapamientos con la barra de navegación del sistema operativo móvil.
