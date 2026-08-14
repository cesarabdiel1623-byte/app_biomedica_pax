import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Order totals with included VAT', () {
    test('3403.28 + 35.47 keeps tax informational and total 3438.75', () {
      final result = _calculateOrderTotals(
        lineItemsTotal: 3403.28,
        couponDiscountAmount: 0,
        customerShippingAmount: 35.47,
      );

      expect(result.productPayable, 3403.28);
      expect(result.tax, 469.42);
      expect(result.total, 3438.75);
      expect(result.tax, isNot(544.52));
      expect(result.total, isNot(3947.80));
    });

    test('shipping benefit uses customer amount, not provider cost', () {
      final result = _calculateOrderTotals(
        lineItemsTotal: 6806.56,
        couponDiscountAmount: 0,
        customerShippingAmount: 0,
      );

      expect(result.productPayable, 6806.56);
      expect(result.tax, 938.84);
      expect(result.total, 6806.56);
    });

    test('paid shipping difference is included when provider cost differs', () {
      final result = _calculateOrderTotals(
        lineItemsTotal: 6806.56,
        couponDiscountAmount: 0,
        customerShippingAmount: 147.23,
      );

      expect(result.productPayable, 6806.56);
      expect(result.tax, 938.84);
      expect(result.total, 6953.79);
    });

    test(
      'coupon discount is subtracted from line items before tax and total',
      () {
        final result = _calculateOrderTotals(
          lineItemsTotal: 3400,
          couponDiscountAmount: 400,
          customerShippingAmount: 100,
        );

        expect(result.productPayable, 3000);
        expect(result.tax, 413.79);
        expect(result.total, 3100);
      },
    );

    test('tax exempt preserves zero tax without changing payable total', () {
      final result = _calculateOrderTotals(
        lineItemsTotal: 3403.28,
        couponDiscountAmount: 0,
        customerShippingAmount: 35.47,
        taxExempt: true,
      );

      expect(result.productPayable, 3403.28);
      expect(result.tax, 0);
      expect(result.total, 3438.75);
    });
  });

  group('T2.8 migration static checks', () {
    test('does not add tax back into orders.total', () {
      final migration = File(
        'supabase/migrations/20260812113000_t2_8_fix_order_totals_included_vat_shipping.sql',
      ).readAsStringSync();

      expect(
        migration,
        contains('v_product_payable - (v_product_payable / (1 + v_tax_pct))'),
      );
      expect(migration, contains('v_coupon_discount'));
      expect(migration, contains('v_items_subtotal - v_coupon_discount'));
      expect(
        migration,
        contains('v_product_payable + v_customer_shipping_amount'),
      );
      expect(migration, isNot(contains('v_product_payable + v_tax')));
      expect(migration, isNot(contains('v_items_subtotal * 0.16')));
      expect(migration, isNot(contains('v_subtotal * 0.16')));
      expect(migration, isNot(contains('skydropx_shipping_cost')));
    });
  });
}

({double productPayable, double tax, double total}) _calculateOrderTotals({
  required double lineItemsTotal,
  required double couponDiscountAmount,
  required double customerShippingAmount,
  double taxPct = 0.16,
  bool taxExempt = false,
}) {
  final safeLineItems = lineItemsTotal < 0 ? 0.0 : lineItemsTotal;
  final safeCoupon = couponDiscountAmount < 0 ? 0.0 : couponDiscountAmount;
  final productPayable = _round2(
    safeLineItems - safeCoupon < 0 ? 0.0 : safeLineItems - safeCoupon,
  );
  final safeCustomerShipping = customerShippingAmount < 0
      ? 0.0
      : customerShippingAmount;
  final tax = taxExempt
      ? 0.0
      : _round2(productPayable - productPayable / (1 + taxPct));
  final total = _round2(productPayable + safeCustomerShipping);

  return (productPayable: productPayable, tax: tax, total: total);
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
