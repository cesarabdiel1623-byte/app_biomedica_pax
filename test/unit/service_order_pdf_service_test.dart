import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/services/service_order_pdf_service.dart';

void main() {
  group('T6.3D service order PDF', () {
    const validPayload = {
      'ok': true,
      'document_type': 'preliminary',
      'ticket_number': 'TCK-20260817-TEST',
      'path': 'orders/test/orden_servicio_preliminar.pdf',
      'expires_in': 3600,
      'signed_url':
          'https://example.supabase.co/storage/v1/object/sign/service-reports/orders/test/orden_servicio_preliminar.pdf?token=temporary',
    };

    test('parse respuesta HTTP 200 válida', () async {
      final service = ServiceOrderPdfService(
        invoke: (_) async =>
            const ServiceOrderPdfRawResponse(status: 200, data: validPayload),
      );

      final result = await service.generate(ticketId: 'ticket-id');

      expect(result.ok, isTrue);
      expect(result.ticketNumber, 'TCK-20260817-TEST');
      expect(result.path, 'orders/test/orden_servicio_preliminar.pdf');
      expect(result.expiresIn, 3600);
    });

    test('document_type preliminary se conserva', () {
      final result = ServiceOrderPdfResult.fromJson(validPayload);

      expect(result.documentType, 'preliminary');
    });

    test('signed_url válida se requiere cuando ok=true', () {
      final result = ServiceOrderPdfResult.fromJson(validPayload);

      expect(result.signedUrl, startsWith('https://'));
      expect(result.signedUrl, contains('orden_servicio_preliminar.pdf'));
    });

    test('respuesta sin signed_url falla controladamente', () {
      expect(
        () =>
            ServiceOrderPdfResult.fromJson({...validPayload, 'signed_url': ''}),
        throwsA(isA<ServiceOrderPdfException>()),
      );
    });

    test('401 se maneja como sesión expirada', () async {
      final service = ServiceOrderPdfService(
        invoke: (_) async =>
            const ServiceOrderPdfRawResponse(status: 401, data: {}),
      );

      expect(
        () => service.generate(ticketId: 'ticket-id'),
        throwsA(
          isA<ServiceOrderPdfException>().having(
            (e) => e.message,
            'message',
            'Tu sesión expiró. Inicia sesión nuevamente.',
          ),
        ),
      );
    });

    test('403 se maneja como acceso denegado', () {
      expect(
        ServiceOrderPdfService.friendlyMessageForStatus(403),
        'No tienes acceso a esta orden de servicio.',
      );
    });

    test('404 se maneja como ticket no encontrado', () {
      expect(
        ServiceOrderPdfService.friendlyMessageForStatus(404),
        'No se encontró el ticket de servicio.',
      );
    });

    test('error servidor se maneja con mensaje genérico', () {
      expect(
        ServiceOrderPdfService.friendlyMessageForStatus(500),
        'No se pudo generar la orden de servicio.',
      );
    });

    test('botón loading impide doble llamada', () {
      final source = File(
        'lib/screens/tickets/ticket_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('if (_generatingServiceOrderPdf) return;'));
      expect(source, contains('onPressed: _generatingServiceOrderPdf'));
      expect(source, contains('? null'));
      expect(source, contains(': _openServiceOrderPdf'));
    });

    test('signed URL no se persiste localmente', () {
      final serviceSource = File(
        'lib/services/service_order_pdf_service.dart',
      ).readAsStringSync();
      final detailSource = File(
        'lib/screens/tickets/ticket_detail_screen.dart',
      ).readAsStringSync();
      final combined = '$serviceSource\n$detailSource';

      expect(combined, isNot(contains('SharedPreferences')));
      expect(combined, isNot(contains('setString')));
      expect(combined, isNot(contains('signed_url_complete')));
    });

    test('ticket detail mantiene resto de secciones', () {
      final source = File(
        'lib/screens/tickets/ticket_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains("'DATOS DEL EQUIPO'"));
      expect(source, contains("'TIPO DE SERVICIO'"));
      expect(source, contains("'DATOS DEL CLIENTE'"));
      expect(source, contains("'Evidencias'"));
      expect(source, contains("'Chat de Soporte Técnico'"));
    });

    test(
      'invoca generate-service-order-pdf con ticket_id únicamente',
      () async {
        Map<String, dynamic>? capturedBody;
        final service = ServiceOrderPdfService(
          invoke: (body) async {
            capturedBody = body;
            return const ServiceOrderPdfRawResponse(
              status: 200,
              data: validPayload,
            );
          },
        );

        await service.generate(ticketId: ' ticket-id ');

        expect(capturedBody, {'ticket_id': 'ticket-id'});
      },
    );

    test(
      'invoca generate-service-order-pdf con document_type final cuando se especifica',
      () async {
        Map<String, dynamic>? capturedBody;
        final service = ServiceOrderPdfService(
          invoke: (body) async {
            capturedBody = body;
            return ServiceOrderPdfRawResponse(
              status: 200,
              data: {...validPayload, 'document_type': 'final'},
            );
          },
        );

        final result = await service.generate(
          ticketId: ' ticket-id ',
          documentType: 'final',
        );

        expect(capturedBody, {
          'ticket_id': 'ticket-id',
          'document_type': 'final',
        });
        expect(result.documentType, 'final');
      },
    );

    test(
      'TicketDetailScreen integra ServiceCompletionCard de forma reactiva',
      () {
        final source = File(
          'lib/screens/tickets/ticket_detail_screen.dart',
        ).readAsStringSync();

        expect(source, contains('ServiceCompletionCard'));
        expect(source, contains('_openFinalServiceOrderPdf'));
        expect(source, contains('_loadServiceCompletion'));
        expect(source, contains('documentType: \'final\''));
      },
    );
  });
}
