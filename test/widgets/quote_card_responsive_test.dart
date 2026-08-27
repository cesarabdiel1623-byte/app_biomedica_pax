import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/quote.dart';

void main() {
  group('Quote Card Header Responsive Tests', () {
    testWidgets(
      'Header renders without overflow on a 320px narrow mobile viewport',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final quote = ServiceQuote(
          id: 'quote-123',
          quoteNumber: 'QTE-20260824-EB2EF7C8',
          serviceTicketId: 'ticket-456',
          clientId: 'client-789',
          status: 'converted',
          subtotal: 1450.0,
          taxPct: 0.16,
          taxExempt: false,
          tax: 232.0,
          total: 1682.0,
          validUntil: DateTime(2026, 8, 24),
          items: const [
            ServiceQuoteLineItem(
              id: 'item-1',
              quoteId: 'quote-123',
              productNameSnapshot: 'Mantenimiento preventivo biomédico',
              quantity: 1,
              unitPrice: 1450.0,
              discount: 0.0,
              totalLinePrice: 1450.0,
            ),
          ],
        );

        const statusColor = Color(0xFF16A34A);
        const validStr = '24 Ago 2026';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.request_quote_outlined,
                                color: Color(0xFF007BFF),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'COTIZACIÓN DE SERVICIO',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(
                                quote.quoteNumber,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.event_outlined,
                                          size: 13,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                    const TextSpan(
                                      text: 'Válida hasta: $validStr',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  quote.statusLabel.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Verify no RenderFlex overflow exceptions occurred
        expect(tester.takeException(), isNull);
        expect(find.text('COTIZACIÓN DE SERVICIO'), findsOneWidget);
        expect(find.text('CONVERTIDA'), findsOneWidget);
        expect(find.text('QTE-20260824-EB2EF7C8'), findsOneWidget);
        expect(
          find.textContaining('Válida hasta: 24 Ago 2026'),
          findsOneWidget,
        );
      },
    );
  });
}
