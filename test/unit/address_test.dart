import 'package:flutter_test/flutter_test.dart';
import 'package:app_prueba/services/address_service.dart';

void main() {
  group('ClientAddress Unit Tests', () {
    test('displayText returns "city, CP postalCode" when both are present', () {
      final addr = ClientAddress(
        id: '1',
        clientId: 'client-123',
        label: 'Mi casa',
        address: 'Calle 10 x 20 y 30',
        city: 'Mérida',
        state: 'Yucatán',
        postalCode: '97144',
      );
      expect(addr.displayText, 'Mérida, CP 97144');
    });

    test('displayText returns city when only city is present', () {
      final addr = ClientAddress(
        id: '1',
        clientId: 'client-123',
        label: 'Mi casa',
        address: 'Calle 10 x 20 y 30',
        city: 'Mérida',
        state: 'Yucatán',
        postalCode: null,
      );
      expect(addr.displayText, 'Mérida');
    });

    test('displayText returns full address if city/postalCode are null and address <= 40 chars', () {
      final addr = ClientAddress(
        id: '1',
        clientId: 'client-123',
        label: 'Mi casa',
        address: 'Calle 10 #123 Residencial Central',
        city: null,
        state: null,
        postalCode: null,
      );
      expect(addr.displayText, 'Calle 10 #123 Residencial Central');
    });

    test('displayText truncates address and adds elipsis if city/postalCode are null and address > 40 chars', () {
      final addr = ClientAddress(
        id: '1',
        clientId: 'client-123',
        label: 'Mi casa',
        address: 'Calle 10 #123 por 45 y 47 Residencial Central Alameda del Prado',
        city: null,
        state: null,
        postalCode: null,
      );
      expect(addr.displayText, 'Calle 10 #123 por 45 y 47 Residencial Ce...');
    });
  });
}
