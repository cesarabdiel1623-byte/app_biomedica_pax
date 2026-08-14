import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/product.dart';
import 'package:gomedical_app/screens/home/widgets/product_card.dart';

void main() {
  testWidgets('ProductCard renders name, price and stock label correctly', (
    WidgetTester tester,
  ) async {
    final product = Product(
      id: 'prod-123',
      sku: 'SKU-123',
      name: 'Ultrasonido Portátil Chison',
      category: 'ultrasonido_humano',
      application: 'humano',
      unitPriceMxn: 120000.00,
      costPriceMxn: 90000.00,
      currency: 'MXN',
      unit: 'unidad',
      isActive: true,
      requiresSerial: true,
      trackInventory: true,
      currentStock: 5,
      minimumStock: 2,
      createdAt: DateTime.now(),
    );

    // Build the widget in MaterialApp
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 200, child: ProductCard(product: product)),
        ),
      ),
    );

    // 1. Verify product name is rendered
    expect(find.text('Ultrasonido Portátil Chison'), findsOneWidget);

    // 2. Verify formatted price is rendered
    expect(find.text('\$120,000 MXN'), findsOneWidget);

    // 3. Verify stock label
    expect(find.text('Disponible'), findsOneWidget);
  });

  testWidgets(
    'ProductCard renders active promotion price, original price and discount',
    (WidgetTester tester) async {
      final product = Product(
        id: 'prod-discount',
        sku: 'SKU-DISC',
        name: 'Gel USG 5L',
        category: 'consumible',
        application: 'general',
        unitPriceMxn: 350.00,
        costPriceMxn: 200.00,
        oldPrice: 500.00,
        currency: 'MXN',
        unit: 'pieza',
        isActive: true,
        requiresSerial: false,
        trackInventory: true,
        currentStock: 10,
        minimumStock: 2,
        createdAt: DateTime.now(),
        activePromotion: ActiveProductPromotion(
          productId: 'prod-discount',
          discountType: 'percentage',
          discountValue: 30.0,
          campaignName: 'Buen Fin',
        ),
      );

      // Build the widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 200, child: ProductCard(product: product)),
          ),
        ),
      );

      // Verify campaign badge text (rendered inside MarqueeText)
      expect(find.text('BUEN FIN'), findsOneWidget);

      // Verify current price is rendered
      expect(find.text('\$350 MXN'), findsOneWidget);

      expect(find.text('\$500 MXN'), findsOneWidget);
      expect(find.text('-30%'), findsOneWidget);
    },
  );

  testWidgets(
    'ProductCard renders MÁS VENDIDO badge and condition badge when applicable',
    (WidgetTester tester) async {
      // Uses salesCount: 120 which matches the real Ultrasonido animal value in the DB.
      // The card shows MÁS VENDIDO badge when salesCount >= 50 (no activePromotion needed).
      final product = Product(
        id: 'prod-best',
        sku: 'SKU-BEST',
        name: 'Gel USG 5L',
        category: 'consumible',
        application: 'general',
        unitPriceMxn: 350.00,
        costPriceMxn: 200.00,
        currency: 'MXN',
        unit: 'pieza',
        isActive: true,
        requiresSerial: false,
        trackInventory: true,
        currentStock: 10,
        minimumStock: 2,
        createdAt: DateTime.now(),
        salesCount: 120,
        productCondition: 'preowned',
      );

      // Build the widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 200, child: ProductCard(product: product)),
          ),
        ),
      );

      // Verify best seller badge
      expect(find.text('MÁS VENDIDO'), findsOneWidget);

      // Verify condition badge
      expect(find.text('Seminuevo'), findsOneWidget);
    },
  );
}
