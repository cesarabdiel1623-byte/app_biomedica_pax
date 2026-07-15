# Plan de Rediseño de UI/UX e Interfaz Premium (Go Medical)

Este plan de rediseño detalla la estrategia visual y de interacción para llevar la interfaz de **Go Medical** al siguiente nivel. El objetivo principal es renovar la estética con un diseño contemporáneo, limpio y profesional, y añadir animaciones fluidas (micro-interacciones, transiciones de página, esqueletos de carga) para lograr una experiencia de usuario (UX) premium.

---

## 1. Estrategia de Estilo y Tema General (Design Tokens)

* **Paleta de Colores Moderna (Alineada con HSL):**
  * **Primario:** Teal profundo (`#0D9488` o `0xFF0D9488`).
  * **Secundario (Navy):** `#0F172A` (Slate/Navy muy moderno para textos y encabezados en lugar del navy plano).
  * **Acentos:** Esmeralda suave (`#10B981`) para éxitos y Coral cálido (`#F43F5E`) para alertas o descuentos.
  * **Fondo de App:** Blanco puro o Slate ultra-claro (`#F8FAFC`).
* **Bordes y Sombras (Elevaciones):**
  * Unificación de esquinas con `BorderRadius.circular(16)` para tarjetas estándar y `24` para hojas modales inferiores (bottom sheets).
  * Reemplazo de sombras duras por sombras difuminadas: `BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: Offset(0, 4))`.
* **Tipografía:** Usar pesos contrastantes de fuentes del sistema (o Inter si es posible) con espaciados de letras (`letterSpacing`) ligeramente abiertos para mayúsculas y compactos para títulos grandes.

---

## 2. Plan por Pantallas Principales

### A. Pantalla de Inicio / Marketplace (`marketplace_tab.dart`)
* **Mejoras Visuales:**
  * **Buscador Superior:** Convertirlo en una barra flotante estilizada con una sombra muy sutil, en lugar de un cuadro plano.
  * **Carrusel de Banners:** Bordes redondeados de 16px con un indicador de páginas tipo píldora interactiva.
  * **Tarjetas de Producto:** Tarjetas de diseño vertical con bordes limpios sin elevación tradicional, usando bordes grises de 1px muy tenues (`Colors.grey.shade100`) y fondo blanco puro.
* **Animaciones Premium:**
  * **Shimmer Loader (Esqueleto):** Sustituir el spinner giratorio por bloques con un gradiente animado en gris claro que simule la forma de la tarjeta mientras cargan los productos.
  * **Desplazamiento Horizontal Suave:** Animación de rebote elástica al final del scroll horizontal en las secciones de ofertas del día.
  * **Efecto Hover/Tap:** La tarjeta del producto se escala ligeramente hacia arriba (1.02x) y la sombra aumenta de densidad en respuesta al toque.

### B. Detalle de Producto (`product_detail_screen.dart`)
* **Mejoras Visuales:**
  * **Galería de Imágenes:** Transición integrada con gestos de zoom sobre el producto.
  * **Ficha Técnica y Acordeones:** Sección expandible rediseñada con divisores limpios y cabeceras gruesas.
  * **Sticky Bottom Bar:** El botón de agregar al carrito flotará en una barra inferior fija con fondo difuminado (Glassmorphism / BackdropFilter).
* **Animaciones Premium:**
  * **Hero Transition:** El widget de la foto del producto en el Marketplace crecerá de forma continua y fluida hacia la cabecera de la pantalla de detalle al hacer clic.
  * **Slide in Panels:** Al abrir la pestaña de "Comentarios" o "Preguntas", el contenido aparecerá con un deslizamiento vertical y desvanecimiento progresivo (Fade & Slide).

### C. Carrito de Compras (`cart_tab.dart`)
* **Mejoras Visuales:**
  * **Tarjetas de Artículos:** Diseño compacto de lista con botón deslizante lateral (dismissible) para remover elementos del carrito.
  * **Resumen de Pago:** Diseño de tarjeta tipo factura con tipografía de anchos variables (semibold para totales).
* **Animaciones Premium:**
  * **Animated List Insertion/Removal:** Animación de colapso y desvanecimiento al eliminar un artículo de la lista en lugar de que desaparezca instantáneamente.
  * **Efecto Confeti / Success Check:** Animación festiva o un checklist animado en 2D al confirmar una compra con éxito.

### D. Soporte y Tickets (`tickets_list_screen.dart` y `ticket_detail_screen.dart`)
* **Mejoras Visuales:**
  * **Tickets Cards:** Tarjetas con badges de estado circulares de color translúcido según prioridad.
  * **Chat de Soporte:** Burbujas de mensajes asimétricas redondeadas con micro-sombras e indicación clara de remitente.
* **Animaciones Premium:**
  * **Transition Tabs:** El deslizamiento horizontal entre las pestañas ("Abiertos", "En Progreso", "Cerrados") se animará con transiciones suaves.
  * **Message Float In:** Cada mensaje nuevo aparecerá flotando de abajo hacia arriba de manera amortiguada (Spring Animation).

### E. Sección del Perfil y Menús (`profile_tab.dart` y sub-pantallas)
* **Mejoras Visuales:**
  * **Header del Perfil:** Fondo Teal sólido que se difumina hacia abajo, con foto de perfil circular que sobresale ligeramente.
  * **Opciones del Menú:** Iconos modernos estilo outline con fondos de color de acento tenue.
* **Animaciones Premium:**
  * **Staggered Slide-In:** Al abrir la pantalla de perfil, las opciones de menú ("Mis Pedidos", "Mis Cotizaciones", "Datos Fiscales") se deslizarán de derecha a izquierda una tras otra en cascada (0.05 segundos de retraso por fila).

### F. Pantalla de Autenticación (`login_screen.dart`)
* **Mejoras Visuales:**
  * **Background:** Incorporación de curvas suaves o ilustración corporativa minimalista.
  * **Formularios:** Focus borders más gruesos y animados en color Teal.
* **Animaciones Premium:**
  * **Logo Fade & Scale:** Al cargar la pantalla de login, el logo de la aplicación se desvanecerá e incrementará su tamaño suavemente.

---

## 3. Plan de Verificación

### Pruebas de Rendimiento de Animaciones
* Utilizar la herramienta Flutter DevTools para verificar que las animaciones propuestas corran constantemente a **60 o 120 FPS** sin causar caídas de cuadros de animación (jank).
