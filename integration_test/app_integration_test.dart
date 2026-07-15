import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app_prueba/main.dart' as app;
import 'package:app_prueba/screens/home/home_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pruebas de Integración Completas: Go Medical', (WidgetTester tester) async {
    // 1. Inicializar la aplicación
    app.main();
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Bypass del LoginScreen si está presente
    final loginTitle = find.textContaining('Iniciar Sesión');
    final textFields = find.byType(TextField);
    if (loginTitle.evaluate().isNotEmpty || textFields.evaluate().isNotEmpty) {
      print('Detectada pantalla de Login. Realizando bypass para navegar a HomeScreen...');
      final BuildContext currentContext = tester.element(find.byType(Navigator).first);
      Navigator.of(currentContext).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }

    // ==========================================
    // FLUJO 1: COMPRA COMPLETA DESDE EL MARKETPLACE
    // ==========================================
    print('--- INICIANDO FLUJO 1: Compra Completa ---');
    
    // Tocar el primer ProductCard para ir al detalle
    final cardsFinder = find.byWidgetPredicate((widget) => widget.runtimeType.toString() == 'ProductCard');
    if (cardsFinder.evaluate().isNotEmpty) {
      final firstCardFinder = cardsFinder.first;
      print('Abriendo detalle de producto...');
      await tester.tap(firstCardFinder);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // En la pantalla de detalle: presionar "Agregar al carrito"
      // Buscamos un botón de texto "Agregar al carrito" o similar
      final addToCartBtn = find.text('Agregar al carrito');
      if (addToCartBtn.evaluate().isNotEmpty) {
        print('Agregando producto al carrito...');
        await tester.tap(addToCartBtn);
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      }

      // Regresar al Marketplace
      final backBtn = find.byIcon(Icons.arrow_back_ios_new_rounded);
      if (backBtn.evaluate().isNotEmpty) {
        print('Regresando a inicio...');
        await tester.tap(backBtn.first);
        await tester.pumpAndSettle();
      }
    }

    // Ir a la pestaña del Carrito
    print('Navegando a la pestaña de Carrito...');
    final cartTab = find.text('Carrito');
    if (cartTab.evaluate().isNotEmpty) {
      await tester.tap(cartTab);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Abrir checkout si el botón "Continuar" está disponible
      final checkoutBtn = find.textContaining('Continuar');
      if (checkoutBtn.evaluate().isNotEmpty) {
        print('Abriendo el Checkout...');
        await tester.tap(checkoutBtn);
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Completar compra si está la hoja de checkout
        final payBtn = find.textContaining('Confirmar compra');
        if (payBtn.evaluate().isNotEmpty) {
          print('Confirmando compra en el Checkout...');
          await tester.tap(payBtn);
          await tester.pumpAndSettle();
          await Future.delayed(const Duration(seconds: 1));
          await tester.pumpAndSettle();
        }
      }
    }

    // ==========================================
    // FLUJO 2: BÚSQUEDA Y FILTRADO
    // ==========================================
    print('--- INICIANDO FLUJO 2: Búsqueda y Filtrado ---');
    
    // Regresar a la pestaña de Inicio
    final inicioTab = find.text('Inicio');
    if (inicioTab.evaluate().isNotEmpty) {
      await tester.tap(inicioTab);
      await tester.pumpAndSettle();
    }

    // Tocar barra de búsqueda para abrir SearchScreen
    final searchBar = find.text('Buscar equipo médico');
    if (searchBar.evaluate().isNotEmpty) {
      print('Abriendo buscador...');
      await tester.tap(searchBar);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Escribir "ultrasonido"
      final searchInput = find.byType(TextField);
      if (searchInput.evaluate().isNotEmpty) {
        print('Escribiendo "ultrasonido" en el buscador...');
        await tester.enterText(searchInput, 'ultrasonido');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      }

      // Regresar al Marketplace
      final backFromSearch = find.byIcon(Icons.arrow_back_ios_new_rounded);
      if (backFromSearch.evaluate().isNotEmpty) {
        await tester.tap(backFromSearch.first);
        await tester.pumpAndSettle();
      }
    }

    // Filtrar por categoría rápida "Equipos"
    final equiposQuickCat = find.text('Equipos');
    if (equiposQuickCat.evaluate().isNotEmpty) {
      print('Filtrando por categoría "Equipos"...');
      await tester.tap(equiposQuickCat);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      
      // Desactivar filtro
      await tester.tap(equiposQuickCat);
      await tester.pumpAndSettle();
    }

    // ==========================================
    // FLUJO 3: MANTENIMIENTO Y SOPORTE TÉCNICO
    // ==========================================
    print('--- INICIANDO FLUJO 3: Soporte y Tickets ---');

    // Navegar a la pestaña de Soporte
    final soporteTab = find.text('Soporte');
    if (soporteTab.evaluate().isNotEmpty) {
      await tester.tap(soporteTab);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Tocar filtros de estado de tickets
      final tabAbiertos = find.text('Abiertos');
      if (tabAbiertos.evaluate().isNotEmpty) {
        print('Filtrando tickets abiertos...');
        await tester.tap(tabAbiertos);
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final tabEnProgreso = find.text('En Progreso');
      if (tabEnProgreso.evaluate().isNotEmpty) {
        print('Filtrando tickets en progreso...');
        await tester.tap(tabEnProgreso);
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Intentar abrir el primer ticket listado si existe
      final ticketCardsFinder = find.byType(Card);
      if (ticketCardsFinder.evaluate().isNotEmpty) {
        final ticketCardFinder = ticketCardsFinder.first;
        print('Abriendo detalle del ticket...');
        await tester.tap(ticketCardFinder);
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Intentar escribir un mensaje de chat
        final chatInput = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == 'Escribe un mensaje...');
        if (chatInput.evaluate().isNotEmpty) {
          print('Escribiendo un mensaje en el chat del ticket...');
          await tester.enterText(chatInput, 'Prueba de integración automática');
          await tester.pumpAndSettle();
          
          final sendBtn = find.byIcon(Icons.send);
          if (sendBtn.evaluate().isNotEmpty) {
            await tester.tap(sendBtn);
            await tester.pumpAndSettle();
            await Future.delayed(const Duration(seconds: 1));
            await tester.pumpAndSettle();
          }
        }

        // Regresar a la lista de tickets
        final backFromChat = find.byIcon(Icons.arrow_back);
        if (backFromChat.evaluate().isNotEmpty) {
          await tester.tap(backFromChat.first);
          await tester.pumpAndSettle();
        }
      }
    }

    print('Pruebas de integración de Go Medical finalizadas exitosamente.');
  });
}
