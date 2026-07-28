import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/services/address_service.dart';

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

    test('deliveryLabel returns only the postal code when available', () {
      final addr = ClientAddress(
        id: '1',
        clientId: 'client-1',
        label: 'Casa',
        address: 'Calle 10 #123',
        city: 'Mérida',
        postalCode: '97144',
      );

      expect(addr.deliveryLabel, 'CP 97144');
    });

    test(
      'displayText returns full address if city/postalCode are null and address <= 40 chars',
      () {
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
      },
    );

    test(
      'displayText truncates address and adds elipsis if city/postalCode are null and address > 40 chars',
      () {
        final addr = ClientAddress(
          id: '1',
          clientId: 'client-123',
          label: 'Mi casa',
          address:
              'Calle 10 #123 por 45 y 47 Residencial Central Alameda del Prado',
          city: null,
          state: null,
          postalCode: null,
        );
        expect(addr.displayText, 'Calle 10 #123 por 45 y 47 Residencial Ce...');
      },
    );

    test('preserves all delivery details in the stored address', () {
      const details = ClientAddressDetails(
        streetAddress: 'Calle 45A',
        municipality: 'Umán',
        locality: 'Umán',
        neighborhood: 'Itzincab',
        interior: '546H',
        instructions: 'Casa de color azul',
        recipientName: 'Juan Pablo',
        recipientPhone: '9995266748',
      );

      final stored = details.toStoredAddress(
        state: 'Yucatán',
        postalCode: '97392',
      );
      final parsed = ClientAddressDetails.fromStoredAddress(
        stored,
        municipality: 'Umán',
      );

      expect(parsed.streetAddress, 'Calle 45A');
      expect(parsed.municipality, 'Umán');
      expect(parsed.locality, 'Umán');
      expect(parsed.neighborhood, 'Itzincab');
      expect(parsed.interior, '546H');
      expect(parsed.instructions, 'Casa de color azul');
      expect(parsed.recipientName, 'Juan Pablo');
      expect(parsed.recipientPhone, '9995266748');
    });

    test('recovers delivery details from the previous address format', () {
      final parsed = ClientAddressDetails.fromStoredAddress(
        'Calle 45A, Interior 546H, Itzincab, Umán, '
        'Indicaciones: Casa de color azul, Recibe: Juan Pablo, '
        'Teléfono: 9995266748',
        municipality: 'Umán',
      );

      expect(parsed.streetAddress, 'Calle 45A');
      expect(parsed.neighborhood, 'Itzincab');
      expect(parsed.interior, '546H');
      expect(parsed.instructions, 'Casa de color azul');
      expect(parsed.recipientName, 'Juan Pablo');
      expect(parsed.recipientPhone, '9995266748');
    });
  });
}
