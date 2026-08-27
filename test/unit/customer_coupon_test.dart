import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/customer_coupon.dart';

void main() {
  group('CustomerCoupon Unit Tests', () {
    test('E: percentage renderiza correctamente en benefitText', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-01',
        'code': 'PROMO15',
        'name': 'Descuento 15%',
        'discount_type': 'percentage',
        'discount_value': 15,
        'coupon_state': 'available',
      });

      expect(coupon.benefitText, '15% de descuento');
      expect(coupon.discountType, 'percentage');
      expect(coupon.discountValue, 15.0);
    });

    test('E: percentage con decimales renderiza correctamente', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-01b',
        'code': 'PROMO12_5',
        'name': 'Descuento 12.5%',
        'discount_type': 'percentage',
        'discount_value': '12.5',
        'coupon_state': 'available',
      });

      expect(coupon.benefitText, '12.5% de descuento');
    });

    test('F: fixed_amount renderiza correctamente', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-02',
        'code': 'REBAJA250',
        'name': 'Bono \$250',
        'discount_type': 'fixed_amount',
        'discount_value': '250.00',
        'coupon_state': 'available',
      });

      expect(coupon.benefitText, '\$250 MXN de descuento');
    });

    test('G: free_shipping renderiza correctamente', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-03',
        'code': 'ENVIOGRATIS',
        'name': 'Envío sin costo',
        'discount_type': 'free_shipping',
        'discount_value': 0,
        'coupon_state': 'available',
      });

      expect(coupon.benefitText, 'Envío gratis');
    });

    test('H: minimum_subtotal aparece sólo cuando corresponde (> 0)', () {
      final couponWithoutMin = CustomerCoupon.fromRpc({
        'coupon_id': 'c-04',
        'code': 'SINMINIMO',
        'name': 'Cupón sin mínimo',
        'discount_type': 'percentage',
        'discount_value': 10,
        'minimum_subtotal': 0,
        'coupon_state': 'available',
      });
      expect(couponWithoutMin.minimumSubtotalText, isNull);

      final couponWithMin = CustomerCoupon.fromRpc({
        'coupon_id': 'c-05',
        'code': 'CONMINIMO',
        'name': 'Cupón con mínimo',
        'discount_type': 'percentage',
        'discount_value': 10,
        'minimum_subtotal': '1500.00',
        'coupon_state': 'available',
      });
      expect(couponWithMin.minimumSubtotalText, 'Compra mínima: \$1500 MXN');
    });

    test('I: valid_until se formatea local correctamente', () {
      // Create UTC date 2026-08-25 18:00:00Z
      final utcDate = DateTime.utc(2026, 8, 25, 18, 0, 0);
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-06',
        'code': 'VIGENCIA',
        'name': 'Cupón con fecha',
        'discount_type': 'percentage',
        'discount_value': 10,
        'valid_until': utcDate.toIso8601String(),
        'coupon_state': 'available',
      });

      expect(coupon.validUntil, isNotNull);
      expect(coupon.formattedValidUntil, contains('ago.'));
      expect(coupon.formattedValidUntil, contains('2026'));
      expect(coupon.formattedValidUntil, startsWith('Válido hasta el '));
    });

    test('Estados de cupón y helpers de estado', () {
      final states = [
        ('available', 'Disponible', true, false, false, false, false),
        ('not_started', 'Próximamente', false, true, false, false, false),
        ('used', 'Utilizado', false, false, true, false, false),
        ('expired', 'Vencido', false, false, false, true, false),
        ('limit_reached', 'Límite alcanzado', false, false, false, false, true),
      ];

      for (final (state, label, isAvail, isNotSt, isUsd, isExp, isLim)
          in states) {
        final coupon = CustomerCoupon.fromRpc({
          'coupon_id': 'c-test',
          'code': 'TEST',
          'name': 'Test Coupon',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': state,
        });

        expect(coupon.couponState, state);
        expect(coupon.stateLabel, label);
        expect(coupon.isAvailable, isAvail);
        expect(coupon.isNotStarted, isNotSt);
        expect(coupon.isUsed, isUsd);
        expect(coupon.isExpired, isExp);
        expect(coupon.isLimitReached, isLim);
        expect(coupon.stateColor, isNotNull);
      }
    });

    test('Q: Campos internos no existen en el modelo CustomerCoupon', () {
      // El modelo no expone campos administrativos internos
      final map = {
        'coupon_id': 'c-safe',
        'code': 'SAFE10',
        'name': 'Safe Coupon',
        'discount_type': 'percentage',
        'discount_value': 10,
        'coupon_state': 'available',
        'internal_notes': 'SECRETO ADMIN',
        'created_by': 'admin-uuid',
        'updated_by': 'admin-uuid',
        'assigned_by': 'admin-uuid',
      };

      final coupon = CustomerCoupon.fromRpc(map);
      expect(coupon.code, 'SAFE10');
      // No existe getter o propiedad para internal_notes o created_by
    });

    test('Parseo numérico robusto con tipos mixtos (null, num, String)', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-robust',
        'code': 'ROBUST',
        'name': 'Robust Types',
        'discount_type': 'fixed_amount',
        'discount_value': 100, // int
        'minimum_subtotal': '500.50', // string
        'maximum_discount': 250.0, // double
        'usage_limit': '50', // string int
        'client_uses': 2,
        'remaining_uses': '48',
        'coupon_state': 'available',
      });

      expect(coupon.discountValue, 100.0);
      expect(coupon.minimumSubtotal, 500.50);
      expect(coupon.maximumDiscount, 250.0);
      expect(coupon.usageLimit, 50);
      expect(coupon.clientUses, 2);
      expect(coupon.remainingUses, 48);
    });

    test('C: CouponService invoca exclusivamente rpc(\'get_my_coupons\')', () {
      final serviceSource = File(
        'lib/services/coupon_service.dart',
      ).readAsStringSync();

      expect(serviceSource, contains(".rpc('get_my_coupons')"));
      expect(serviceSource, isNot(contains('client_id')));
    });

    test(
      'D: NO SELECT directo a coupons ni tablas relacionadas de cupones',
      () {
        final serviceSource = File(
          'lib/services/coupon_service.dart',
        ).readAsStringSync();
        final screenSource = File(
          'lib/screens/profile/coupons_screen.dart',
        ).readAsStringSync();

        for (final table in [
          'coupons',
          'coupon_assignments',
          'coupon_products',
          'coupon_categories',
          'coupon_subcategories',
          'coupon_redemptions',
        ]) {
          expect(serviceSource, isNot(contains(".from('$table')")));
          expect(screenSource, isNot(contains(".from('$table')")));
        }
      },
    );

    test(
      'R: Botón Usar cupón usa CartService.applyCartCoupon sin cálculos locales',
      () {
        final screenSource = File(
          'lib/screens/profile/coupons_screen.dart',
        ).readAsStringSync();

        expect(
          screenSource,
          contains('CartService.applyCartCoupon(coupon.code)'),
        );
        // No debe realizar cálculos de descuento locales en la UI
        expect(screenSource, isNot(contains('discountValue / 100')));
        expect(screenSource, isNot(contains('subtotal - couponDiscount')));
      },
    );

    test('A: coupon_state null es FAIL-CLOSED (isAvailable == false)', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-null',
        'code': 'TEST_NULL',
        'name': 'Test Null State',
        'discount_type': 'percentage',
        'discount_value': 10,
        'coupon_state': null,
      });

      expect(coupon.couponState, 'unknown');
      expect(coupon.isAvailable, isFalse);
      expect(coupon.stateLabel, 'No disponible');
    });

    test('B: coupon_state ausente es FAIL-CLOSED (isAvailable == false)', () {
      final coupon = CustomerCoupon.fromRpc({
        'coupon_id': 'c-missing',
        'code': 'TEST_MISSING',
        'name': 'Test Missing State',
        'discount_type': 'percentage',
        'discount_value': 10,
      });

      expect(coupon.couponState, 'unknown');
      expect(coupon.isAvailable, isFalse);
      expect(coupon.stateLabel, 'No disponible');
    });

    test(
      'C: coupon_state vacio o whitespace es FAIL-CLOSED (isAvailable == false)',
      () {
        final couponEmpty = CustomerCoupon.fromRpc({
          'coupon_id': 'c-empty',
          'code': 'TEST_EMPTY',
          'name': 'Test Empty State',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': '',
        });
        final couponSpaces = CustomerCoupon.fromRpc({
          'coupon_id': 'c-spaces',
          'code': 'TEST_SPACES',
          'name': 'Test Spaces State',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': '   ',
        });

        expect(couponEmpty.isAvailable, isFalse);
        expect(couponEmpty.stateLabel, 'No disponible');
        expect(couponSpaces.isAvailable, isFalse);
        expect(couponSpaces.stateLabel, 'No disponible');
      },
    );

    test(
      'D: coupon_state con valor desconocido es FAIL-CLOSED (isAvailable == false)',
      () {
        final coupon = CustomerCoupon.fromRpc({
          'coupon_id': 'c-unk',
          'code': 'TEST_UNK',
          'name': 'Test Unknown State',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': 'unknown_arbitrary_value',
        });

        expect(coupon.couponState, 'unknown');
        expect(coupon.isAvailable, isFalse);
        expect(coupon.stateLabel, 'No disponible');
      },
    );

    test(
      'E: coupon_state = available es el UNICO que produce isAvailable == true',
      () {
        final coupon = CustomerCoupon.fromRpc({
          'coupon_id': 'c-avail',
          'code': 'TEST_AVAIL',
          'name': 'Test Available State',
          'discount_type': 'percentage',
          'discount_value': 10,
          'coupon_state': 'available',
        });

        expect(coupon.couponState, 'available');
        expect(coupon.isAvailable, isTrue);
        expect(coupon.stateLabel, 'Disponible');
      },
    );

    test(
      'J: hasActiveCart realiza consulta no intrusiva y NO crea carritos',
      () {
        final cartServiceSource = File(
          'lib/services/cart_service.dart',
        ).readAsStringSync();

        expect(
          cartServiceSource,
          contains('static Future<bool> hasActiveCart()'),
        );
        // Dentro de hasActiveCart no debe haber llamadas a .insert
        final methodStart = cartServiceSource.indexOf(
          'static Future<bool> hasActiveCart()',
        );
        final methodEnd = cartServiceSource.indexOf(
          'static Future<String> _requireActiveCartId()',
        );
        final methodBody = cartServiceSource.substring(methodStart, methodEnd);

        expect(methodBody, contains(".select('id')"));
        expect(methodBody, contains(".eq('status', 'active')"));
        expect(methodBody, contains(".maybeSingle()"));
        expect(methodBody, isNot(contains(".insert")));
      },
    );
  });
}
