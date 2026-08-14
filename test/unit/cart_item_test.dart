import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/product.dart';
import 'package:gomedical_app/services/cart_service.dart';

void main() {
  test('CartItem subtotal uses the effective commercial payable price', () {
    final product = Product(
      id: 'product-1',
      sku: 'REFA1114',
      name: 'Banco de baterias para ventilador Vela',
      category: 'refaccion',
      application: 'general',
      unitPriceMxn: 12343.00,
      costPriceMxn: 9000,
      currency: 'MXN',
      unit: 'pieza',
      isActive: true,
      requiresSerial: false,
      trackInventory: true,
      createdAt: DateTime.parse('2026-08-12T00:00:00Z'),
    );

    final item = CartItem(
      id: 'cart-item-1',
      cartId: 'cart-1',
      productId: product.id,
      quantity: 2,
      product: product,
    );

    expect(item.subtotal, 24686.00);
  });
}
