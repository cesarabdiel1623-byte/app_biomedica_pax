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
        service.startTestPayment(),
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
        service.startTestPayment(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Debes iniciar sesión'),
          ),
        ),
      );
    });

    test('envía body vacío', () async {
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

      await service.startTestPayment();

      expect(sentBody, isNotNull);
      expect(sentBody, isEmpty);
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

      final firstCall = service.startTestPayment();

      await expectLater(
        service.startTestPayment(),
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
        service.startTestPayment(),
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
