import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/service_order_presentation.dart';
import 'package:gomedical_app/models/service_ticket.dart';

void main() {
  group('Service Ticket Client Flow & Status Alignment', () {
    test('A. Status mapping conforms to admin workflow', () {
      final openTicket = ServiceTicket.fromJson({
        'id': 'tck-1',
        'ticket_number': 'TCK-1',
        'title': 'Test Open',
        'status': 'open',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-28T00:00:00Z',
      });
      final assignedTicket = ServiceTicket.fromJson({
        'id': 'tck-2',
        'ticket_number': 'TCK-2',
        'title': 'Test Assigned',
        'status': 'assigned',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-28T00:00:00Z',
      });
      final inProgressTicket = ServiceTicket.fromJson({
        'id': 'tck-3',
        'ticket_number': 'TCK-3',
        'title': 'Test In Progress',
        'status': 'in_progress',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-28T00:00:00Z',
      });
      final resolvedTicket = ServiceTicket.fromJson({
        'id': 'tck-4',
        'ticket_number': 'TCK-4',
        'title': 'Test Resolved',
        'status': 'resolved',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-28T00:00:00Z',
      });
      final closedTicket = ServiceTicket.fromJson({
        'id': 'tck-5',
        'ticket_number': 'TCK-5',
        'title': 'Test Closed',
        'status': 'closed',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-28T00:00:00Z',
      });
      final cancelledTicket = ServiceTicket.fromJson({
        'id': 'tck-6',
        'ticket_number': 'TCK-6',
        'title': 'Test Cancelled',
        'status': 'cancelled',
        'priority': 'medium',
        'type': 'diagnostico',
        'created_at': '2026-08-28T00:00:00Z',
      });

      expect(openTicket.statusLabel, 'Abierto');
      expect(assignedTicket.statusLabel, 'Asignado');
      expect(inProgressTicket.statusLabel, 'En progreso');
      expect(resolvedTicket.statusLabel, 'Servicio realizado');
      expect(closedTicket.statusLabel, 'Cerrado');
      expect(cancelledTicket.statusLabel, 'Cancelado');
    });

    test('B. Status mapping is distinct for resolved and closed', () {
      final resolved = ServiceTicket.fromJson({
        'id': 'tck-res',
        'ticket_number': 'TCK-RES',
        'title': 'Resolved',
        'status': 'resolved',
        'priority': 'low',
        'type': 'preventivo',
        'created_at': '2026-08-28T00:00:00Z',
      });
      final closed = ServiceTicket.fromJson({
        'id': 'tck-clo',
        'ticket_number': 'TCK-CLO',
        'title': 'Closed',
        'status': 'closed',
        'priority': 'low',
        'type': 'preventivo',
        'created_at': '2026-08-28T00:00:00Z',
      });

      expect(resolved.statusLabel, isNot(equals(closed.statusLabel)));
      expect(resolved.statusLabel, 'Servicio realizado');
      expect(closed.statusLabel, 'Cerrado');
    });

    test('C. Chat logic rule verification in ticket_detail_screen', () {
      final detailSource = File(
        'lib/screens/tickets/ticket_detail_screen.dart',
      ).readAsStringSync();

      // Ensure resolved is NOT blocking the chat
      expect(detailSource.contains("status != 'resolved'"), isFalse);

      // Ensure only closed and cancelled block chat
      expect(detailSource.contains("status != 'closed'"), isTrue);
      expect(detailSource.contains("status != 'cancelled'"), isTrue);
      expect(detailSource.contains("status != 'canceled'"), isTrue);

      // Ensure chat archived banner text is updated
      expect(
        detailSource.contains('Servicio cerrado. Chat archivado.'),
        isTrue,
      );
    });

    test('D. Order PDF actions reflect Preliminary vs Final correctly', () {
      final detailSource = File(
        'lib/screens/tickets/ticket_detail_screen.dart',
      ).readAsStringSync();

      // Checks for _buildServiceOrderPdfAction taking ticket
      expect(
        detailSource.contains(
          'Widget _buildServiceOrderPdfAction(ServiceTicket ticket)',
        ),
        isTrue,
      );
      expect(
        detailSource.contains("ticket.status.toLowerCase() == 'resolved' ||"),
        isTrue,
      );
      expect(detailSource.contains('class _FinalChip'), isTrue);
      expect(detailSource.contains('class _PreliminaryChip'), isTrue);
      expect(
        detailSource.contains(
          'Documento final generado con la información y reporte técnico registrado.',
        ),
        isTrue,
      );
    });

    test('E. Status banners present for in_progress, resolved and closed', () {
      final detailSource = File(
        'lib/screens/tickets/ticket_detail_screen.dart',
      ).readAsStringSync();

      expect(detailSource.contains('Servicio técnico en proceso'), isTrue);
      expect(
        detailSource.contains(
          'El técnico terminó la atención y registró la información final del servicio. El caso está pendiente de cierre administrativo.',
        ),
        isTrue,
      );
      expect(detailSource.contains('El servicio ha sido cerrado.'), isTrue);
    });

    test('F. Equipment Brand and Model field fidelity', () {
      final ticket = ServiceTicket.fromJson({
        'id': 'tck-bm',
        'ticket_number': 'TCK-BM',
        'title': 'Test Equipment',
        'status': 'in_progress',
        'priority': 'medium',
        'type': 'correctivo',
        'created_at': '2026-08-28T00:00:00Z',
        'equipment_name': 'Bomba de Infusión',
        'equipment_brand': 'B. Braun',
        'equipment_model': 'Infusomat Space',
      });

      expect(ticket.equipmentBrand, 'B. Braun');
      expect(ticket.equipmentModel, 'Infusomat Space');

      final order = ServiceOrderPresentation.fromTicket(ticket);
      expect(order.equipmentBrand, 'B. Braun');
      expect(order.equipmentModel, 'Infusomat Space');
    });

    test('G. TicketsListScreen tab and filter alignment', () {
      final listSource = File(
        'lib/screens/tickets/tickets_list_screen.dart',
      ).readAsStringSync();

      expect(listSource.contains("('in_progress', 'En progreso')"), isTrue);
      expect(listSource.contains("('resolved', 'Servicio realizado')"), isTrue);
      expect(listSource.contains("('closed', 'Cerrados')"), isTrue);
    });
  });
}
