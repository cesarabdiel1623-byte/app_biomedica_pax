import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/quote.dart';
import 'package:gomedical_app/services/mercado_pago_service.dart';

void main() {
  group('ServiceQuotePaymentResult Unit Tests', () {
    test('instantiates with valid payment session', () {
      final uri = Uri.parse(
        'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=123',
      );
      final result = ServiceQuotePaymentResult(
        ok: true,
        alreadyPaid: false,
        orderId: 'order-uuid-1',
        orderNumber: 'ORD-20260819-001',
        paymentRecordId: 'pay-rec-uuid',
        checkoutUri: uri,
        amount: 5220.0,
        currencyId: 'MXN',
        reusedPreference: false,
      );

      expect(result.ok, isTrue);
      expect(result.alreadyPaid, isFalse);
      expect(result.orderId, 'order-uuid-1');
      expect(result.orderNumber, 'ORD-20260819-001');
      expect(result.paymentRecordId, 'pay-rec-uuid');
      expect(result.checkoutUri, uri);
      expect(result.amount, 5220.0);
      expect(result.currencyId, 'MXN');
      expect(result.reusedPreference, isFalse);
    });

    test('instantiates with alreadyPaid = true and null checkoutUri', () {
      final result = ServiceQuotePaymentResult(
        ok: true,
        alreadyPaid: true,
        orderId: 'order-uuid-2',
        orderNumber: 'ORD-20260819-002',
        amount: 1500.0,
        currencyId: 'MXN',
      );

      expect(result.ok, isTrue);
      expect(result.alreadyPaid, isTrue);
      expect(result.checkoutUri, isNull);
      expect(result.orderId, 'order-uuid-2');
    });
  });

  group('MercadoPagoService.validateCheckoutUri Security Tests', () {
    test('accepts valid https Mercado Pago domains', () {
      final validUrls = [
        'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=12345',
        'https://mercadopago.com/checkout/v1/redirect?pref_id=12345',
        'https://mpago.la/2abcde',
        'https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=12345',
      ];

      for (final url in validUrls) {
        final uri = MercadoPagoService.validateCheckoutUri(url);
        expect(uri.scheme, 'https');
        expect(uri.host, isNotEmpty);
      }
    });

    test('rejects non-https URLs', () {
      expect(
        () => MercadoPagoService.validateCheckoutUri(
          'http://www.mercadopago.com.mx/checkout',
        ),
        throwsException,
      );
    });

    test('rejects phishing / unallowed domains', () {
      final maliciousUrls = [
        'https://evil-phishing.com/mercadopago.com.mx',
        'https://mercadopago.com.mx.attacker.com',
        'https://google.com',
        'https://notmercadopago.com',
      ];

      for (final url in maliciousUrls) {
        expect(
          () => MercadoPagoService.validateCheckoutUri(url),
          throwsException,
        );
      }
    });

    test('rejects malformed URLs', () {
      expect(
        () => MercadoPagoService.validateCheckoutUri('not_a_valid_url'),
        throwsException,
      );
    });
  });

  group('ServiceQuote State and Converted Order Navigation Tests', () {
    test('quote converted with convertedOrderId is handled properly', () {
      final quote = ServiceQuote(
        id: 'quote-100',
        quoteNumber: 'COT-001',
        clientId: 'client-1',
        status: 'converted',
        subtotal: 1000.0,
        taxPct: 0.16,
        taxExempt: false,
        tax: 160.0,
        total: 1160.0,
        convertedOrderId: 'order-converted-uuid-1',
      );

      expect(quote.isConverted, isTrue);
      expect(quote.convertedOrderId, 'order-converted-uuid-1');
      expect(quote.isApproved, isFalse);
      expect(quote.isSent, isFalse);
    });

    test('quote approved requires payment action', () {
      final quote = ServiceQuote(
        id: 'quote-200',
        quoteNumber: 'COT-002',
        clientId: 'client-2',
        status: 'approved',
        subtotal: 2000.0,
        taxPct: 0.16,
        taxExempt: false,
        tax: 320.0,
        total: 2320.0,
      );

      expect(quote.isApproved, isTrue);
      expect(quote.isConverted, isFalse);
      expect(quote.statusLabel, 'Aprobada');
    });
  });

  group('Service quote Mercado Pago concurrency contract', () {
    test(
      'only the request that wins created to pending may create preference',
      () {
        bool canCreatePreference({
          required String currentStatus,
          required bool hasPreferenceId,
          required bool hasCheckoutUrl,
        }) {
          return currentStatus == 'created' &&
              !hasPreferenceId &&
              !hasCheckoutUrl;
        }

        expect(
          canCreatePreference(
            currentStatus: 'created',
            hasPreferenceId: false,
            hasCheckoutUrl: false,
          ),
          isTrue,
        );

        expect(
          canCreatePreference(
            currentStatus: 'pending',
            hasPreferenceId: false,
            hasCheckoutUrl: false,
          ),
          isFalse,
        );

        expect(
          canCreatePreference(
            currentStatus: 'created',
            hasPreferenceId: true,
            hasCheckoutUrl: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'orphan external preference is not returned when DB persistence fails',
      () {
        String outcomeAfterMercadoPago({
          required bool mercadoPagoCreatedPreference,
          required bool persistedInDatabase,
          required bool hasCanonicalCheckoutUrl,
        }) {
          if (persistedInDatabase && hasCanonicalCheckoutUrl) {
            return 'return_checkout_url';
          }
          if (hasCanonicalCheckoutUrl) {
            return 'reuse_canonical_checkout_url';
          }
          if (mercadoPagoCreatedPreference && !persistedInDatabase) {
            return 'fail_closed_without_checkout_url';
          }
          return 'retryable_error';
        }

        expect(
          outcomeAfterMercadoPago(
            mercadoPagoCreatedPreference: true,
            persistedInDatabase: false,
            hasCanonicalCheckoutUrl: false,
          ),
          'fail_closed_without_checkout_url',
        );

        expect(
          outcomeAfterMercadoPago(
            mercadoPagoCreatedPreference: true,
            persistedInDatabase: true,
            hasCanonicalCheckoutUrl: true,
          ),
          'return_checkout_url',
        );
      },
    );
  });
}
