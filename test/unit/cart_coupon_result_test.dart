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

    test('conserva reason cuando el backend rechaza el cupon', () {
      final result = CartCouponResult.fromRpc([
        {'valid': false, 'reason': 'expired'},
      ]);

      expect(result.valid, isFalse);
      expect(result.reason, 'expired');
      expect(result.message, 'expired');
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
