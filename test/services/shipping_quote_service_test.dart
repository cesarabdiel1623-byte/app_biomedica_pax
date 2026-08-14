import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/services/shipping_quote_service.dart';

void main() {
  group('ShippingQuoteResult.fromJson', () {
    test(
      'conserva campos de cada rate sin mezclar carrier, servicio, total ni dias',
      () {
        final result = ShippingQuoteResult.fromJson({
          'ok': true,
          'shippable': true,
          'product_subtotal': 3403.28,
          'free_shipping_threshold': 5000,
          'free_shipping_unlocked': false,
          'cheapest_valid_rate_total': 35.47,
          'quotation_id': 'quotation-1',
          'rates': [
            {
              'rate_id': 'ampm-standard',
              'carrier': 'AMPM',
              'service': 'Standard',
              'days': 2,
              'actual_shipping_cost': 35.47,
              'customer_shipping_amount': 35.47,
              'shipping_discount_amount': 0,
              'label': '+\$35.47',
            },
            {
              'rate_id': 'fedex-overnight',
              'carrier': 'FedEx',
              'service': 'Standard Overnight',
              'days': 1,
              'actual_shipping_cost': 114.88,
              'customer_shipping_amount': 114.88,
              'shipping_discount_amount': 0,
              'label': '+\$114.88',
            },
            {
              'rate_id': 'dhl-express',
              'carrier': 'DHL',
              'service': 'Express',
              'days': 8,
              'actual_shipping_cost': 340.41,
              'customer_shipping_amount': 340.41,
              'shipping_discount_amount': 0,
              'label': '+\$340.41',
            },
          ],
        });

        expect(result.quotationId, 'quotation-1');
        expect(result.rates, hasLength(3));

        expect(result.rates[0].rateId, 'ampm-standard');
        expect(result.rates[0].carrier, 'AMPM');
        expect(result.rates[0].service, 'Standard');
        expect(result.rates[0].days, 2);
        expect(result.rates[0].actualShippingCost, 35.47);
        expect(result.rates[0].customerShippingAmount, 35.47);

        expect(result.rates[1].rateId, 'fedex-overnight');
        expect(result.rates[1].carrier, 'FedEx');
        expect(result.rates[1].service, 'Standard Overnight');
        expect(result.rates[1].days, 1);
        expect(result.rates[1].actualShippingCost, 114.88);
        expect(result.rates[1].customerShippingAmount, 114.88);

        expect(result.rates[2].rateId, 'dhl-express');
        expect(result.rates[2].carrier, 'DHL');
        expect(result.rates[2].service, 'Express');
        expect(result.rates[2].days, 8);
        expect(result.rates[2].actualShippingCost, 340.41);
        expect(result.rates[2].customerShippingAmount, 340.41);
      },
    );

    test(
      'representa beneficio de envio gratis sin confiar en totales de Flutter',
      () {
        final result = ShippingQuoteResult.fromJson({
          'ok': true,
          'shippable': true,
          'product_subtotal': 6806.55,
          'free_shipping_threshold': 5000,
          'free_shipping_unlocked': true,
          'cheapest_valid_rate_total': 35.47,
          'quotation_id': 'quotation-2',
          'rates': [
            {
              'rate_id': 'cheapest',
              'carrier': 'AMPM',
              'service': 'Standard',
              'days': 2,
              'actual_shipping_cost': 35.47,
              'customer_shipping_amount': 0,
              'shipping_discount_amount': 35.47,
              'label': 'GRATIS',
            },
            {
              'rate_id': 'faster',
              'carrier': 'Estafeta',
              'service': 'Servicio Express',
              'days': 1,
              'actual_shipping_cost': 182.70,
              'customer_shipping_amount': 147.23,
              'shipping_discount_amount': 35.47,
              'label': '+\$147.23',
            },
          ],
        });

        expect(result.freeShippingUnlocked, isTrue);
        expect(result.rates[0].customerShippingAmount, 0);
        expect(result.rates[0].label, 'GRATIS');
        expect(result.rates[1].customerShippingAmount, 147.23);
        expect(result.rates[1].shippingDiscountAmount, 35.47);
      },
    );
  });
}
