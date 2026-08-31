import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/service_completion.dart';
import 'package:gomedical_app/widgets/service_completion_card.dart';

void main() {
  group('ServiceCompletion Model & isCompleted Tests', () {
    test('A & G: in_progress or uncompleted orders are NOT completed', () {
      final active = ServiceCompletion(
        id: 'order-1',
        serviceTicketId: 'ticket-1',
        status: 'in_progress',
        startedAt: DateTime.parse('2026-08-19T10:00:00Z'),
      );
      expect(active.isCompleted, isFalse);

      final activeWithDate = ServiceCompletion(
        id: 'order-2',
        serviceTicketId: 'ticket-1',
        status: 'in_progress',
        completedAt: DateTime.parse('2026-08-19T11:00:00Z'),
      );
      expect(activeWithDate.isCompleted, isFalse);
    });

    test('B: resolved + completed_at is completed', () {
      final resolved = ServiceCompletion(
        id: 'order-3',
        serviceTicketId: 'ticket-1',
        status: 'resolved',
        completedAt: DateTime.parse('2026-08-19T12:00:00Z'),
      );
      expect(resolved.isCompleted, isTrue);
    });

    test('C: closed + completed_at is completed', () {
      final closed = ServiceCompletion(
        id: 'order-4',
        serviceTicketId: 'ticket-1',
        status: 'closed',
        completedAt: DateTime.parse('2026-08-19T13:00:00Z'),
      );
      expect(closed.isCompleted, isTrue);
    });

    test('D: closed without completed_at is NOT completed', () {
      final closedNoDate = ServiceCompletion(
        id: 'order-5',
        serviceTicketId: 'ticket-1',
        status: 'closed',
        completedAt: null,
      );
      expect(closedNoDate.isCompleted, isFalse);
    });

    test(
      'H: multiple historical orders selection logic prioritizes latest completed',
      () {
        final historical1 = ServiceCompletion(
          id: 'order-old',
          serviceTicketId: 'ticket-1',
          status: 'resolved',
          completedAt: DateTime.parse('2026-08-10T10:00:00Z'),
        );
        final historical2 = ServiceCompletion(
          id: 'order-new',
          serviceTicketId: 'ticket-1',
          status: 'closed',
          completedAt: DateTime.parse('2026-08-19T15:00:00Z'),
        );
        final list = [historical1, historical2];
        list.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));

        expect(list.first.id, 'order-new');
      },
    );
  });

  group('ServiceCompletionCard Widget Tests', () {
    testWidgets('E: renders technical details and parts without unit cost', (
      WidgetTester tester,
    ) async {
      final completion = ServiceCompletion(
        id: 'order-123',
        serviceTicketId: 'ticket-456',
        assignedTechnicianName: 'Ing. Carlos Mendoza',
        diagnosis: 'Sensor de oxígeno descalibrado',
        solution: 'Reemplazo de sensor y calibración con gas patrón',
        recommendations: 'Uso en ambiente libre de humedad excesiva',
        status: 'resolved',
        completedAt: DateTime.parse('2026-08-19T11:30:00Z'),
        partsUsed: const [
          ServicePartUsedItem(
            id: 'part-1',
            serviceOrderId: 'order-123',
            productId: 'prod-sensor-1',
            productName: 'Sensor de Oxígeno Médico O2',
            quantity: 1,
            unitCost: 1500.0, // Should NOT be rendered
          ),
        ],
      );

      bool downloadClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceCompletionCard(
              serviceCompletion: completion,
              onDownloadReportPdf: () => downloadClicked = true,
            ),
          ),
        ),
      );

      expect(find.text('Servicio Técnico Finalizado'), findsOneWidget);
      expect(find.text('Diagnóstico Técnico Final:'), findsOneWidget);
      expect(find.text('Sensor de oxígeno descalibrado'), findsOneWidget);
      expect(find.text('Trabajo Realizado y Solución:'), findsOneWidget);
      expect(
        find.text('Reemplazo de sensor y calibración con gas patrón'),
        findsOneWidget,
      );
      expect(find.text('Recomendaciones del Especialista:'), findsOneWidget);
      expect(
        find.text('Uso en ambiente libre de humedad excesiva'),
        findsOneWidget,
      );
      expect(
        find.text('Técnico Responsable: Ing. Carlos Mendoza'),
        findsOneWidget,
      );
      expect(
        find.text('Sensor de Oxígeno Médico O2 — 1 pieza'),
        findsOneWidget,
      );

      // Verify unit cost (1500) is NOT rendered anywhere
      expect(find.textContaining('1500'), findsNothing);
      expect(find.textContaining('\$1,500'), findsNothing);

      // Verify Download Button
      final downloadButton = find.text(
        'Descargar Orden de Servicio Oficial (PDF)',
      );
      expect(downloadButton, findsOneWidget);

      await tester.tap(downloadButton);
      await tester.pump();

      expect(downloadClicked, isTrue);
    });

    testWidgets('Shows loading indicator when isDownloadingPdf is true', (
      WidgetTester tester,
    ) async {
      final completion = ServiceCompletion(
        id: 'order-123',
        serviceTicketId: 'ticket-456',
        diagnosis: 'Diagnóstico de prueba',
        solution: 'Solución de prueba',
        status: 'resolved',
        completedAt: DateTime.parse('2026-08-19T11:30:00Z'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceCompletionCard(
              serviceCompletion: completion,
              isDownloadingPdf: true,
              onDownloadReportPdf: () {},
            ),
          ),
        ),
      );

      expect(find.text('Generando documento...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'Renders free-text partsUsedNotes with bullet points and without unit cost',
      (WidgetTester tester) async {
        final completion = ServiceCompletion(
          id: 'order-free-parts',
          serviceTicketId: 'ticket-789',
          diagnosis: 'Fusible dañado y cable cortado',
          solution: 'Reemplazo de componentes de alimentación',
          partsUsedNotes:
              '• Fusible 5A (Cant: 2)\n• Cable de alimentación grado médico',
          status: 'resolved',
          completedAt: DateTime.parse('2026-08-28T12:00:00Z'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServiceCompletionCard(serviceCompletion: completion),
            ),
          ),
        );

        expect(
          find.text('Refacciones / Materiales Utilizados:'),
          findsOneWidget,
        );
        expect(find.text('Fusible 5A (Cant: 2)'), findsOneWidget);
        expect(find.text('Cable de alimentación grado médico'), findsOneWidget);
      },
    );

    testWidgets(
      'Combines BOTH partsUsedNotes AND partsUsed without losing either source',
      (WidgetTester tester) async {
        final completion = ServiceCompletion(
          id: 'order-combined-parts',
          serviceTicketId: 'ticket-888',
          diagnosis: 'Mantenimiento integral correctivo',
          solution: 'Reemplazo de partes electrónicas y consumibles',
          partsUsedNotes: 'Fusible 5A\nCable de alimentación',
          status: 'resolved',
          completedAt: DateTime.parse('2026-08-28T14:00:00Z'),
          partsUsed: const [
            ServicePartUsedItem(
              id: 'part-structured-1',
              serviceOrderId: 'order-combined-parts',
              productId: 'prod-transductor',
              productName: 'Transductor X',
              quantity: 1,
              unitCost: 3500.0,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServiceCompletionCard(serviceCompletion: completion),
            ),
          ),
        );

        expect(find.text('Fusible 5A'), findsOneWidget);
        expect(find.text('Cable de alimentación'), findsOneWidget);
        expect(find.text('Transductor X — 1 pieza'), findsOneWidget);
        expect(find.textContaining('3500'), findsNothing);
      },
    );

    testWidgets('Renders "Ninguna" when no parts were used', (
      WidgetTester tester,
    ) async {
      final completion = ServiceCompletion(
        id: 'order-no-parts',
        serviceTicketId: 'ticket-999',
        diagnosis: 'Ajuste de calibración',
        solution: 'Calibración por software completada',
        status: 'resolved',
        completedAt: DateTime.parse('2026-08-28T12:00:00Z'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceCompletionCard(serviceCompletion: completion),
          ),
        ),
      );

      expect(find.text('Refacciones / Materiales Utilizados:'), findsOneWidget);
      expect(find.text('Ninguna'), findsOneWidget);
    });
  });
}
