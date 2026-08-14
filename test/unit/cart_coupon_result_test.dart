import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/services/cart_service.dart';

void main() {
  group('CartCouponResult', () {
    test('interpreta una respuesta valida del backend', () {
      final result = CartCouponResult.fromRpc({
        'valid': true,
        'message': 'Descuento aplicado.',
        'discount_amount': 125,
      });

      expect(result.valid, isTrue);
      expect(result.reason, isNull);
      expect(result.message, 'Descuento aplicado.');
      expect(result.data['discount_amount'], 125);
    });

    test('extrae amounts.total y amounts.coupon_discount del backend', () {
      final result = CartCouponResult.fromRpc({
        'valid': true,
        'message': 'Cupón aplicado.',
        'amounts': {
          'items_subtotal': 2681.00,
          'product_discount': 0,
          'eligible_subtotal': 2681.00,
          'coupon_discount': 268.10,
          'tax': 0,
          'total': 2412.90,
          'currency': 'MXN',
        },
      });

      expect(result.valid, isTrue);
      expect(result.amounts, isNotNull);
      expect(result.amounts!.itemsSubtotal, 2681.00);
      expect(result.amounts!.couponDiscount, 268.10);
      expect(result.amounts!.total, 2412.90);
      expect(result.amounts!.currency, 'MXN');
    });

    test('conserva reason cuando el backend rechaza el cupon', () {
      final result = CartCouponResult.fromRpc([
        {'valid': false, 'reason': 'expired'},
      ]);

      expect(result.valid, isFalse);
      expect(result.reason, 'expired');
      expect(result.message, 'expired');
    });

    test('conserva not_combinable para limpiar cupon persistido stale', () {
      final result = CartCouponResult.fromRpc({
        'valid': false,
        'reason': 'not_combinable',
        'message': 'El cupón no es acumulable con promociones activas.',
      });

      expect(result.valid, isFalse);
      expect(result.reason, 'not_combinable');
      expect(
        result.message,
        'El cupón no es acumulable con promociones activas.',
      );
      expect(result.amounts, isNull);
    });

    test('rechaza respuestas que no cumplen el contrato', () {
      final result = CartCouponResult.fromRpc('respuesta inesperada');

      expect(result.valid, isFalse);
      expect(result.reason, isNull);
      expect(
        result.message,
        'El servidor devolvió una respuesta de cupón inválida.',
      );
    });
  });
}
