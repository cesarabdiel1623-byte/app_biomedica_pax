import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/customer_coupon.dart';
import 'package:gomedical_app/screens/profile/coupons_screen.dart';
import 'package:gomedical_app/services/cart_service.dart';

void main() {
  group('CouponsScreen Widget Tests', () {
    final sampleAvailableCoupon = CustomerCoupon.fromRpc({
      'coupon_id': 'c-01',
      'code': 'BIENVENIDA15',
      'name': 'Descuento de Bienvenida',
      'public_description': 'Aplica en tu primera compra médica',
      'discount_type': 'percentage',
      'discount_value': 15,
      'minimum_subtotal': 1500,
      'valid_until': '2026-08-25T18:00:00Z',
      'client_usage_limit': 1,
      'client_uses': 0,
      'remaining_uses': 1,
      'coupon_state': 'available',
    });

    final sampleUsedCoupon = CustomerCoupon.fromRpc({
      'coupon_id': 'c-02',
      'code': 'USADO10',
      'name': 'Cupón Usado',
      'discount_type': 'fixed_amount',
      'discount_value': 100,
      'coupon_state': 'used',
    });

    final sampleExpiredCoupon = CustomerCoupon.fromRpc({
      'coupon_id': 'c-03',
      'code': 'VENCIDO20',
      'name': 'Cupón Vencido',
      'discount_type': 'percentage',
      'discount_value': 20,
      'coupon_state': 'expired',
    });

    final sampleNotStartedCoupon = CustomerCoupon.fromRpc({
      'coupon_id': 'c-04',
      'code': 'FUTURO50',
      'name': 'Cupón Futuro',
      'discount_type': 'fixed_amount',
      'discount_value': 50,
      'coupon_state': 'not_started',
    });

    testWidgets('N: Muestra empty state correcto cuando la lista está vacía', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CouponsScreen(
            couponsLoader: () async => const [],
            hasActiveCartLoader: () async => false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Mis Cupones'), findsOneWidget);
      expect(find.text('No tienes cupones disponibles'), findsOneWidget);
      expect(
        find.text('Cuando tengas descuentos disponibles aparecerán aquí.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'O: Muestra error state correcto con mensaje sanitizado y botón Reintentar',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => throw Exception('server_error'),
              hasActiveCartLoader: () async => false,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('No pudimos cargar tus cupones.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );

    testWidgets(
      'J, E: Renderiza cupón disponible con beneficio, código y botón Copiar código',
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
        expect(find.text('15% de descuento'), findsOneWidget);
        expect(find.text('BIENVENIDA15'), findsOneWidget);
        expect(find.text('Descuento de Bienvenida'), findsOneWidget);
        expect(find.text('Aplica en tu primera compra médica'), findsOneWidget);
        expect(find.text('Disponible'), findsOneWidget);
        expect(find.text('Compra mínima: \$1500 MXN'), findsOneWidget);
        expect(find.text('Copiar'), findsOneWidget);
        // Si no hay carrito activo, no muestra Usar cupón
        expect(find.text('Usar cupón'), findsNothing);
      },
    );

    testWidgets(
      'K, L, M: Cupones no disponibles (used, expired, not_started) no permiten aplicar',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [
                sampleUsedCoupon,
                sampleExpiredCoupon,
                sampleNotStartedCoupon,
              ],
              hasActiveCartLoader: () async => true,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('OTROS CUPONES'), findsOneWidget);
        expect(find.text('Utilizado'), findsOneWidget);
        expect(find.text('Vencido'), findsOneWidget);
        expect(find.text('Próximamente'), findsOneWidget);
        // Ninguno de estos estados debe mostrar Usar cupón
        expect(find.text('Usar cupón'), findsNothing);
      },
    );

    testWidgets(
      'Banner de disclaimer de seguridad y elegibilidad está presente',
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

        expect(
          find.text(
            'Las condiciones finales se validan al aplicar el cupón en el carrito.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'P: Renderiza sin RenderFlex overflow en viewport estrecho de 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [
                sampleAvailableCoupon,
                sampleUsedCoupon,
                sampleExpiredCoupon,
              ],
              hasActiveCartLoader: () async => true,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('BIENVENIDA15'), findsOneWidget);
      },
    );

    testWidgets('Q: Campos internos nunca aparecen en el árbol de widgets', (
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

      expect(find.text('internal_notes'), findsNothing);
      expect(find.text('created_by'), findsNothing);
      expect(find.text('assigned_by'), findsNothing);
    });

    test('A: profile_tab.dart incluye acceso a Cupones con su subtítulo', () {
      final profileTabSource = File(
        'lib/screens/home/tabs/profile_tab.dart',
      ).readAsStringSync();

      expect(profileTabSource, contains("'Cupones'"));
      expect(profileTabSource, contains("'Descuentos disponibles para ti'"));
      expect(profileTabSource, contains('CouponsScreen()'));
    });

    testWidgets(
      'B: Navegación hacia CouponsScreen renderiza el título Mis Cupones',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CouponsScreen(
                        couponsLoader: () async => const [],
                        hasActiveCartLoader: () async => false,
                      ),
                    ),
                  ),
                  child: const Text('Ir a Cupones'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Ir a Cupones'));
        await tester.pumpAndSettle();

        expect(find.text('Mis Cupones'), findsOneWidget);
      },
    );

    testWidgets(
      'I: Cupón limit_reached no permite aplicar (no muestra Usar cupón)',
      (tester) async {
        final sampleLimitReached = CustomerCoupon.fromRpc({
          'coupon_id': 'c-05',
          'code': 'AGOTADO10',
          'name': 'Cupón Agotado',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': 'limit_reached',
        });

        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [sampleLimitReached],
              hasActiveCartLoader: () async => true,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Límite alcanzado'), findsOneWidget);
        expect(find.text('Usar cupón'), findsNothing);
      },
    );

    testWidgets(
      'Cupón con coupon_state desconocido muestra No disponible y bloquea Usar cupón',
      (tester) async {
        final sampleUnknown = CustomerCoupon.fromRpc({
          'coupon_id': 'c-06',
          'code': 'DESCONOCIDO',
          'name': 'Cupón Raro',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': 'invalido_xyz',
        });

        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [sampleUnknown],
              hasActiveCartLoader: () async => true,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('No disponible'), findsOneWidget);
        expect(find.text('Usar cupón'), findsNothing);
      },
    );

    testWidgets(
      'F: Fallo técnico/exception al aplicar cupón muestra mensaje sanitizado y NO expone e.toString()',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [sampleAvailableCoupon],
              hasActiveCartLoader: () async => true,
              couponApplier: (code) async {
                throw Exception(
                  'PostgrestException(message: internal syntax error in pg_catalog.rpc, code: 42883)',
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Usar cupón'), findsOneWidget);

        await tester.tap(find.text('Usar cupón'));
        await tester.pumpAndSettle();

        // UI muestra mensaje sanitizado
        expect(
          find.text(
            'No pudimos aplicar el cupón. Verifica las condiciones e inténtalo de nuevo.',
          ),
          findsOneWidget,
        );
        // UI NO expone detalles técnicos
        expect(find.textContaining('PostgrestException'), findsNothing);
        expect(find.textContaining('syntax error'), findsNothing);
        expect(find.textContaining('42883'), findsNothing);
        expect(find.textContaining('pg_catalog'), findsNothing);
      },
    );

    testWidgets(
      'G: Backend devuelve reason conocido minimum_not_met -> muestra mensaje UX seguro',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [sampleAvailableCoupon],
              hasActiveCartLoader: () async => true,
              couponApplier: (code) async {
                return const CartCouponResult(
                  valid: false,
                  reason: 'minimum_not_met',
                  message: 'raw db minimum_not_met',
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('Usar cupón'));
        await tester.pumpAndSettle();

        expect(
          find.text('Tu compra todavía no alcanza el monto mínimo requerido.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'H: Backend devuelve reason desconocido -> muestra mensaje genérico sanitizado',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CouponsScreen(
              couponsLoader: () async => [sampleAvailableCoupon],
              hasActiveCartLoader: () async => true,
              couponApplier: (code) async {
                return const CartCouponResult(
                  valid: false,
                  reason: 'error_interno_db_cluster_99',
                  message: 'raw error database cluster',
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('Usar cupón'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'No pudimos aplicar el cupón. Verifica las condiciones e inténtalo de nuevo.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('error_interno_db_cluster_99'),
          findsNothing,
        );
        expect(find.textContaining('raw error'), findsNothing);
      },
    );

    testWidgets(
      'Mapeo de razones conocidas adicionales (not_assigned, expired, not_combinable, usage_limit_reached)',
      (tester) async {
        final cases = [
          ('not_assigned', 'Este cupón no está disponible para tu cuenta.'),
          ('expired', 'Este cupón ya venció.'),
          ('not_started', 'Este cupón todavía no está disponible.'),
          (
            'not_combinable',
            'Este cupón no puede combinarse con las promociones actuales.',
          ),
          ('usage_limit_reached', 'Este cupón alcanzó su límite de usos.'),
          (
            'client_limit_reached',
            'Ya utilizaste el número máximo de veces permitido.',
          ),
          (
            'first_purchase_required',
            'Este cupón es exclusivo para la primera compra.',
          ),
        ];

        for (final (reason, expectedMsg) in cases) {
          expect(CouponsScreen.sanitizeCouponApplyReason(reason), expectedMsg);
        }
      },
    );
  });
}
