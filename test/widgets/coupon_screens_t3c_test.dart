import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/customer_coupon.dart';
import 'package:gomedical_app/screens/profile/coupon_conditions_screen.dart';
import 'package:gomedical_app/screens/profile/coupons_screen.dart';

void main() {
  group('T3C — Model & Security Definer Privacy', () {
    test('CustomerCoupon parses public_terms and ignores internal_notes', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': '00000000-0000-0000-0000-000000000001',
        'code': 'TERMS10',
        'name': 'Cupón con términos',
        'public_description': '10% de descuento',
        'public_terms':
            'Válido solo en compras mayores a \$1,000 MXN.\nNo acumulable con otras promociones.',
        'internal_notes': 'Margen 25% - no revelar al cliente',
        'discount_type': 'percentage',
        'discount_value': 10,
        'coupon_state': 'available',
      });

      expect(
        coupon.publicTerms,
        equals(
          'Válido solo en compras mayores a \$1,000 MXN.\nNo acumulable con otras promociones.',
        ),
      );
      expect(coupon.publicDescription, equals('10% de descuento'));
    });

    test(
      'CustomerCoupon normalizes empty or whitespace public_terms to null',
      () {
        final coupon = CustomerCoupon.fromRpc({
          'coupon_id': '00000000-0000-0000-0000-000000000002',
          'code': 'EMPTYTERMS',
          'name': 'Cupón sin términos',
          'public_terms': '   ',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': 'available',
        });

        expect(coupon.publicTerms, isNull);
      },
    );
  });

  group('T3C — CouponConditionsScreen Public Terms Presentation', () {
    testWidgets(
      'Renders Condiciones adicionales section when publicTerms is present',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final couponWithTerms = CustomerCoupon.fromRpc({
          'coupon_id': '00000000-0000-0000-0000-000000000001',
          'code': 'MEDICO15',
          'name': 'Descuento Médico',
          'public_description': '15% en ultrasonidos',
          'public_terms':
              'Válido exclusivamente en la app móvil.\nAplica únicamente a productos participantes.\nNo acumulable con servicios técnicos.',
          'discount_type': 'percentage',
          'discount_value': 15,
          'minimum_subtotal': 2000,
          'coupon_state': 'available',
        });

        await tester.pumpWidget(
          MaterialApp(home: CouponConditionsScreen(coupon: couponWithTerms)),
        );

        await tester.pumpAndSettle();

        expect(find.text('Condiciones adicionales'), findsOneWidget);
        expect(
          find.text(
            'Válido exclusivamente en la app móvil.\nAplica únicamente a productos participantes.\nNo acumulable con servicios técnicos.',
          ),
          findsOneWidget,
        );

        // Verify no internal notes are visible
        expect(find.text('Margen'), findsNothing);
        expect(find.text('internal_notes'), findsNothing);
      },
    );

    testWidgets(
      'Does NOT render Condiciones adicionales section when publicTerms is null',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final couponWithoutTerms = CustomerCoupon.fromRpc({
          'coupon_id': '00000000-0000-0000-0000-000000000002',
          'code': 'NOTERMS',
          'name': 'Cupón Simple',
          'public_description': 'Sin términos extra',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': 'available',
        });

        await tester.pumpWidget(
          MaterialApp(home: CouponConditionsScreen(coupon: couponWithoutTerms)),
        );

        await tester.pumpAndSettle();

        expect(find.text('Condiciones adicionales'), findsNothing);
      },
    );
  });

  group('T3C — Mis Cupones UI Polish & Responsiveness', () {
    final sampleAvailableCoupon = CustomerCoupon.fromRpc({
      'coupon_id': '00000000-0000-0000-0000-000000000001',
      'code': 'POLISHED15',
      'name': 'Descuento Pulido',
      'public_description': '15% en equipos',
      'public_terms': 'Términos adicionales administrativos.',
      'discount_type': 'percentage',
      'discount_value': 15,
      'minimum_subtotal': 1000,
      'coupon_state': 'available',
    });

    final sampleExpiredCoupon = CustomerCoupon.fromRpc({
      'coupon_id': '00000000-0000-0000-0000-000000000002',
      'code': 'VENCIDO2026',
      'name': 'Cupón Vencido',
      'discount_type': 'fixed_amount',
      'discount_value': 100,
      'coupon_state': 'expired',
    });

    testWidgets(
      'Available coupon has active Ver productos and Ver condiciones buttons',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [sampleAvailableCoupon],
              hasActiveCartLoader: () async => false,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('DISPONIBLES'), findsOneWidget);
        expect(find.text('POLISHED15'), findsOneWidget);
        expect(find.text('Ver condiciones'), findsOneWidget);
        expect(find.text('Ver productos'), findsOneWidget);
        expect(find.text('Copiar'), findsOneWidget);
      },
    );

    testWidgets(
      'Expired coupon has muted design and no active Ver productos button',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [sampleExpiredCoupon],
              hasActiveCartLoader: () async => false,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('OTROS CUPONES'), findsOneWidget);
        expect(find.text('VENCIDO2026'), findsOneWidget);
        expect(find.text('Vencido'), findsOneWidget);
        expect(find.text('Ver condiciones'), findsOneWidget);
        expect(find.text('Ver productos'), findsNothing);
      },
    );

    testWidgets(
      'Responsive rendering on narrow 320px viewport without overflow',
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

    testWidgets(
      'Responsive rendering on standard 360px and 390px viewports without overflow',
      (tester) async {
        for (final width in [360.0, 390.0]) {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1.0;

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
        }
        tester.view.resetPhysicalSize();
      },
    );
  });
}
