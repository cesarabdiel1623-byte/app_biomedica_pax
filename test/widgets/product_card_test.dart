import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/product.dart';
import 'package:gomedical_app/screens/home/widgets/product_card.dart';
import 'package:gomedical_app/utils/responsive_grid.dart';

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

      // Verify discount badge and discount pill text
      expect(find.text('-30%'), findsNWidgets(2));

      // Verify current price is rendered
      expect(find.text('\$350 MXN'), findsOneWidget);

      expect(find.text('\$500 MXN'), findsOneWidget);
    },
  );

  testWidgets('ProductCard renders MÁS VENDIDO badge when applicable', (
    WidgetTester tester,
  ) async {
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

    // Home cards keep the same compact product layout used by catalog cards.
    expect(find.text('Seminuevo'), findsNothing);
  });

  testWidgets('product grid stays overflow-free across phone and tablet widths', (
    WidgetTester tester,
  ) async {
    final product = Product(
      id: 'prod-responsive',
      sku: 'SKU-RESPONSIVE',
      name: 'Banco de baterías para ventilador con nombre comercial extendido',
      category: 'refacciones',
      application: 'general',
      unitPriceMxn: 12343,
      costPriceMxn: 9000,
      oldPrice: 14026,
      currency: 'MXN',
      unit: 'pieza',
      isActive: true,
      requiresSerial: false,
      trackInventory: true,
      currentStock: 8,
      minimumStock: 2,
      shippingInfo: 'Envío estándar disponible',
      createdAt: DateTime.now(),
      activePromotion: ActiveProductPromotion(
        productId: 'prod-responsive',
        discountType: 'percentage',
        discountValue: 12,
      ),
    );

    for (final scenario in <({double width, double scale})>[
      (width: 320, scale: 1),
      (width: 360, scale: 1.3),
      (width: 600, scale: 1.5),
      (width: 800, scale: 1.5),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(scenario.width, 1000),
              textScaler: TextScaler.linear(scenario.scale),
            ),
            child: Scaffold(
              body: SizedBox(
                width: scenario.width,
                height: 1000,
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: ResponsiveGrid.productColumnCount(
                      scenario.width - 24,
                    ),
                    mainAxisExtent: ResponsiveGrid.productCardExtent(
                      scenario.scale,
                    ),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: 6,
                  itemBuilder: (_, _) => ProductCard(product: product),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Unexpected layout exception at ${scenario.width}px and ${scenario.scale}x text',
      );
    }
  });
}
