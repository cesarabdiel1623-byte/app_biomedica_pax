import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/main.dart' as app;
import 'package:gomedical_app/screens/home/home_screen.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke test de navegacion principal: Go Medical', (
    WidgetTester tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final loginTitle = find.textContaining('Iniciar Sesion');
    final loginTitleWithAccent = find.textContaining('Iniciar Sesión');
    final textFields = find.byType(TextField);

    if (loginTitle.evaluate().isNotEmpty ||
        loginTitleWithAccent.evaluate().isNotEmpty ||
        textFields.evaluate().isNotEmpty) {
      final currentContext = tester.element(find.byType(Navigator).first);
      Navigator.of(currentContext).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }

    expect(find.byType(MaterialApp), findsOneWidget);

    final cardsFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == 'ProductCard',
    );
    if (cardsFinder.evaluate().isNotEmpty) {
      await tester.tap(cardsFinder.first);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final backBtn = find.byIcon(Icons.arrow_back_ios_new_rounded);
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn.first);
        await tester.pumpAndSettle();
      }
    }

    final cartTab = find.text('Carrito');
    if (cartTab.evaluate().isNotEmpty) {
      await tester.tap(cartTab);
      await tester.pumpAndSettle();
    }

    final inicioTab = find.text('Inicio');
    if (inicioTab.evaluate().isNotEmpty) {
      await tester.tap(inicioTab);
      await tester.pumpAndSettle();
    }

    final searchBar = find.text('Buscar equipo medico');
    final searchBarWithAccent = find.text('Buscar equipo médico');
    final searchFinder = searchBar.evaluate().isNotEmpty
        ? searchBar
        : searchBarWithAccent;

    if (searchFinder.evaluate().isNotEmpty) {
      await tester.tap(searchFinder);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final searchInput = find.byType(TextField);
      if (searchInput.evaluate().isNotEmpty) {
        await tester.enterText(searchInput.first, 'ultrasonido');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
      }

      final backFromSearch = find.byIcon(Icons.arrow_back_ios_new_rounded);
      if (backFromSearch.evaluate().isNotEmpty) {
        await tester.tap(backFromSearch.first);
        await tester.pumpAndSettle();
      }
    }

    final soporteTab = find.text('Soporte');
    if (soporteTab.evaluate().isNotEmpty) {
      await tester.tap(soporteTab);
      await tester.pumpAndSettle();
    }

    // Esta prueba solo valida que la app arranca y que las rutas principales
    // no se rompen. Los flujos de pago, webhooks e inventario deben probarse
    // con pruebas E2E controladas contra staging.
    expect(tester.takeException(), isNull);
  });
}
