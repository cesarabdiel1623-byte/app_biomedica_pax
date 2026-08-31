import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/utils/notification_presentation.dart';

void main() {
  group('notificationPresentation', () {
    test('identifies a service quote status notification', () {
      final result = notificationPresentation({
        'title': 'Actualización de cotización',
        'body': 'Tu cotización QTE-20260828-26B7C0C1 cambió a estado: Enviada',
        'resource_type': 'service_ticket',
        'resource_id': '11111111-1111-4111-8111-111111111111',
      });

      expect(result.isServiceNotification, isTrue);
      expect(result.title, 'Actualización de tu servicio');
      expect(
        result.body,
        'La propuesta de tu servicio cambió a estado: Enviada',
      );
    });

    test('identifies a service quote message notification', () {
      final result = notificationPresentation({
        'title': 'Nuevo mensaje de cotización',
        'body': 'Cotización QTE-20260828-26B7C0C1: Ya está disponible',
        'metadata': {
          'resource_type': 'service_ticket',
          'resource_id': '11111111-1111-4111-8111-111111111111',
        },
      });

      expect(result.title, 'Nuevo mensaje sobre tu servicio');
      expect(
        result.body,
        'Mensaje sobre la propuesta de tu servicio: Ya está disponible',
      );
    });

    test('leaves a commercial quote unchanged', () {
      const title = 'Actualización de cotización';
      const body = 'Tu cotización QTE-20260828-ABC cambió a estado: Enviada';
      final result = notificationPresentation({
        'title': title,
        'body': body,
        'resource_type': 'quote',
      });

      expect(result.isServiceNotification, isFalse);
      expect(result.title, title);
      expect(result.body, body);
    });

    test('recognizes the explicit service ticket id for legacy payloads', () {
      final result = notificationPresentation({
        'title': 'Actualización de cotización',
        'body': 'Tu cotización cambió a estado: Aprobada',
        'payload': {
          'service_ticket_id': '11111111-1111-4111-8111-111111111111',
        },
      });

      expect(result.isServiceNotification, isTrue);
      expect(result.title, 'Actualización de tu servicio');
    });
  });
}
