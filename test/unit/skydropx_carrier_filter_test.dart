import 'package:flutter_test/flutter_test.dart';

// Normalizador y validador de transportistas autorizados SkyDropX
// (Espejo de la lógica en las Edge Functions skydropx-mobile-quote y process-paid-order-fulfillment)
final _allowedCarrierPatterns = [
  RegExp(r'(?:^|[^a-z0-9])fedex(?:[^a-z0-9]|$)', caseSensitive: false),
  RegExp(r'(?:^|[^a-z0-9])dhl(?:[^a-z0-9]|$)', caseSensitive: false),
  RegExp(r'(?:^|[^a-z0-9])estafeta(?:[^a-z0-9]|$)', caseSensitive: false),
  RegExp(
    r'(?:^|[^a-z0-9])paquetexpress(?:[^a-z0-9]|$)|(?:^|[^a-z0-9])paquete\s*express(?:[^a-z0-9]|$)',
    caseSensitive: false,
  ),
];

String _removeDiacritics(String str) {
  const withDia =
      'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐIÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
  const withoutDia =
      'AAAAAAaaaaaaOOOOOOOoooooooEEEEeeeedCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
  var result = str;
  for (int i = 0; i < withDia.length; i++) {
    result = result.replaceAll(withDia[i], withoutDia[i]);
  }
  return result;
}

bool isAllowedCarrier(String? carrierName) {
  if (carrierName == null || carrierName.trim().isEmpty) return false;
  final clean = _removeDiacritics(carrierName).trim().toLowerCase();

  return _allowedCarrierPatterns.any((regex) => regex.hasMatch(clean));
}

void main() {
  group('SkyDropX Carrier Whitelist Tests', () {
    test('DHL Express -> permitido', () {
      expect(isAllowedCarrier('DHL'), isTrue);
      expect(isAllowedCarrier('DHL Express'), isTrue);
      expect(isAllowedCarrier('dhl_express'), isTrue);
      expect(isAllowedCarrier('DHL Parcel'), isTrue);
    });

    test('FedEx -> permitido', () {
      expect(isAllowedCarrier('FedEx'), isTrue);
      expect(isAllowedCarrier('FedEx · Standard Overnight'), isTrue);
      expect(isAllowedCarrier('fedex_express'), isTrue);
      expect(isAllowedCarrier('FedEx Express Saver'), isTrue);
    });

    test('Estafeta -> permitido', () {
      expect(isAllowedCarrier('Estafeta'), isTrue);
      expect(isAllowedCarrier('estafeta'), isTrue);
      expect(isAllowedCarrier('Estáfeta'), isTrue);
      expect(isAllowedCarrier('Estafeta Terrestre'), isTrue);
    });

    test('Paquetexpress -> permitido', () {
      expect(isAllowedCarrier('Paquetexpress'), isTrue);
      expect(isAllowedCarrier('paquetexpress'), isTrue);
      expect(isAllowedCarrier('Paquete Express'), isTrue);
      expect(isAllowedCarrier('PAQUETE EXPRESS NACIONAL'), isTrue);
    });

    test('UPS -> excluido', () {
      expect(isAllowedCarrier('UPS'), isFalse);
      expect(isAllowedCarrier('ups standard'), isFalse);
      expect(isAllowedCarrier('UPS Ground'), isFalse);
    });

    test('Otros carriers no autorizados -> excluidos', () {
      expect(isAllowedCarrier('ampm'), isFalse);
      expect(isAllowedCarrier('ampm · Standard'), isFalse);
      expect(isAllowedCarrier('Redpack'), isFalse);
      expect(isAllowedCarrier('Sendex'), isFalse);
      expect(isAllowedCarrier('Carssa'), isFalse);
      expect(isAllowedCarrier('Noventa9'), isFalse);
      expect(isAllowedCarrier('99minutos'), isFalse);
      expect(isAllowedCarrier('Uber'), isFalse);
      expect(isAllowedCarrier(''), isFalse);
      expect(isAllowedCarrier(null), isFalse);
    });
  });
}
