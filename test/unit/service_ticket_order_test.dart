import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/service_order_presentation.dart';
import 'package:gomedical_app/models/service_ticket.dart';
import 'package:gomedical_app/utils/service_ticket_card_presentation.dart';
import 'package:gomedical_app/utils/service_ticket_intake.dart';

void main() {
  group('T6.2 service ticket structured order', () {
    test('1. ServiceTicket parsea nuevas columnas', () {
      final ticket = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-1',
        'title': 'Diagnóstico: Monitor',
        'description': 'Pantalla intermitente',
        'status': 'open',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-17T00:00:00Z',
        'equipment_name': 'Monitor',
        'equipment_brand': 'Philips',
        'equipment_model': 'MX450',
        'serial_number': 'SN-123',
        'institution': 'Hospital Central',
        'department': 'Urgencias',
        'equipment_operating': false,
        'failure_description': 'Pantalla intermitente',
        'intake_details': {
          'issue_duration': 'Hace 2 a 7 días',
          'shows_error_code': 'Sí',
          'visible_damage': 'No',
        },
      });

      expect(ticket.equipmentName, 'Monitor');
      expect(ticket.equipmentBrand, 'Philips');
      expect(ticket.equipmentModel, 'MX450');
      expect(ticket.serialNumber, 'SN-123');
      expect(ticket.institution, 'Hospital Central');
      expect(ticket.department, 'Urgencias');
      expect(ticket.equipmentOperating, 'No');
      expect(ticket.failureDescription, 'Pantalla intermitente');
      expect(ticket.intakeDetails?['issue_duration'], 'Hace 2 a 7 días');
    });

    test(
      'diagnostico, intake_details null y equipment_operating null cargan',
      () {
        final ticket = ServiceTicket.fromJson({
          'id': 'ticket-id',
          'ticket_number': 'TCK-DIAG',
          'title': 'Diagnóstico: Monitor',
          'description': 'Revisión de comportamiento',
          'status': 'open',
          'priority': 'medium',
          'type': 'diagnostico',
          'created_at': '2026-08-17T00:00:00Z',
          'equipment_operating': null,
          'intake_details': null,
        });

        expect(ticket.typeLabel, 'Diagnóstico');
        expect(ticket.equipmentOperating, isNull);
        expect(ticket.intakeDetails, isNull);
        expect(
          ServiceOrderPresentation.fromTicket(ticket).failureDescription,
          'Revisión de comportamiento',
        );
      },
    );

    test('equipment_operating boolean true se muestra como Sí', () {
      final ticket = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-BOOL',
        'title': 'Mantenimiento preventivo: Equipo',
        'status': 'open',
        'priority': 'low',
        'type': 'preventivo',
        'created_at': '2026-08-17T00:00:00Z',
        'equipment_operating': true,
      });

      expect(ticket.equipmentOperating, 'Sí');
    });

    test('listado acepta mezcla de tickets viejos y nuevos', () {
      final rawTickets = [
        {
          'id': 'legacy-id',
          'ticket_number': 'TCK-OLD',
          'title': 'Reparación: Panel',
          'description': '''
=== INFORMACIÓN DEL EQUIPO ===
• Nombre: Panel

=== SOLICITUD ===
• Tipo: Reparación

=== Descripción ===
Falla intermitente.
''',
          'status': 'open',
          'priority': 'medium',
          'type': 'reparacion',
          'created_at': '2026-08-17T00:00:00Z',
        },
        {
          'id': 'new-id',
          'ticket_number': 'TCK-NEW',
          'title': 'Diagnóstico: Monitor',
          'description': 'No entrega lectura estable',
          'status': 'open',
          'priority': 'medium',
          'type': 'diagnostico',
          'created_at': '2026-08-17T00:00:00Z',
          'equipment_name': 'Monitor',
          'equipment_operating': false,
          'failure_description': 'No entrega lectura estable',
          'intake_details': {'issue_duration': 'Hoy'},
        },
      ];

      final tickets = rawTickets.map(ServiceTicket.fromJson).toList();

      expect(tickets, hasLength(2));
      expect(tickets[0].typeLabel, 'Mantenimiento correctivo');
      expect(tickets[1].typeLabel, 'Diagnóstico');
      expect(tickets[1].equipmentOperating, 'No');
    });

    test('2-8. ticket nuevo usa columnas estructuradas en presentación', () {
      final order = ServiceOrderPresentation.fromTicket(
        ServiceTicket.fromJson({
          'id': 'ticket-id',
          'ticket_number': 'TCK-2',
          'title': 'Mantenimiento correctivo: Ventilador',
          'description': 'Hace ruido al iniciar',
          'status': 'open',
          'priority': 'medium',
          'type': 'correctivo',
          'created_at': '2026-08-17T00:00:00Z',
          'equipment_name': 'Ventilador',
          'equipment_brand': 'Vela',
          'equipment_model': 'V1',
          'serial_number': 'VELA-1',
          'institution': 'Clínica Norte',
          'department': 'Terapia',
          'equipment_operating': 'Sí',
          'failure_description': 'Hace ruido al iniciar',
          'intake_details': {'visible_damage': 'No'},
        }),
      );

      expect(order.isStructured, isTrue);
      expect(order.equipmentName, 'Ventilador');
      expect(order.equipmentBrand, 'Vela');
      expect(order.equipmentModel, 'V1');
      expect(order.serialNumber, 'VELA-1');
      expect(order.institution, 'Clínica Norte');
      expect(order.department, 'Terapia');
      expect(order.equipmentOperating, 'Sí');
      expect(order.failureDescription, 'Hace ruido al iniciar');
    });

    test('9. preventivo genera intake_details correspondiente', () {
      final details = buildServiceTicketIntakeDetails(
        type: 'preventivo',
        previousMaintenance: 'Sí',
        lastMaintenanceDate: DateTime(2026, 8, 1),
        issueDuration: 'No debe guardarse',
      );

      expect(details, {
        'previous_maintenance': 'Sí',
        'last_maintenance_date': '2026-08-01',
      });
    });

    test('10. correctivo genera intake_details correspondiente', () {
      final details = buildServiceTicketIntakeDetails(
        type: 'correctivo',
        issueDuration: 'Hoy',
        visibleDamage: 'No',
        previousRepair: 'No lo sé',
        showsErrorCode: 'Sí',
      );

      expect(details, {
        'issue_duration': 'Hoy',
        'visible_damage': 'No',
        'previous_repair': 'No lo sé',
      });
    });

    test(
      '11-12. diagnostico genera intake_details y no duplica error_code',
      () {
        final details = buildServiceTicketIntakeDetails(
          type: 'diagnostico',
          issueDuration: 'Hace más de una semana',
          showsErrorCode: 'Sí',
          visibleDamage: 'Sí',
        );

        expect(details, {
          'issue_duration': 'Hace más de una semana',
          'shows_error_code': 'Sí',
          'visible_damage': 'Sí',
        });
        expect(details.containsKey('error_code'), isFalse);
      },
    );

    test('13-14. ticket legacy sigue renderizando datos y parser funciona', () {
      const legacyDescription = '''
=== INFORMACIÓN DEL EQUIPO ===
• Nombre: Ultrasonido portatil
• Modelo: US-1
• Marca: Acme
• Número de serie: SN-9

=== SOLICITUD ===
• Tipo: Mantenimiento preventivo
• ¿El equipo enciende?: Sí
• Mantenimiento preventivo anterior: No

=== Descripción ===
El equipo requiere revisión general.

=== CONTACTO Y LOGÍSTICA ===
• Responsable: Juan Pérez
• Teléfono: 9991112222
• Área o departamento: Radiología
• Institución: Hospital #34
• Dirección: Calle 45
• Evidencia: 1 fotografía(s) y 0 video(s)
''';

      final order = ServiceOrderPresentation.fromTicket(
        ServiceTicket.fromJson({
          'id': 'ticket-id',
          'ticket_number': 'TCK-20260810-65F83353',
          'title': 'Mantenimiento preventivo: Ultrasonido portatil',
          'description': legacyDescription,
          'status': 'open',
          'priority': 'low',
          'type': 'preventivo',
          'created_at': '2026-08-17T00:00:00Z',
        }),
      );

      expect(order.isStructured, isFalse);
      expect(order.equipmentName, 'Ultrasonido portatil');
      expect(order.equipmentBrand, 'Acme');
      expect(order.equipmentModel, 'US-1');
      expect(order.serialNumber, 'SN-9');
      expect(order.equipmentOperating, 'Sí');
      expect(order.failureDescription, 'El equipo requiere revisión general.');
      expect(order.responsible, 'Juan Pérez');
      expect(order.phone, '9991112222');
      expect(order.department, 'Radiología');
      expect(order.institution, 'Hospital #34');
      expect(order.legacyEvidenceSummary, '1 fotografía(s) y 0 video(s)');
    });

    test('15. reparacion legacy se muestra Mantenimiento correctivo', () {
      final ticket = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-3',
        'title': 'Reparación: Panel',
        'status': 'open',
        'priority': 'medium',
        'type': 'reparacion',
        'created_at': '2026-08-17T00:00:00Z',
      });

      expect(ticket.typeLabel, 'Mantenimiento correctivo');
    });

    test('card title reparacion legacy -> Mantenimiento correctivo', () {
      final ticket = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-5',
        'title': 'Reparación: Panel JYJ',
        'status': 'open',
        'priority': 'medium',
        'type': 'reparacion',
        'created_at': '2026-08-17T00:00:00Z',
      });

      expect(
        serviceTicketCardTitle(ticket),
        'Mantenimiento correctivo: Panel JYJ',
      );
    });

    test('card title mantiene preventivo correctivo y diagnostico', () {
      final preventivo = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-P',
        'title': 'Mantenimiento preventivo: Ultrasonido',
        'status': 'open',
        'priority': 'low',
        'type': 'preventivo',
        'created_at': '2026-08-17T00:00:00Z',
      });
      final correctivo = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-C',
        'title': 'Mantenimiento correctivo: Panel',
        'status': 'open',
        'priority': 'medium',
        'type': 'correctivo',
        'created_at': '2026-08-17T00:00:00Z',
      });
      final diagnostico = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-D',
        'title': 'Diagnóstico: Monitor',
        'status': 'open',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-17T00:00:00Z',
      });

      expect(
        serviceTicketCardTitle(preventivo),
        'Mantenimiento preventivo: Ultrasonido',
      );
      expect(
        serviceTicketCardTitle(correctivo),
        'Mantenimiento correctivo: Panel',
      );
      expect(serviceTicketCardTitle(diagnostico), 'Diagnóstico: Monitor');
    });

    test('card preview estructurado usa failure_description', () {
      final ticket = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-6',
        'title': 'Diagnóstico: Monitor',
        'description': 'Texto de compatibilidad',
        'status': 'open',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-17T00:00:00Z',
        'failure_description':
            'El equipo intenta encender, muestra E01 y se apaga.',
      });

      expect(
        serviceTicketCardPreview(ticket),
        'El equipo intenta encender, muestra E01 y se apaga.',
      );
    });

    test('card preview legacy usa solo sección Descripción', () {
      const legacyDescription = '''
=== INFORMACIÓN DEL EQUIPO ===
• Nombre: Ultrasonido portatil
• Modelo: TYT
• Marca: Lg
• Número de serie: No proporcionado

=== SOLICITUD ===
• Tipo: Mantenimiento preventivo

=== Descripción ===
Mantenimiento común de cada dos meses

=== CONTACTO Y LOGÍSTICA ===
• Responsable: Juan
''';
      final ticket = ServiceTicket.fromJson({
        'id': 'ticket-id',
        'ticket_number': 'TCK-7',
        'title': 'Mantenimiento preventivo: Ultrasonido',
        'description': legacyDescription,
        'status': 'open',
        'priority': 'low',
        'type': 'preventivo',
        'created_at': '2026-08-17T00:00:00Z',
      });
      final preview = serviceTicketCardPreview(ticket);

      expect(preview, 'Mantenimiento común de cada dos meses');
      expect(preview.contains('=== INFORMACIÓN DEL EQUIPO ==='), isFalse);
      expect(preview.contains('Nombre:'), isFalse);
      expect(preview.contains('Modelo:'), isFalse);
    });

    test(
      '16-17. campos null no generan datos falsos y description simple sigue',
      () {
        final order = ServiceOrderPresentation.fromTicket(
          ServiceTicket.fromJson({
            'id': 'ticket-id',
            'ticket_number': 'TCK-4',
            'title': 'Ticket simple',
            'description': 'Descripción sin formato legacy',
            'status': 'open',
            'priority': 'medium',
            'type': 'otro',
            'created_at': '2026-08-17T00:00:00Z',
          }),
        );

        expect(order.equipmentName, isNull);
        expect(order.failureDescription, 'Descripción sin formato legacy');
        expect(order.intakeDetails, isEmpty);
      },
    );

    test('18-19. Flutter no toca service_orders ni maintenance_logs', () {
      final maintenanceSource = File(
        'lib/screens/profile/maintenance_screen.dart',
      ).readAsStringSync();
      final detailSource = File(
        'lib/screens/tickets/ticket_detail_screen.dart',
      ).readAsStringSync();
      final combined = '$maintenanceSource\n$detailSource';

      expect(combined.contains('service_orders'), isFalse);
      expect(combined.contains('maintenance_logs'), isFalse);
    });

    test('ticket nuevo no genera bloque concatenado gigante', () {
      final source = File(
        'lib/screens/profile/maintenance_screen.dart',
      ).readAsStringSync();

      expect(source.contains('=== INFORMACIÓN DEL EQUIPO ==='), isFalse);
      expect(source.contains('=== CONTACTO Y LOGÍSTICA ==='), isFalse);
      expect(source.contains("'equipment_name': equipmentName"), isTrue);
      expect(
        source.contains("'failure_description': failureDescription"),
        isTrue,
      );
    });

    test('marca y modelo se mapean y muestran con fidelidad contractual', () {
      final ticket = ServiceTicket.fromJson({
        'id': 'tck-e2e',
        'ticket_number': 'TCK-20260824-F01697F6',
        'title':
            'Mantenimiento preventivo: Ultrasonido e2e test MARCA TEST Modelo Test-2026',
        'status': 'in_progress',
        'priority': 'low',
        'type': 'preventivo',
        'created_at': '2026-08-24T16:38:59.974Z',
        'equipment_name': 'Ultrasonido e2e test',
        'equipment_brand': 'MARCA TEST',
        'equipment_model': 'Modelo Test-2026',
      });

      expect(ticket.equipmentBrand, 'MARCA TEST');
      expect(ticket.equipmentModel, 'Modelo Test-2026');
      expect(ticket.equipmentName, 'Ultrasonido e2e test');

      final order = ServiceOrderPresentation.fromTicket(ticket);
      expect(order.equipmentBrand, 'MARCA TEST');
      expect(order.equipmentModel, 'Modelo Test-2026');
      expect(order.equipmentName, 'Ultrasonido e2e test');

      final maintenanceSource = File(
        'lib/screens/profile/maintenance_screen.dart',
      ).readAsStringSync();
      expect(
        maintenanceSource.contains("'equipment_brand': equipmentBrand"),
        isTrue,
      );
      expect(
        maintenanceSource.contains("'equipment_model': equipmentModel"),
        isTrue,
      );
    });

    test(
      'scheduledStartAt en UTC se formatea mediante toLocal correctamente',
      () {
        final utcString = '2026-08-25T16:00:00.000Z';
        final ticket = ServiceTicket.fromJson({
          'id': 'tck-tz',
          'ticket_number': 'TCK-TZ',
          'title': 'Test Horario',
          'status': 'assigned',
          'priority': 'medium',
          'type': 'preventivo',
          'created_at': '2026-08-24T16:00:00Z',
          'scheduled_start_at': utcString,
        });

        expect(ticket.scheduledStartAt, isNotNull);
        final parsed = ticket.scheduledStartAt!;
        expect(parsed.isUtc, isTrue);

        final local = parsed.toLocal();
        expect(local.isUtc, isFalse);

        final detailSource = File(
          'lib/screens/tickets/ticket_detail_screen.dart',
        ).readAsStringSync();
        expect(detailSource.contains('final local = d.toLocal();'), isTrue);
        expect(
          detailSource.contains(
            'final localCreatedAt = msg.createdAt.toLocal();',
          ),
          isTrue,
        );

        final listSource = File(
          'lib/screens/tickets/tickets_list_screen.dart',
        ).readAsStringSync();
        expect(listSource.contains('final local = d.toLocal();'), isTrue);
      },
    );
  });
}
