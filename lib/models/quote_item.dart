import '../models/product.dart';

class QuoteItem {
  final String productId;
  int quantity;
  Product? product;

  QuoteItem({required this.productId, required this.quantity, this.product});

  Map<String, dynamic> toJson() {
    return {'product_id': productId, 'quantity': quantity};
  }

  factory QuoteItem.fromJson(Map<String, dynamic> json) {
    return QuoteItem(
      productId: json['product_id'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 1,
    );
  }
}
