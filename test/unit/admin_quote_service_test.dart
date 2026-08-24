import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/service_ticket.dart';
import 'package:gomedical_app/services/admin_quote_service.dart';

void main() {
  group('AdminQuoteItemDraft Unit Tests', () {
    test('calculates normal item total line price correctly', () {
      const item = AdminQuoteItemDraft(
        productNameSnapshot: 'Mantenimiento Preventivo',
        quantity: 2,
        unitPrice: 1500.0,
        discount: 300.0,
      );

      expect(item.totalLinePrice, 2700.0);
    });

    test('supports 100% bonified diagnostic concept (total = 0)', () {
      const item = AdminQuoteItemDraft(
        productNameSnapshot: 'Diagnóstico técnico biomédico',
        quantity: 1,
        unitPrice: 1500.0,
        discount: 1500.0,
      );

      expect(item.totalLinePrice, 0.0);
      expect(() => item.validate(), returnsNormally);
    });

    test('rejects discount higher than gross line amount', () {
      const item = AdminQuoteItemDraft(
        productNameSnapshot: 'Calibración',
        quantity: 1,
        unitPrice: 1000.0,
        discount: 1200.0,
      );

      expect(() => item.validate(), throwsA(isA<ArgumentError>()));
    });

    test('rejects negative quantity or zero quantity', () {
      const zeroQty = AdminQuoteItemDraft(
        productNameSnapshot: 'Mantenimiento',
        quantity: 0,
        unitPrice: 1000.0,
      );
      const negQty = AdminQuoteItemDraft(
        productNameSnapshot: 'Mantenimiento',
        quantity: -1,
        unitPrice: 1000.0,
      );

      expect(() => zeroQty.validate(), throwsA(isA<ArgumentError>()));
      expect(() => negQty.validate(), throwsA(isA<ArgumentError>()));
    });

    test('rejects negative unit price or negative discount', () {
      const negPrice = AdminQuoteItemDraft(
        productNameSnapshot: 'Servicio',
        quantity: 1,
        unitPrice: -500.0,
      );
      const negDiscount = AdminQuoteItemDraft(
        productNameSnapshot: 'Servicio',
        quantity: 1,
        unitPrice: 500.0,
        discount: -50.0,
      );

      expect(() => negPrice.validate(), throwsA(isA<ArgumentError>()));
      expect(() => negDiscount.validate(), throwsA(isA<ArgumentError>()));
    });

    test('rejects empty concept name', () {
      const emptyName = AdminQuoteItemDraft(
        productNameSnapshot: '   ',
        quantity: 1,
        unitPrice: 500.0,
      );

      expect(() => emptyName.validate(), throwsA(isA<ArgumentError>()));
    });

    test('toJson sets item fields strictly and omits authority totals or client_id', () {
      const item = AdminQuoteItemDraft(
        productNameSnapshot: 'Mano de Obra',
        quantity: 3,
        unitPrice: 800.0,
        discount: 200.0,
      );

      final payload = item.toJson();

      expect(payload['product_name_snapshot'], 'Mano de Obra');
      expect(payload['quantity'], 3);
      expect(payload['unit_price'], 800.0);
      expect(payload['discount'], 200.0);

      // No debe enviar product_id, client_id ni total_line_price como autoridad
      expect(payload.containsKey('product_id'), isFalse);
      expect(payload.containsKey('client_id'), isFalse);
      expect(payload.containsKey('total_line_price'), isFalse);
    });
  });

  group('AdminQuotePreviewTotals Tests', () {
    test('calculates preview subtotal, tax 16% and total accurately', () {
      final items = [
        const AdminQuoteItemDraft(
          productNameSnapshot: 'Mantenimiento preventivo',
          quantity: 1,
          unitPrice: 3500.0,
          discount: 0.0,
        ),
        const AdminQuoteItemDraft(
          productNameSnapshot: 'Diagnóstico técnico',
          quantity: 1,
          unitPrice: 1500.0,
          discount: 1500.0, // Bonificado
        ),
      ];

      final totals = AdminQuotePreviewTotals.calculate(items, taxPct: 0.16);

      // Subtotal = 3500 + 0 = 3500
      expect(totals.subtotal, 3500.0);
      // Tax = 3500 * 0.16 = 560.0
      expect(totals.tax, 560.0);
      // Total = 3500 + 560 = 4060.0
      expect(totals.total, 4060.0);
    });

    test('handles tax exempt preview totals', () {
      final items = [
        const AdminQuoteItemDraft(
          productNameSnapshot: 'Servicio Exento',
          quantity: 1,
          unitPrice: 2000.0,
        ),
      ];

      final totals = AdminQuotePreviewTotals.calculate(items, taxExempt: true);

      expect(totals.subtotal, 2000.0);
      expect(totals.tax, 0.0);
      expect(totals.total, 2000.0);
    });
  });

  group('AdminQuoteService Editability Tests', () {
    test('isQuoteEditable returns true exclusively for draft', () {
      expect(AdminQuoteService.isQuoteEditable('draft'), isTrue);
      expect(AdminQuoteService.isQuoteEditable('sent'), isFalse);
      expect(AdminQuoteService.isQuoteEditable('approved'), isFalse);
      expect(AdminQuoteService.isQuoteEditable('rejected'), isFalse);
      expect(AdminQuoteService.isQuoteEditable('expired'), isFalse);
      expect(AdminQuoteService.isQuoteEditable('converted'), isFalse);
    });
  });

  group('ServiceTicket Equipment Summary & Quote Integration Tests', () {
    test('resolves equipmentSummary from equipmentName or brand and model', () {
      final ticketWithName = ServiceTicket(
        id: 't-1',
        ticketNumber: 'TCK-20260820-ADDC48CB',
        title: 'Mantenimiento preventivo',
        status: 'assigned',
        priority: 'medium',
        type: 'preventivo',
        createdAt: DateTime.now(),
        equipmentName: 'Electrocardiógrafo Philips PageWriter',
      );
      expect(
        ticketWithName.equipmentSummary,
        'Electrocardiógrafo Philips PageWriter',
      );

      final ticketWithBrandModel = ServiceTicket(
        id: 't-2',
        ticketNumber: 'TCK-20260820-0002',
        title: 'Revisión técnica',
        status: 'open',
        priority: 'high',
        type: 'correctivo',
        createdAt: DateTime.now(),
        equipmentBrand: 'Mindray',
        equipmentModel: 'BeneView T5',
      );
      expect(ticketWithBrandModel.equipmentSummary, 'Mindray BeneView T5');

      final ticketFallback = ServiceTicket(
        id: 't-3',
        ticketNumber: 'TCK-20260820-0003',
        title: 'Servicio general de quirófano',
        status: 'open',
        priority: 'low',
        type: 'otro',
        createdAt: DateTime.now(),
      );
      expect(
        ticketFallback.equipmentSummary,
        'Servicio general de quirófano',
      );
    });
  });
}
