import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/payment_test_result.dart';
import 'package:gomedical_app/services/payment_deep_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaymentDeepLinkService.parseResult', () {
    test('acepta success válido', () {
      final result = PaymentDeepLinkService.parseResult(
        Uri.parse('gomedical://payment/success'),
      );

      expect(result, PaymentTestResult.success);
    });

    test('acepta pending válido', () {
      final result = PaymentDeepLinkService.parseResult(
        Uri.parse('gomedical://payment/pending'),
      );

      expect(result, PaymentTestResult.pending);
    });

    test('acepta failure válido', () {
      final result = PaymentDeepLinkService.parseResult(
        Uri.parse('gomedical://payment/failure'),
      );

      expect(result, PaymentTestResult.failure);
    });

    test('rechaza scheme inválido', () {
      final result = PaymentDeepLinkService.parseResult(
        Uri.parse('otroapp://payment/success'),
      );

      expect(result, isNull);
    });

    test('rechaza host inválido', () {
      final result = PaymentDeepLinkService.parseResult(
        Uri.parse('gomedical://otrohost/success'),
      );

      expect(result, isNull);
    });

    test('rechaza path inválido', () {
      final result = PaymentDeepLinkService.parseResult(
        Uri.parse('gomedical://payment/desconocido'),
      );

      expect(result, isNull);
    });

    test('rechaza https normal', () {
      final result = PaymentDeepLinkService.parseResult(
        Uri.parse('https://payment/success'),
      );

      expect(result, isNull);
    });
  });

  group('PaymentDeepLinkService init', () {
    test('procesa cold start válido una sola vez', () async {
      final controller = StreamController<Uri>.broadcast();
      final handled = <PaymentTestResult>[];
      final service = PaymentDeepLinkService(
        initialLinkLoader: () async => Uri.parse('gomedical://payment/success'),
        linkStreamFactory: () => controller.stream,
      );

      await service.init(onResult: handled.add);
      await controller.close();
      service.dispose();

      expect(handled, [PaymentTestResult.success]);
    });

    test('ignora enlaces duplicados', () async {
      final controller = StreamController<Uri>.broadcast();
      final handled = <PaymentTestResult>[];
      final service = PaymentDeepLinkService(
        initialLinkLoader: () async => null,
        linkStreamFactory: () => controller.stream,
      );

      await service.init(onResult: handled.add);
      controller.add(Uri.parse('gomedical://payment/failure'));
      controller.add(Uri.parse('gomedical://payment/failure'));
      await Future<void>.delayed(Duration.zero);

      expect(handled, [PaymentTestResult.failure]);

      await controller.close();
      service.dispose();
    });

    test('procesa retornos con payment_id diferentes', () async {
      final controller = StreamController<Uri>.broadcast();
      final handled = <PaymentTestResult>[];
      final service = PaymentDeepLinkService(
        initialLinkLoader: () async => null,
        linkStreamFactory: () => controller.stream,
      );

      await service.init(onResult: handled.add);
      controller.add(
        Uri.parse('gomedical://payment/success?payment_id=123&status=approved'),
      );
      controller.add(
        Uri.parse('gomedical://payment/success?payment_id=456&status=approved'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(handled, [PaymentTestResult.success, PaymentTestResult.success]);

      await controller.close();
      service.dispose();
    });

    test('ignora enlaces inválidos del stream', () async {
      final controller = StreamController<Uri>.broadcast();
      final handled = <PaymentTestResult>[];
      final service = PaymentDeepLinkService(
        initialLinkLoader: () async => null,
        linkStreamFactory: () => controller.stream,
      );

      await service.init(onResult: handled.add);
      controller.add(Uri.parse('gomedical://payment/desconocido'));
      controller.add(Uri.parse('otroapp://payment/success'));
      await Future<void>.delayed(Duration.zero);

      expect(handled, isEmpty);

      await controller.close();
      service.dispose();
    });
  });
}
