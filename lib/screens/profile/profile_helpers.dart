import 'package:flutter/material.dart';

const kPrimary = Color(0xFF024C8B);
const kSecondary = Color(0xFF21AF97);
const kNavy = Color(0xFF024C8B);
const kGreen = Color(0xFF16A34A);
const kRed = Color(0xFFEF4444);
const kOrange = Color(0xFFF59E0B);

String formatCurrency(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final buf = StringBuffer();
  for (int i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
    buf.write(parts[0][i]);
  }
  return '\$$buf.${parts[1]} MXN';
}

class OrderPaymentBreakdown {
  final double products;
  final double includedTax;
  final double shipping;
  final double total;

  const OrderPaymentBreakdown({
    required this.products,
    required this.includedTax,
    required this.shipping,
    required this.total,
  });
}

OrderPaymentBreakdown buildIncludedVatOrderPaymentBreakdown({
  required double subtotal,
  required double total,
  double? storedTax,
  double? customerShippingAmount,
  double taxPct = 0.16,
}) {
  final safeTotal = _roundMoney(total);
  final safeShipping = _roundMoney(
    (customerShippingAmount ?? 0).clamp(0.0, double.infinity),
  );
  final fallbackProducts = (safeTotal - safeShipping).clamp(
    0.0,
    double.infinity,
  );
  final products = _roundMoney(
    subtotal > 0 ? subtotal : fallbackProducts.toDouble(),
  );
  final includedTax = storedTax != null && storedTax > 0
      ? _roundMoney(storedTax)
      : _roundMoney(products - (products / (1 + taxPct)));

  return OrderPaymentBreakdown(
    products: products,
    includedTax: includedTax,
    shipping: safeShipping,
    total: safeTotal,
  );
}

double _roundMoney(num value) => (value * 100).roundToDouble() / 100;

String getEffectiveStatus(Map<String, dynamic> q) {
  final status = q['status'] ?? '';
  if (status == 'sent' || status == 'draft') {
    final validUntilStr = q['valid_until'];
    if (validUntilStr != null) {
      final validDate = DateTime.tryParse(validUntilStr)?.toLocal();
      if (validDate != null && DateTime.now().isAfter(validDate)) {
        return 'expired';
      }
    }
  }
  return status;
}
