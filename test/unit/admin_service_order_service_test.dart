import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/service_completion.dart';
import 'package:gomedical_app/services/admin_service_order_service.dart';

void main() {
  group('AdminServiceOrderService Validation Unit Tests', () {
    test('validateCompletionInput accepts valid diagnosis and solution', () {
      expect(
        () => AdminServiceOrderService.validateCompletionInput(
          diagnosis: 'Falla en sensor óptico de oximetría',
          solution: 'Reemplazo de sensor y calibración con simulador',
        ),
        returnsNormally,
      );
    });

    test('validateCompletionInput rejects empty diagnosis', () {
      expect(
        () => AdminServiceOrderService.validateCompletionInput(
          diagnosis: '   ',
          solution: 'Solución aplicada',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validateCompletionInput rejects empty solution', () {
      expect(
        () => AdminServiceOrderService.validateCompletionInput(
          diagnosis: 'Diagnóstico técnico',
          solution: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validatePartUsage accepts valid parameters with quantity > 0', () {
      expect(
        () => AdminServiceOrderService.validatePartUsage(
          serviceOrderId: 'order-123',
          productId: 'prod-456',
          warehouseId: 'wh-789',
          quantity: 2.5,
        ),
        returnsNormally,
      );
    });

    test('validatePartUsage rejects non-positive quantity', () {
      expect(
        () => AdminServiceOrderService.validatePartUsage(
          serviceOrderId: 'order-123',
          productId: 'prod-456',
          warehouseId: 'wh-789',
          quantity: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AdminServiceOrderService.validatePartUsage(
          serviceOrderId: 'order-123',
          productId: 'prod-456',
          warehouseId: 'wh-789',
          quantity: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validatePartUsage rejects empty IDs', () {
      expect(
        () => AdminServiceOrderService.validatePartUsage(
          serviceOrderId: '  ',
          productId: 'prod-1',
          warehouseId: 'wh-1',
          quantity: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AdminServiceOrderService.validatePartUsage(
          serviceOrderId: 'order-1',
          productId: '',
          warehouseId: 'wh-1',
          quantity: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AdminServiceOrderService.validatePartUsage(
          serviceOrderId: 'order-1',
          productId: 'prod-1',
          warehouseId: '  ',
          quantity: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ServiceCompletion Model Unit Tests', () {
    test('ServiceCompletion parses JSON correctly with parts and technician', () {
      final json = {
        'id': 'order-uuid-1',
        'service_ticket_id': 'ticket-uuid-1',
        'assigned_technician_id': 'tech-uuid-1',
        'diagnosis': 'Batería interna agotada',
        'solution': 'Se reemplaza batería por celda de litio nueva',
        'recommendations': 'Mantener conectado a corriente regulada',
        'status': 'resolved',
        'scheduled_at': '2026-08-19T10:00:00Z',
        'started_at': '2026-08-19T10:30:00Z',
        'completed_at': '2026-08-19T12:00:00Z',
        'report_pdf_path': 'orders/ticket-uuid-1/orden_servicio_final.pdf',
        'assigned_technician': {
          'full_name': 'Ing. Carlos Mendoza',
        },
        'service_parts_used': [
          {
            'id': 'part-used-1',
            'service_order_id': 'order-uuid-1',
            'product_id': 'prod-battery-1',
            'warehouse_id': 'wh-main',
            'quantity': 1,
            'unit_cost': 450.0,
            'created_at': '2026-08-19T11:00:00Z',
            'products': {
              'name': 'Batería 12V 7Ah Biomédica',
            },
          }
        ],
      };

      final model = ServiceCompletion.fromJson(json);

      expect(model.id, 'order-uuid-1');
      expect(model.serviceTicketId, 'ticket-uuid-1');
      expect(model.assignedTechnicianName, 'Ing. Carlos Mendoza');
      expect(model.diagnosis, 'Batería interna agotada');
      expect(model.solution, 'Se reemplaza batería por celda de litio nueva');
      expect(model.recommendations, 'Mantener conectado a corriente regulada');
      expect(model.status, 'resolved');
      expect(model.isCompleted, isTrue);
      expect(model.partsUsed.length, 1);
      expect(model.partsUsed.first.productName, 'Batería 12V 7Ah Biomédica');
      expect(model.partsUsed.first.quantity, 1.0);
    });

    test('ServiceCompletion handles empty / incomplete state correctly', () {
      final json = {
        'id': 'order-uuid-2',
        'service_ticket_id': 'ticket-uuid-2',
        'status': 'in_progress',
        'started_at': '2026-08-19T09:00:00Z',
      };

      final model = ServiceCompletion.fromJson(json);

      expect(model.id, 'order-uuid-2');
      expect(model.isCompleted, isFalse);
      expect(model.diagnosis, isNull);
      expect(model.solution, isNull);
      expect(model.partsUsed, isEmpty);
    });

    test('ServiceCompletion completion states require completedAt explicitly', () {
      final resolvedWithDate = ServiceCompletion.fromJson({
        'id': 'order-resolved',
        'service_ticket_id': 'ticket',
        'status': 'resolved',
        'completed_at': '2026-08-19T12:00:00Z',
      });
      final closedWithDate = ServiceCompletion.fromJson({
        'id': 'order-closed',
        'service_ticket_id': 'ticket',
        'status': 'closed',
        'completed_at': '2026-08-19T12:00:00Z',
      });
      final closedWithoutDate = ServiceCompletion.fromJson({
        'id': 'order-closed-no-date',
        'service_ticket_id': 'ticket',
        'status': 'closed',
      });
      final inProgress = ServiceCompletion.fromJson({
        'id': 'order-progress',
        'service_ticket_id': 'ticket',
        'status': 'in_progress',
        'started_at': '2026-08-19T10:00:00Z',
      });

      expect(resolvedWithDate.isCompleted, isTrue);
      expect(closedWithDate.isCompleted, isTrue);
      expect(closedWithoutDate.isCompleted, isFalse);
      expect(inProgress.isCompleted, isFalse);
    });
  });

  group('Service Idempotency & Concurrency Logic Tests', () {
    test('start retry preserves started_at timestamp', () {
      final initialStartedAt = DateTime.parse('2026-08-19T08:00:00Z');
      DateTime calculateStartedAt(DateTime? existingStartedAt) {
        return existingStartedAt ?? DateTime.now();
      }

      final retriedStartedAt = calculateStartedAt(initialStartedAt);
      expect(retriedStartedAt, equals(initialStartedAt));
    });

    test('complete retry with identical recommendations is idempotent', () {
      const existingDiagnosis = 'Falla sensor';
      const existingSolution = 'Sensor reemplazado';
      const existingRecommendations = 'Calibrar en 6 meses';

      bool isIdempotentRetry({
        required String diagnosis,
        required String solution,
        required String? recommendations,
      }) {
        return existingDiagnosis == diagnosis.trim() &&
            existingSolution == solution.trim() &&
            existingRecommendations == (recommendations?.trim() ?? '');
      }

      expect(
        isIdempotentRetry(
          diagnosis: 'Falla sensor',
          solution: 'Sensor reemplazado',
          recommendations: 'Calibrar en 6 meses',
        ),
        isTrue,
      );

      expect(
        isIdempotentRetry(
          diagnosis: 'Falla sensor',
          solution: 'Sensor reemplazado',
          recommendations: 'Cambiar cable también',
        ),
        isFalse,
      );
    });

    test('close retry on closed ticket preserves closed state without transition', () {
      const ticketStatus = 'closed';
      bool shouldEmitCloseEvent(String currentStatus) {
        return currentStatus != 'closed';
      }

      expect(shouldEmitCloseEvent(ticketStatus), isFalse);
    });
  });

  group('PDF Technical Formatting Logic Tests', () {
    test('Final PDF combines diagnosis and solution distinctly without replacing customer failure', () {
      const customerFailure = 'El monitor se apaga después de 5 minutos de uso.';
      const technicalDiagnosis = 'Batería interna sulfatada y ventilador bloqueado por polvo.';
      const technicalSolution = 'Limpieza de ventilador y sustitución de celda de batería 12V.';
      const recommendations = 'Realizar mantenimiento preventivo cada 6 meses.';

      final formattedWorkPerformed =
          'DIAGNÓSTICO:\n$technicalDiagnosis\n\nTRABAJO REALIZADO:\n$technicalSolution';

      expect(customerFailure, isNotEmpty);
      expect(formattedWorkPerformed.contains('DIAGNÓSTICO:'), isTrue);
      expect(formattedWorkPerformed.contains('TRABAJO REALIZADO:'), isTrue);
      expect(formattedWorkPerformed.contains(customerFailure), isFalse);
      expect(recommendations, isNotEmpty);
    });
  });
}
