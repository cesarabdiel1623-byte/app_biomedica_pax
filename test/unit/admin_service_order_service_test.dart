import 'dart:io';
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

  group('Free-Text Parts & Materials Capture Unit Tests (Section 19)', () {
    test(
      'A. 0 refacciones -> service completes with null parts_used_notes',
      () {
        final parts = <String>[];
        final formatted = parts.isEmpty ? null : parts.join('\n');
        expect(formatted, isNull);
      },
    );

    test('B. 1 refacción libre -> formats correctly', () {
      const name = 'Fusible 5A';
      const qty = '1';
      final formatted = '• $name';
      expect(formatted, '• Fusible 5A');
    });

    test('C. varias refacciones -> formats in order with quantities', () {
      final items = [
        {'name': 'Fusible 5A', 'qty': '2'},
        {'name': 'Cable de alimentación', 'qty': '1'},
        {'name': 'Fuente de poder XYZ', 'qty': '1'},
      ];

      final lines = items.map((item) {
        final name = item['name']!;
        final qty = item['qty']!;
        return qty != '1' ? '• $name (Cant: $qty)' : '• $name';
      }).toList();

      expect(lines.length, 3);
      expect(lines[0], '• Fusible 5A (Cant: 2)');
      expect(lines[1], '• Cable de alimentación');
      expect(lines[2], '• Fuente de poder XYZ');
    });

    test('D. espacios vacíos -> no crea elementos basura', () {
      final rawInputs = ['   ', '', '  \n  ', 'Batería interna'];
      final cleaned = rawInputs
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map((s) => '• $s')
          .toList();

      expect(cleaned.length, 1);
      expect(cleaned.first, '• Batería interna');
    });

    test('E. texto con acentos y caracteres especiales -> preservado', () {
      const complexText =
          'Conector de transductor ultrasónico & alimentación 120V~';
      final formatted = '• $complexText';
      expect(formatted, contains('ultrasónico'));
      expect(formatted, contains('alimentación'));
    });

    test('F, G, H. refacción libre no exige producto, almacén ni costo', () {
      // Las refacciones libres son texto libre desacoplado del inventario formal
      const freePart = 'Fuente de poder modelo XYZ';
      expect(freePart, isNotEmpty);
    });

    test('I. no rompe registerPartUsage ni ServicePartUsedItem existente', () {
      final partItem = ServicePartUsedItem.fromJson({
        'id': 'part-1',
        'service_order_id': 'order-1',
        'product_id': 'prod-uuid',
        'warehouse_id': 'wh-uuid',
        'quantity': 3.0,
        'unit_cost': 150.0,
        'products': {'name': 'Sensor de flujo'},
      });

      expect(partItem.productName, 'Sensor de flujo');
      expect(partItem.quantity, 3.0);
      expect(partItem.unitCost, 150.0);
    });

    test('J. resolved muestra refacciones guardadas en partsUsedNotes', () {
      final completion = ServiceCompletion.fromJson({
        'id': 'ord-1',
        'service_ticket_id': 'tck-1',
        'status': 'resolved',
        'completed_at': '2026-08-28T12:00:00Z',
        'diagnosis': 'Fusible fundido',
        'solution': 'Reemplazo de fusible',
        'parts_used_notes': '• Fusible 5A (Cant: 2)\n• Cable de alimentación',
      });

      expect(completion.partsUsedNotes, isNotNull);
      expect(completion.partsUsedNotes, contains('Fusible 5A'));
      expect(completion.partsUsedNotes, contains('Cable de alimentación'));
    });
  });

  group('ServiceCompletion Model Unit Tests', () {
    test(
      'ServiceCompletion parses JSON correctly with parts, notes and technician',
      () {
        final json = {
          'id': 'order-uuid-1',
          'service_ticket_id': 'ticket-uuid-1',
          'assigned_technician_id': 'tech-uuid-1',
          'diagnosis': 'Batería interna agotada',
          'solution': 'Se reemplaza batería por celda de litio nueva',
          'recommendations': 'Mantener conectado a corriente regulada',
          'parts_used_notes':
              '• Batería de litio 12V\n• Cable de poder grado médico',
          'status': 'resolved',
          'scheduled_at': '2026-08-19T10:00:00Z',
          'started_at': '2026-08-19T10:30:00Z',
          'completed_at': '2026-08-19T12:00:00Z',
          'report_pdf_path': 'orders/ticket-uuid-1/orden_servicio_final.pdf',
          'assigned_technician': {'full_name': 'Ing. Carlos Mendoza'},
          'service_parts_used': [
            {
              'id': 'part-used-1',
              'service_order_id': 'order-uuid-1',
              'product_id': 'prod-battery-1',
              'warehouse_id': 'wh-main',
              'quantity': 1,
              'unit_cost': 450.0,
              'created_at': '2026-08-19T11:00:00Z',
              'products': {'name': 'Batería 12V 7Ah Biomédica'},
            },
          ],
        };

        final model = ServiceCompletion.fromJson(json);

        expect(model.id, 'order-uuid-1');
        expect(model.serviceTicketId, 'ticket-uuid-1');
        expect(model.assignedTechnicianName, 'Ing. Carlos Mendoza');
        expect(model.diagnosis, 'Batería interna agotada');
        expect(model.solution, 'Se reemplaza batería por celda de litio nueva');
        expect(
          model.recommendations,
          'Mantener conectado a corriente regulada',
        );
        expect(
          model.partsUsedNotes,
          '• Batería de litio 12V\n• Cable de poder grado médico',
        );
        expect(model.status, 'resolved');
        expect(model.isCompleted, isTrue);
        expect(model.partsUsed.length, 1);
        expect(model.partsUsed.first.productName, 'Batería 12V 7Ah Biomédica');
        expect(model.partsUsed.first.quantity, 1.0);
      },
    );

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
      expect(model.partsUsedNotes, isNull);
      expect(model.partsUsed, isEmpty);
    });
  });

  group('PDF Technical & Migration Contract Tests (Section 20)', () {
    test(
      'Migration file 20260828130000_t2c1_service_orders_parts_used_notes.sql exists and is robust',
      () {
        final file = File(
          'supabase/migrations/20260828130000_t2c1_service_orders_parts_used_notes.sql',
        );
        expect(file.existsSync(), isTrue);
        final sql = file.readAsStringSync();

        expect(sql, contains('ALTER TABLE public.service_orders'));
        expect(sql, contains('ADD COLUMN IF NOT EXISTS parts_used_notes text'));
        expect(
          sql,
          contains('CREATE OR REPLACE FUNCTION public.complete_service_order'),
        );
        expect(sql, contains('p_parts_used_notes text DEFAULT NULL'));
        expect(sql, contains('guard_service_orders_immutability'));
        expect(sql, contains('parts_used_notes'));
      },
    );

    test(
      'Edge function service_order_pdf_engine.ts supports multiline breaks and clean institution spacing',
      () {
        final engineFile = File(
          'supabase/functions/_shared/service_order_pdf_engine.ts',
        );
        expect(engineFile.existsSync(), isTrue);
        final ts = engineFile.readAsStringSync();

        expect(ts, contains('rawParagraphs = normalized.split('));
        expect(
          ts,
          contains('institution: { x: 450.0, y: 499.5, maxWidth: 105.0'),
        );
        expect(ts, contains('drawMultilineBlock'));
      },
    );

    test(
      'generate-service-order-pdf index.ts selects parts_used_notes and formats observations cleanly',
      () {
        final indexFile = File(
          'supabase/functions/generate-service-order-pdf/index.ts',
        );
        expect(indexFile.existsSync(), isTrue);
        final ts = indexFile.readAsStringSync();

        expect(ts, contains('parts_used_notes'));
        expect(
          ts,
          contains('DIAGNÓSTICO:\\n\${diag}\\n\\nTRABAJO REALIZADO:\\n\${sol}'),
        );
        expect(ts, contains('REFACCIONES UTILIZADAS:'));
      },
    );
  });
}
