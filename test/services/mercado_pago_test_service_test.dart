import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/services/mercado_pago_test_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('MercadoPagoTestService.validateCheckoutUri', () {
    test('acepta url https de mercadopago', () {
      final uri = MercadoPagoTestService.validateCheckoutUri(
        'https://www.mercadopago.com.mx/checkout/v1/redirect',
      );

      expect(uri.host, 'www.mercadopago.com.mx');
    });

    test('rechaza respuesta sin checkout_url', () async {
      final service = MercadoPagoTestService(
        SupabaseClient('https://example.com', 'anon-key'),
        sessionGetter: () => _fakeSession(),
        invokePreference: (body) async => <String, dynamic>{},
        openCheckout: (_) async {},
      );

      expect(
        service.startTestPayment(
          cartId: 'test-cart-id',
          addressId: 'address-1',
          quotationId: 'quotation-1',
          rateId: 'rate-1',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No se recibió una URL válida'),
          ),
        ),
      );
    });

    test('rechaza url http', () {
      expect(
        () => MercadoPagoTestService.validateCheckoutUri(
          'http://www.mercadopago.com.mx/checkout/v1/redirect',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('HTTPS'),
          ),
        ),
      );
    });

    test('rechaza dominio desconocido', () {
      expect(
        () => MercadoPagoTestService.validateCheckoutUri(
          'https://evil-example.com/checkout',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Mercado Pago'),
          ),
        ),
      );
    });
  });

  group('MercadoPagoTestService.startTestPayment', () {
    test('rechaza usuario sin sesión', () async {
      final service = MercadoPagoTestService(
        SupabaseClient('https://example.com', 'anon-key'),
        sessionGetter: () => null,
        invokePreference: (_) async => <String, dynamic>{},
        openCheckout: (_) async {},
      );

      await expectLater(
        service.startTestPayment(cartId: 'test-cart-id'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Debes iniciar sesión'),
          ),
        ),
      );
    });

    test(
      'envía selección de envío sin identidad ni totales del cliente',
      () async {
        Map<String, dynamic>? sentBody;
        final service = MercadoPagoTestService(
          SupabaseClient('https://example.com', 'anon-key'),
          sessionGetter: _fakeSession,
          invokePreference: (body) async {
            sentBody = body;
            return <String, dynamic>{
              'checkout_url':
                  'https://www.mercadopago.com.mx/checkout/v1/redirect',
            };
          },
          openCheckout: (_) async {},
        );

        await service.startTestPayment(
          cartId: 'test-cart-id',
          addressId: 'address-1',
          quotationId: 'quotation-1',
          rateId: 'rate-1',
          notes: 'Entregar en recepción',
        );

        expect(sentBody, isNotNull);
        expect(sentBody!['cart_id'], 'test-cart-id');
        expect(sentBody!['address_id'], 'address-1');
        expect(sentBody!['skydropx_quotation_id'], 'quotation-1');
        expect(sentBody!['skydropx_rate_id'], 'rate-1');
        expect(sentBody!['notes'], 'Entregar en recepción');
        expect(sentBody!.containsKey('user_id'), isFalse);
        expect(sentBody!.containsKey('profile_id'), isFalse);
        expect(sentBody!.containsKey('client_id'), isFalse);
        expect(sentBody!.containsKey('payment_total'), isFalse);
        expect(sentBody!.containsKey('product_subtotal'), isFalse);
        expect(sentBody!.containsKey('customer_shipping_amount'), isFalse);
        expect(sentBody!.containsKey('unit_price'), isFalse);
      },
    );

    test('rechaza pago sin selección de envío', () async {
      var invoked = false;
      final service = MercadoPagoTestService(
        SupabaseClient('https://example.com', 'anon-key'),
        sessionGetter: _fakeSession,
        invokePreference: (_) async {
          invoked = true;
          return <String, dynamic>{
            'checkout_url':
                'https://www.mercadopago.com.mx/checkout/v1/redirect',
          };
        },
        openCheckout: (_) async {},
      );

      await expectLater(
        service.startTestPayment(cartId: 'test-cart-id'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('opción de envío válida'),
          ),
        ),
      );

      expect(invoked, isFalse);
    });

    test('previene doble apertura', () async {
      final completer = Completer<void>();
      final service = MercadoPagoTestService(
        SupabaseClient('https://example.com', 'anon-key'),
        sessionGetter: _fakeSession,
        invokePreference: (_) async => <String, dynamic>{
          'checkout_url': 'https://www.mercadopago.com.mx/checkout/v1/redirect',
        },
        openCheckout: (_) => completer.future,
      );

      final firstCall = service.startTestPayment(
        cartId: 'test-cart-id',
        addressId: 'address-1',
        quotationId: 'quotation-1',
        rateId: 'rate-1',
      );

      await expectLater(
        service.startTestPayment(
          cartId: 'test-cart-id',
          addressId: 'address-1',
          quotationId: 'quotation-1',
          rateId: 'rate-1',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('en curso'),
          ),
        ),
      );

      completer.complete();
      await firstCall;
    });

    test('propaga error de edge function', () async {
      final service = MercadoPagoTestService(
        SupabaseClient('https://example.com', 'anon-key'),
        sessionGetter: _fakeSession,
        invokePreference: (_) async =>
            throw Exception('Error de Edge Function'),
        openCheckout: (_) async {},
      );

      await expectLater(
        service.startTestPayment(
          cartId: 'test-cart-id',
          addressId: 'address-1',
          quotationId: 'quotation-1',
          rateId: 'rate-1',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Edge Function'),
          ),
        ),
      );
    });
  });
}

Session _fakeSession() {
  return Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: const User(
      id: 'user-1',
      appMetadata: <String, dynamic>{},
      userMetadata: <String, dynamic>{},
      aud: 'authenticated',
      createdAt: '2026-07-22T00:00:00.000Z',
    ),
  );
}
