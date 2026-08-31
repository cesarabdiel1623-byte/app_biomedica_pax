import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/customer_coupon.dart';
import 'package:gomedical_app/models/product.dart';
import 'package:gomedical_app/screens/product/product_detail_screen.dart';
import 'package:gomedical_app/screens/profile/coupon_conditions_screen.dart';
import 'package:gomedical_app/screens/profile/coupon_eligible_products_screen.dart';
import 'package:gomedical_app/screens/profile/coupons_screen.dart';
import 'package:gomedical_app/services/coupon_service.dart';

Product _createMockProduct(String id, String name, double price) {
  return Product(
    id: id,
    sku: 'SKU-$id',
    name: name,
    category: 'ultrasonido_humano',
    application: 'humano',
    unitPriceMxn: price,
    costPriceMxn: price * 0.8,
    currency: 'MXN',
    unit: 'unidad',
    isActive: true,
    requiresSerial: false,
    trackInventory: true,
    currentStock: 10,
    minimumStock: 1,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('T3B — Mis Cupones UI & Actions', () {
    final sampleAvailableCoupon = CustomerCoupon.fromRpc({
      'coupon_id': '00000000-0000-0000-0000-000000000001',
      'code': 'BIENVENIDA15',
      'name': 'Descuento de Bienvenida',
      'public_description': 'Aplica en tu compra médica de equipos',
      'discount_type': 'percentage',
      'discount_value': 15,
      'minimum_subtotal': 1500,
      'maximum_discount': 500,
      'valid_from': '2026-08-01T00:00:00Z',
      'valid_until': '2026-12-31T23:59:59Z',
      'combinable_with_promotions': false,
      'catalog_scope': 'all',
      'client_usage_limit': 2,
      'client_uses': 0,
      'remaining_uses': 2,
      'coupon_state': 'available',
    });

    final sampleExpiredCoupon = CustomerCoupon.fromRpc({
      'coupon_id': '00000000-0000-0000-0000-000000000002',
      'code': 'EXPIRADO10',
      'name': 'Cupón Expirado',
      'public_description': 'Ya no disponible',
      'discount_type': 'fixed_amount',
      'discount_value': 100,
      'minimum_subtotal': 0,
      'valid_until': '2026-08-10T00:00:00Z',
      'coupon_state': 'expired',
    });

    testWidgets(
      'Renders separate sections for Disponibles and Otros cupones with action buttons',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [
                sampleAvailableCoupon,
                sampleExpiredCoupon,
              ],
              hasActiveCartLoader: () async => false,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('DISPONIBLES'), findsOneWidget);
        expect(find.text('OTROS CUPONES'), findsOneWidget);

        expect(find.text('BIENVENIDA15'), findsOneWidget);
        expect(find.text('15% de descuento'), findsOneWidget);
        expect(find.text('Compra mínima: \$1500 MXN'), findsOneWidget);

        // Available card has "Ver condiciones" and "Ver productos"
        expect(find.text('Ver condiciones'), findsNWidgets(2));
        expect(find.text('Ver productos'), findsOneWidget);
      },
    );

    testWidgets('Tapping Ver condiciones opens CouponConditionsScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CouponsScreen(
            couponsLoader: () async => [sampleAvailableCoupon],
            hasActiveCartLoader: () async => false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver condiciones'));
      await tester.pumpAndSettle();

      expect(find.text('Condiciones del cupón'), findsOneWidget);
      expect(find.text('Detalles y restricciones'), findsOneWidget);
    });

    testWidgets('Tapping Ver productos opens CouponEligibleProductsScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CouponsScreen(
            couponsLoader: () async => [sampleAvailableCoupon],
            hasActiveCartLoader: () async => false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver productos'));
      await tester.pumpAndSettle();

      expect(find.text('Productos participantes'), findsOneWidget);
    });

    testWidgets(
      'Responsive rendering on narrow 320px screen without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [
                sampleAvailableCoupon,
                sampleExpiredCoupon,
              ],
              hasActiveCartLoader: () async => false,
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('T3B — CouponConditionsScreen Tests', () {
    final sampleCoupon = CustomerCoupon.fromRpc({
      'coupon_id': '00000000-0000-0000-0000-000000000001',
      'code': 'PROMO20',
      'name': 'Gran Promoción',
      'public_description': 'Descuento especial de temporada',
      'discount_type': 'percentage',
      'discount_value': 20,
      'minimum_subtotal': 2500,
      'maximum_discount': 1000,
      'valid_from': '2026-08-01T00:00:00Z',
      'valid_until': '2026-08-31T23:59:59Z',
      'combinable_with_promotions': true,
      'catalog_scope': 'all',
      'client_usage_limit': 1,
      'client_uses': 0,
      'remaining_uses': 1,
      'coupon_state': 'available',
    });

    testWidgets(
      'Renders all applicable condition sections cleanly without inventing fields',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(home: CouponConditionsScreen(coupon: sampleCoupon)),
        );

        await tester.pumpAndSettle();

        expect(find.text('Condiciones del cupón'), findsOneWidget);
        expect(find.text('20% de descuento'), findsNWidgets(2));
        expect(find.text('Gran Promoción'), findsOneWidget);
        expect(find.text('Descuento especial de temporada'), findsOneWidget);

        expect(find.text('DESCUENTO'), findsOneWidget);
        expect(find.text('COMPRA MÍNIMA'), findsOneWidget);
        expect(find.text('\$2,500.00 MXN'), findsOneWidget);
        expect(find.text('DESCUENTO MÁXIMO'), findsOneWidget);
        expect(find.text('\$1,000.00 MXN'), findsOneWidget);
        expect(find.text('VIGENCIA'), findsOneWidget);
        expect(find.text('LÍMITE DE USOS'), findsOneWidget);
        expect(find.text('1 uso restante'), findsOneWidget);
        expect(find.text('PROMOCIONES'), findsOneWidget);
        expect(
          find.text('Acumulable con otras promociones activas'),
          findsOneWidget,
        );
        expect(find.text('PRODUCTOS PARTICIPANTES'), findsOneWidget);
        expect(
          find.text('Aplica a todo el catálogo disponible'),
          findsOneWidget,
        );

        // Does NOT invent first_purchase_only
        expect(find.text('first_purchase_only'), findsNothing);
        expect(find.text('Primera compra'), findsNothing);

        // Action button
        expect(find.text('Ver productos participantes'), findsOneWidget);
      },
    );

    testWidgets('Omission of null fields does not break layout', (
      tester,
    ) async {
      final minimalCoupon = CustomerCoupon.fromRpc({
        'coupon_id': '00000000-0000-0000-0000-000000000002',
        'code': 'SIMPLE',
        'name': 'Cupón Simple',
        'discount_type': 'fixed_amount',
        'discount_value': 50,
        'minimum_subtotal': 0,
        'coupon_state': 'expired',
      });

      await tester.pumpWidget(
        MaterialApp(home: CouponConditionsScreen(coupon: minimalCoupon)),
      );

      await tester.pumpAndSettle();

      expect(find.text('Condiciones del cupón'), findsOneWidget);
      expect(find.text('\$50 MXN de descuento'), findsNWidgets(2));
      expect(find.text('COMPRA MÍNIMA'), findsNothing);
      expect(find.text('DESCUENTO MÁXIMO'), findsNothing);
      // Expired coupon does not show active "Ver productos participantes" button
      expect(find.text('Ver productos participantes'), findsNothing);
    });
  });

  group('T3B — CouponEligibleProductsScreen Tests', () {
    final sampleCoupon = CustomerCoupon.fromRpc({
      'coupon_id': '00000000-0000-0000-0000-000000000001',
      'code': 'BIENVENIDA15',
      'name': 'Descuento Bienvenida',
      'discount_type': 'percentage',
      'discount_value': 15,
      'coupon_state': 'available',
    });

    testWidgets(
      'Initial load: fetches eligible product IDs and products with strictly 2 calls',
      (tester) async {
        int rpcCalls = 0;
        int productCalls = 0;

        final mockProduct1 = _createMockProduct(
          '11111111-1111-1111-1111-111111111111',
          'Monitor de Signos Vitales',
          15000,
        );
        final mockProduct2 = _createMockProduct(
          '22222222-2222-2222-2222-222222222222',
          'Electrocardiógrafo Digital',
          25000,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: CouponEligibleProductsScreen(
              coupon: sampleCoupon,
              eligibleProductsLoader:
                  ({
                    required String couponId,
                    String? search,
                    int limit = 20,
                    int offset = 0,
                  }) async {
                    rpcCalls++;
                    return CouponEligibleProductsResult(
                      productIds: [
                        '11111111-1111-1111-1111-111111111111',
                        '22222222-2222-2222-2222-222222222222',
                      ],
                      totalCount: 2,
                      isFullCatalog: true,
                    );
                  },
              productsLoader: (ids) async {
                productCalls++;
                return [mockProduct1, mockProduct2];
              },
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(rpcCalls, equals(1));
        expect(productCalls, equals(1));

        expect(find.text('Productos participantes'), findsOneWidget);
        expect(find.text('BIENVENIDA15'), findsOneWidget);
        expect(find.text('2 productos'), findsOneWidget);
        expect(
          find.text('Este cupón aplica a todo el catálogo disponible.'),
          findsOneWidget,
        );
        expect(find.text('Monitor de Signos Vitales'), findsOneWidget);
        expect(find.text('Electrocardiógrafo Digital'), findsOneWidget);
      },
    );

    testWidgets('Search with debounce filters products', (tester) async {
      String? lastSearchReceived;

      await tester.pumpWidget(
        MaterialApp(
          home: CouponEligibleProductsScreen(
            coupon: sampleCoupon,
            eligibleProductsLoader:
                ({
                  required String couponId,
                  String? search,
                  int limit = 20,
                  int offset = 0,
                }) async {
                  lastSearchReceived = search;
                  if (search == 'ultrasonido') {
                    return CouponEligibleProductsResult(
                      productIds: ['11111111-1111-1111-1111-111111111111'],
                      totalCount: 1,
                      isFullCatalog: false,
                    );
                  }
                  return CouponEligibleProductsResult(
                    productIds: [],
                    totalCount: 0,
                    isFullCatalog: false,
                  );
                },
            productsLoader: (ids) async {
              return [_createMockProduct(ids.first, 'Ultrasonido Pro', 50000)];
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), 'ultrasonido');

      // Debounce timer is 400ms
      await tester.pump(const Duration(milliseconds: 200));
      expect(lastSearchReceived, isNull);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(lastSearchReceived, equals('ultrasonido'));
      expect(find.text('Ultrasonido Pro'), findsOneWidget);
      expect(find.text('1 producto'), findsOneWidget);
    });

    testWidgets('Empty search results displays appropriate empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CouponEligibleProductsScreen(
            coupon: sampleCoupon,
            eligibleProductsLoader:
                ({
                  required String couponId,
                  String? search,
                  int limit = 20,
                  int offset = 0,
                }) async {
                  return CouponEligibleProductsResult(
                    productIds: [],
                    totalCount: 0,
                    isFullCatalog: false,
                  );
                },
            productsLoader: (ids) async => [],
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Empty with no search
      expect(
        find.text('No hay productos participantes disponibles actualmente'),
        findsOneWidget,
      );

      // Enter search
      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        find.text('No encontramos productos con esa búsqueda'),
        findsOneWidget,
      );
      expect(find.text('Limpiar búsqueda'), findsOneWidget);
    });

    testWidgets('Error state displays LoadErrorState and allows retry', (
      tester,
    ) async {
      int attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CouponEligibleProductsScreen(
            coupon: sampleCoupon,
            eligibleProductsLoader:
                ({
                  required String couponId,
                  String? search,
                  int limit = 20,
                  int offset = 0,
                }) async {
                  attempts++;
                  if (attempts == 1) throw Exception('Database error');
                  return CouponEligibleProductsResult(
                    productIds: ['11111111-1111-1111-1111-111111111111'],
                    totalCount: 1,
                    isFullCatalog: false,
                  );
                },
            productsLoader: (ids) async => [
              _createMockProduct(ids.first, 'Producto Recuperado', 1000),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar los productos participantes del cupón.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Producto Recuperado'), findsOneWidget);
    });

    testWidgets('Tapping product card navigates to ProductDetailScreen', (
      tester,
    ) async {
      final mockProduct = _createMockProduct(
        '11111111-1111-1111-1111-111111111111',
        'Esterilizador Autoclave',
        30000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CouponEligibleProductsScreen(
            coupon: sampleCoupon,
            eligibleProductsLoader:
                ({
                  required String couponId,
                  String? search,
                  int limit = 20,
                  int offset = 0,
                }) async {
                  return CouponEligibleProductsResult(
                    productIds: ['11111111-1111-1111-1111-111111111111'],
                    totalCount: 1,
                    isFullCatalog: false,
                  );
                },
            productsLoader: (ids) async => [mockProduct],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Esterilizador Autoclave'), findsOneWidget);

      await tester.tap(find.text('Esterilizador Autoclave'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
    });
  });
}
