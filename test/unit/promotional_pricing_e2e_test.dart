import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/product.dart';
import 'package:gomedical_app/utils/price_formatter.dart';

void main() {
  group('REFA1114 promotional pricing regression', () {
    final product = Product.fromJson({
      'id': '8daf1dc5-8ee0-4cdb-9952-3a12c06af412',
      'sku': 'REFA1114',
      'name': 'Banco de baterías para ventilador Vela',
      'category': 'refaccion',
      'application': 'general',
      'unit_price_mxn': 14025.61,
      'cost_price_mxn': 0,
      'currency': 'MXN',
      'unit': 'pieza',
      'is_active': true,
      'requires_serial': false,
      'track_inventory': true,
      'created_at': '2026-08-12T00:00:00Z',
      'active_product_promotions': [
        {
          'product_id': '8daf1dc5-8ee0-4cdb-9952-3a12c06af412',
          'original_price_mxn': 14025.61,
          'promotional_price_mxn': 12342.5368,
          'discount_type': 'percentage',
          'discount_value': 12,
          'computed_status': 'activa',
        },
      ],
    });

    test('catalog, detail and cart model share the active promotion', () {
      expect(roundFinancialAmount(product.unitPriceMxn), 12343.00);
      expect(product.formattedPrice, '\$12,343 MXN');
      expect(product.formattedOldPrice, '\$14,026 MXN');
      expect(product.discountPercent, 12);
      expect(product.activePromotion?.computedStatus, 'activa');
    });

    test('commercial amount becomes the effective payable amount', () {
      expect(roundCommercialAmount(14025.61), 14026.00);
      expect(roundCommercialAmount(12342.5368), 12343.00);
      expect(formatCommercialPrice(14025.61), '\$14,026 MXN');
      expect(formatCommercialPrice(12342.5368), '\$12,343 MXN');
      expect(formatCommercialPrice(3403.28), '\$3,403 MXN');
      expect(formatFinancialPrice(12342.5368), '\$12,342.54 MXN');
    });

    test('free and premium shipping use effective subtotal', () {
      const cheapestRate = 35.47;
      const premiumRate = 157.32;
      final subtotal = roundFinancialAmount(product.unitPriceMxn);

      expect(subtotal >= 5000, isTrue);
      expect(roundFinancialAmount(cheapestRate - cheapestRate), 0);
      expect(roundFinancialAmount(subtotal), 12343.00);
      expect(roundFinancialAmount(premiumRate - cheapestRate), 121.85);
      expect(
        roundFinancialAmount(subtotal + premiumRate - cheapestRate),
        12464.85,
      );
    });

    test('coupon discount is applied after the effective commercial price', () {
      final couponDiscount = roundFinancialAmount(product.unitPriceMxn * 0.10);
      final total = roundFinancialAmount(product.unitPriceMxn - couponDiscount);

      expect(couponDiscount, 1234.30);
      expect(total, 11108.70);
    });
  });

  group('Authoritative backend pricing contracts', () {
    test('SkyDropX quote reads commercial rounded promotional price', () {
      final source = File(
        'supabase/functions/skydropx-mobile-quote/index.ts',
      ).readAsStringSync();

      expect(
        source,
        contains('active_product_promotions(promotional_price_mxn'),
      );
      expect(source, contains('roundCommercialAmount(promotionalPrice)'));
      expect(source, contains('roundFinancialAmount(payableUnitPrice * qty)'));
      expect(source, isNot(contains('catalogDisplayPrice')));
      expect(source, isNot(contains('roundFinancialAmount(promotionalPrice)')));
    });

    test(
      'prepare_mp_order stores commercial effective price and preserves T2.8',
      () {
        final migration = File(
          'supabase/migrations/20260812170000_t2_9_unify_commercial_checkout_price.sql',
        ).readAsStringSync();

        expect(migration, contains('public.active_product_promotions'));
        expect(migration, contains('promotional_price_mxn'));
        expect(migration, contains('v_commercial_unit_price := ROUND'));
        expect(migration, contains('v_coupon_discount_amount'));
        expect(migration, contains('v_coupon_free_shipping'));
        expect(
          migration,
          contains('ROUND(GREATEST(0, app.promotional_price_mxn), 0)'),
        );
        expect(migration, contains('t2_9_commercial_price_0dp'));
        expect(
          migration,
          contains('v_payable_product_amount + v_customer_shipping_amount'),
        );
        expect(
          migration,
          contains(
            'v_payable_product_amount - (v_payable_product_amount / 1.16)',
          ),
        );
        expect(migration, isNot(contains('v_financial_unit_price')));
        expect(migration, isNot(contains('v_payable_product_amount + v_tax')));
      },
    );

    test(
      'Checkout keeps local commercial subtotal if backend quote regresses',
      () {
        final source = File(
          'lib/screens/home/widgets/checkout_sheet.dart',
        ).readAsStringSync();

        expect(source, contains('pricing_mismatch'));
        expect(source, contains('backend_product_subtotal'));
        expect(source, contains('return localSubtotal'));
        expect(source, contains('_shippingQuoteResult?.productSubtotal'));
      },
    );

    test(
      'stale coupons are cleaned before checkout without weakening backend',
      () {
        final cartTab = File(
          'lib/screens/home/tabs/cart_tab.dart',
        ).readAsStringSync();
        final checkout = File(
          'lib/screens/home/widgets/checkout_sheet.dart',
        ).readAsStringSync();
        final migration = File(
          'supabase/migrations/20260812170000_t2_9_unify_commercial_checkout_price.sql',
        ).readAsStringSync();

        expect(cartTab, contains('clearInvalidPersistedCouponIfAny'));
        expect(cartTab, contains('_syncPersistedCouponBeforeCheckout'));
        expect(checkout, contains('clearInvalidPersistedCouponIfAny'));
        expect(
          migration,
          contains("RAISE EXCEPTION 'Applied coupon is no longer valid'"),
        );
      },
    );

    test('Mercado Pago receives only the server payment_total', () {
      final source = File(
        'supabase/functions/create-mp-test-preference/index.ts',
      ).readAsStringSync();

      expect(
        source,
        contains('const paymentTotal = getNumber(orderData, "payment_total")'),
      );
      expect(source, contains('unit_price: Number(paymentTotal.toFixed(2))'));
    });
  });
}
