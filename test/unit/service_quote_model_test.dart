import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/quote.dart';

void main() {
  group('ServiceQuoteLineItem JSON parsing', () {
    test('parses normal item with discount correctly', () {
      final json = {
        'id': 'line-1',
        'quote_id': 'quote-1',
        'product_id': null,
        'sku_snapshot': 'SRV-MNT',
        'product_name_snapshot': 'Mantenimiento Preventivo',
        'product_category_snapshot': null,
        'quantity': 1,
        'unit_price': 1500.0,
        'discount': 500.0,
        'total_line_price': 1000.0,
        'created_at': '2026-08-18T12:00:00Z',
      };

      final item = ServiceQuoteLineItem.fromJson(json);

      expect(item.id, 'line-1');
      expect(item.quoteId, 'quote-1');
      expect(item.productId, isNull);
      expect(item.skuSnapshot, 'SRV-MNT');
      expect(item.productNameSnapshot, 'Mantenimiento Preventivo');
      expect(item.quantity, 1.0);
      expect(item.unitPrice, 1500.0);
      expect(item.discount, 500.0);
      expect(item.totalLinePrice, 1000.0);
      expect(item.hasDiscount, isTrue);
    });

    test('handles zero discount correctly', () {
      final json = {
        'id': 'line-2',
        'quote_id': 'quote-1',
        'product_name_snapshot': 'Refacción especial',
        'quantity': 2,
        'unit_price': 400.0,
        'discount': 0,
        'total_line_price': 800.0,
      };

      final item = ServiceQuoteLineItem.fromJson(json);

      expect(item.quantity, 2.0);
      expect(item.unitPrice, 400.0);
      expect(item.discount, 0.0);
      expect(item.totalLinePrice, 800.0);
      expect(item.hasDiscount, isFalse);
    });

    test('parses numeric strings and null monetary fields safely', () {
      final item = ServiceQuoteLineItem.fromJson({
        'id': 'line-3',
        'quote_id': 'quote-1',
        'product_name_snapshot': 'Diagnóstico técnico',
        'quantity': '15',
        'unit_price': '15.50',
        'discount': null,
        'total_line_price': '232.50',
      });

      expect(item.quantity, 15.0);
      expect(item.unitPrice, 15.5);
      expect(item.discount, 0.0);
      expect(item.totalLinePrice, 232.5);
    });
  });

  group('ServiceQuote JSON parsing & getters', () {
    test('parses full ServiceQuote with nested items and status helpers', () {
      final json = {
        'id': 'quote-100',
        'quote_number': 'COT-20260818-001',
        'client_id': 'client-uuid',
        'client_name_snapshot': 'Hospital Central',
        'status': 'sent',
        'subtotal': 4500.0,
        'tax_pct': 0.16,
        'tax_exempt': false,
        'tax': 720.0,
        'total': 5220.0,
        'valid_until': '2026-08-25',
        'notes': 'Diagnóstico bonificado en mantenimiento mayor.',
        'service_ticket_id': 'ticket-uuid',
        'converted_order_id': null,
        'created_at': '2026-08-18T10:00:00Z',
        'updated_at': '2026-08-18T10:30:00Z',
        'quote_items': [
          {
            'id': 'line-1',
            'quote_id': 'quote-100',
            'product_name_snapshot': 'Diagnóstico técnico',
            'quantity': 1,
            'unit_price': 1500.0,
            'discount': 1500.0,
            'total_line_price': 0.0,
          },
          {
            'id': 'line-2',
            'quote_id': 'quote-100',
            'product_name_snapshot': 'Mantenimiento Mayor',
            'quantity': 1,
            'unit_price': 4500.0,
            'discount': 0.0,
            'total_line_price': 4500.0,
          },
        ],
      };

      final quote = ServiceQuote.fromJson(json);

      expect(quote.id, 'quote-100');
      expect(quote.quoteNumber, 'COT-20260818-001');
      expect(quote.clientId, 'client-uuid');
      expect(quote.status, 'sent');
      expect(quote.statusLabel, 'Enviada');
      expect(quote.isSent, isTrue);
      expect(quote.isActionable, isTrue);
      expect(quote.isApproved, isFalse);
      expect(quote.isConverted, isFalse);
      expect(quote.subtotal, 4500.0);
      expect(quote.tax, 720.0);
      expect(quote.total, 5220.0);
      expect(quote.serviceTicketId, 'ticket-uuid');
      expect(quote.items.length, 2);
      expect(quote.hasAnyDiscount, isTrue);
      expect(quote.totalLineDiscount, 1500.0);
      expect(quote.items[0].totalLinePrice, 0.0);
      expect(quote.items[1].totalLinePrice, 4500.0);
    });

    test('statusLabel and helper boolean tests', () {
      final statuses = {
        'draft': 'Borrador',
        'sent': 'Enviada',
        'approved': 'Aprobada',
        'rejected': 'Rechazada',
        'expired': 'Vencida',
        'converted': 'Convertida',
      };

      for (final entry in statuses.entries) {
        final quote = ServiceQuote(
          id: 'q',
          quoteNumber: 'Q',
          clientId: 'c',
          status: entry.key,
          subtotal: 0,
          taxPct: 0.16,
          taxExempt: false,
          tax: 0,
          total: 0,
        );
        expect(quote.statusLabel, entry.value);
        expect(quote.isDraft, entry.key == 'draft');
        expect(quote.isSent, entry.key == 'sent');
        expect(quote.isApproved, entry.key == 'approved');
        expect(quote.isRejected, entry.key == 'rejected');
        expect(quote.isExpired, entry.key == 'expired');
        expect(quote.isConverted, entry.key == 'converted');
      }
    });

    test('parses numeric strings and dynamic-key quote_items maps', () {
      final quote = ServiceQuote.fromJson({
        'id': 'quote-string-numbers',
        'quote_number': 'COT-STR',
        'client_id': 'client-uuid',
        'status': 'approved',
        'subtotal': '15',
        'tax_pct': '0.16',
        'tax': '2.48',
        'total': '17.48',
        'quote_items': <Map<dynamic, dynamic>>[
          {
            'id': 'line-dynamic',
            'quote_id': 'quote-string-numbers',
            'product_name_snapshot': 'Concepto',
            'quantity': '1',
            'unit_price': '15.00',
            'discount': '0',
            'total_line_price': '15.00',
          },
        ],
      });

      expect(quote.subtotal, 15.0);
      expect(quote.taxPct, 0.16);
      expect(quote.tax, 2.48);
      expect(quote.total, 17.48);
      expect(quote.items, hasLength(1));
      expect(quote.items.first.unitPrice, 15.0);
    });
  });
}
