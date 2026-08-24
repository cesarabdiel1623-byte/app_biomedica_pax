import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/tracking_info.dart';
import 'package:gomedical_app/screens/profile/profile_helpers.dart';

void main() {
  group('T5.1/T5.2 tracking presentation', () {
    test('1. delivered shows Entregado and friendly delivered message', () {
      expect(shipmentStatusLabel('delivered'), 'Entregado');
      expect(
        shipmentStatusMessage('delivered'),
        'Tu pedido fue entregado correctamente.',
      );
      expect(
        shipmentEventMessage('delivered'),
        'Tu pedido llegó a su destino.',
      );
    });

    test('2. timeline maps five known events to Spanish labels', () {
      final events = _sandboxEvents();
      expect(events.map((event) => event.displayLabel).toList(), [
        'Entregado',
        'En reparto',
        'En tránsito',
        'Recogido',
        'Guía creada',
      ]);
    });

    test('3. events are loaded newest first from Supabase', () {
      final serviceSource = File(
        'lib/services/tracking_service.dart',
      ).readAsStringSync();

      expect(serviceSource, contains(".order('event_at', ascending: false)"));
    });

    test('4. real location is displayed when present', () {
      final event = ShipmentEvent(
        id: 'event-location',
        shipmentId: 'shipment-1',
        status: 'in_transit',
        location: 'Mérida, Yucatán',
        eventAt: DateTime(2026, 8, 14, 1, 1),
      );

      expect(event.hasLocation, isTrue);
      expect(event.location, 'Mérida, Yucatán');
    });

    test('5. null or blank location does not create fake location', () {
      final withoutLocation = ShipmentEvent(
        id: 'event-no-location',
        shipmentId: 'shipment-1',
        status: 'in_transit',
        eventAt: DateTime(2026, 8, 14, 1, 1),
      );
      final blankLocation = ShipmentEvent(
        id: 'event-blank-location',
        shipmentId: 'shipment-1',
        status: 'in_transit',
        location: '   ',
        eventAt: DateTime(2026, 8, 14, 1, 1),
      );

      expect(withoutLocation.hasLocation, isFalse);
      expect(blankLocation.hasLocation, isFalse);
    });

    test('6. tracking number null is guarded by a null and empty check', () {
      final screenSource = _orderDetailSource();

      expect(
        screenSource,
        contains('if (trackingNumber != null && trackingNumber.isNotEmpty)'),
      );
      expect(screenSource, contains("_buildTrackingNumberRow(trackingNumber)"));
    });

    test('7. tracking number existing shows guide row and copy action', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, contains("'Guía'"));
      expect(screenSource, contains('Clipboard.setData'));
      expect(screenSource, contains("'¡Número de guía copiado!'"));
    });

    test('8. tracking url existing shows external carrier action', () {
      final screenSource = _orderDetailSource();

      expect(
        screenSource,
        contains('if (trackingUrl != null && trackingUrl.isNotEmpty)'),
      );
      expect(screenSource, contains('Rastrear con la paquetería'));
      expect(
        screenSource,
        contains('launchUrl(uri, mode: LaunchMode.externalApplication)'),
      );
    });

    test('9. tracking url null does not show external action by default', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains('Rastrear envío en paquetería')));
      expect(screenSource, isNot(contains('ampm.com')));
      expect(screenSource, isNot(contains('estafeta.com')));
      expect(screenSource, isNot(contains('dhl.com')));
    });

    test('10. AMPM carrier is displayed correctly', () {
      const shipment = OrderShipment(
        id: 'shipment-1',
        orderId: 'order-1',
        carrier: 'ampm',
        shippingStatus: 'delivered',
      );

      expect(shipment.carrierDisplayName, 'AMPM');
    });

    test('11. last update uses real shipment/event date fields', () {
      final modelSource = File(
        'lib/models/tracking_info.dart',
      ).readAsStringSync();
      final screenSource = _orderDetailSource();

      expect(modelSource, contains('updatedAt'));
      expect(modelSource, contains("json['updated_at']"));
      expect(screenSource, contains('events.first.eventAt'));
      expect(screenSource, contains('shipment.updatedAt'));
      expect(screenSource, contains('shipment.createdAt'));
      expect(screenSource, contains('_formatCompactDate(lastUpdate)'));
    });

    test('12. destination is not duplicated inside tracking', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains('_buildDestinationRow')));
      expect(screenSource, isNot(contains('_destinationLabelFromOrder')));
      expect(screenSource, isNot(contains('Ubicación actual')));
      expect(screenSource, contains('Dirección de Envío'));
    });

    test('13. tracking uses a unified 6-process SkyDropX timeline', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains('Guía lista')));
      expect(screenSource, isNot(contains('En proceso')));
      expect(screenSource, isNot(contains('Historial de eventos')));
      expect(screenSource, contains('_buildShipmentProgress(shipment)'));
      expect(screenSource, contains('Movimientos del envío'));
      expect(screenSource, contains('kSkyDropXProcesses'));
    });

    test(
      '14. known technical provider statuses are not visible in timeline UI',
      () {
        final events = _sandboxEvents();
        final labels = events.map((event) => event.displayLabel).join('|');

        expect(labels, isNot(contains('delivered')));
        expect(labels, isNot(contains('out_for_delivery')));
        expect(labels, isNot(contains('in_transit')));
        expect(labels, isNot(contains('picked_up')));
      },
    );

    test('15. Flutter tracking does not call SkyDropX directly', () {
      final trackingSource = File(
        'lib/services/tracking_service.dart',
      ).readAsStringSync();
      final screenSource = _orderDetailSource();

      expect(trackingSource, contains("from('customer_order_shipments')"));
      expect(trackingSource, contains("from('customer_shipment_events')"));
      expect(trackingSource, isNot(contains('functions.invoke')));
      expect(screenSource, isNot(contains('skydropx-mobile-quote')));
      expect(screenSource, isNot(contains('/api/v1/shipments')));
    });

    test(
      '16. timeline uses content-driven layout instead of fixed row heights',
      () {
        final screenSource = _orderDetailSource();

        expect(screenSource, contains('IntrinsicHeight'));
        expect(screenSource, contains('Positioned('));
        expect(screenSource, isNot(contains('event.hasLocation ? 82 : 68')));
      },
    );

    test(
      '17. ORD-20260813-B39D1569 sandbox case works without guide or url',
      () {
        const shipment = OrderShipment(
          id: 'shipment-ord',
          orderId: 'order-ord',
          carrier: 'ampm',
          trackingNumber: null,
          trackingUrl: null,
          shippingStatus: 'delivered',
        );
        final screenSource = _orderDetailSource();

        expect(shipment.carrierDisplayName, 'AMPM');
        expect(shipment.statusLabel, 'Entregado');
        expect(shipment.trackingNumber, isNull);
        expect(shipment.trackingUrl, isNull);
        expect(screenSource, contains('_buildShipmentProgress(shipment)'));
        expect(
          screenSource,
          contains('if (trackingUrl != null && trackingUrl.isNotEmpty)'),
        );
      },
    );
  });

  group('T5.2 payment and compact shipment states', () {
    test('1. payment approved maps to Pago aprobado in payment summary', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, contains("case 'approved':"));
      expect(screenSource, contains('Pago aprobado'));
      expect(screenSource, contains('_buildPaymentStatusBanner(o)'));
    });

    test('2. delivered shipping remains Entregado', () {
      expect(shipmentStatusLabel('delivered'), 'Entregado');
      expect(
        shipmentCompactStatusMessage('delivered'),
        'Tu pedido fue entregado.',
      );
    });

    test('3. payment and shipping use distinct labels/components', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, contains('Resumen de Pago'));
      expect(screenSource, contains('Seguimiento del envío'));
      expect(screenSource, contains('_paymentStatusLabel(status)'));
      expect(screenSource, contains('shipment.statusLabel'));
    });

    test('3b. payment status does not show raw card/provider text', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains('_paymentProviderLabel')));
      expect(screenSource, isNot(contains("order['payment_method']")));
      expect(screenSource, isNot(contains("order['provider_name']")));
    });

    test('4. order status badge is removed from the order header', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains('Estado del Pedido')));
      expect(screenSource, isNot(contains("_statusLabel(o['status']")));
      expect(screenSource, contains(r'Realizado el $dateStr'));
    });

    test('5. progress maps guide created statuses (Step 0)', () {
      expect(shipmentProgressStepLabel('created'), 'Guía creada');
      expect(shipmentProgressStepLabel('label_created'), 'Guía creada');
      expect(shipmentProgressStepLabel('pending'), 'Guía creada');
      expect(shipmentProgressStepIndex('label_created'), 0);
    });

    test('6. progress maps ready to ship status (Step 1)', () {
      expect(shipmentProgressStepLabel('ready_to_ship'), 'Listo para envío');
      expect(shipmentProgressStepLabel('listo_para_envio'), 'Listo para envío');
      expect(shipmentProgressStepIndex('ready_to_ship'), 1);
    });

    test('7. progress maps picked up statuses (Step 2)', () {
      expect(shipmentProgressStepLabel('picked_up'), 'Recogido');
      expect(shipmentProgressStepLabel('recolectado'), 'Recogido');
      expect(shipmentProgressStepIndex('picked_up'), 2);
    });

    test('8. progress maps in transit statuses (Step 3)', () {
      expect(shipmentProgressStepLabel('in_transit'), 'En tránsito');
      expect(shipmentProgressStepLabel('en_camino'), 'En tránsito');
      expect(shipmentProgressStepIndex('in_transit'), 3);
    });

    test('9. progress maps out for delivery statuses (Step 4)', () {
      expect(shipmentProgressStepLabel('out_for_delivery'), 'En reparto');
      expect(shipmentProgressStepLabel('last_mile'), 'En reparto');
      expect(shipmentProgressStepIndex('out_for_delivery'), 4);
    });

    test('10. progress maps delivered status (Step 5)', () {
      expect(shipmentProgressStepLabel('delivered'), 'Entregado');
      expect(shipmentProgressStepIndex('delivered'), 5);
    });

    test('11. tracking destination duplicate is removed', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains("'Destino'")));
      expect(screenSource, contains('Dirección de Envío'));
    });

    test('12. tracking url behavior still uses stored external URL only', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, contains('Rastrear con la paquetería'));
      expect(screenSource, contains('Uri.tryParse(trackingUrl)'));
      expect(screenSource, isNot(contains('ampm.com')));
    });

    test('13. tracking number behavior still supports guide and copy', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, contains("_buildTrackingNumberRow(trackingNumber)"));
      expect(screenSource, contains('Clipboard.setData'));
    });

    test('14. payment summary does not show separated IVA amount', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains("_summaryRow('IVA incluido'")));
      expect(screenSource, contains('Los precios incluyen IVA.'));
    });

    test('15. total remains the stored order total', () {
      final breakdown = buildIncludedVatOrderPaymentBreakdown(
        subtotal: 12343,
        total: 12343,
        storedTax: 1702.48,
        customerShippingAmount: 0,
      );

      expect(breakdown.total, 12343.0);
    });

    test('16. payment amount is not recalculated in the order detail UI', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, contains('formatCurrency(paymentBreakdown.total)'));
      expect(screenSource, isNot(contains('paymentBreakdown.products +')));
    });

    test('17. shipping status DB value is not changed by Flutter UI', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains("shippingStatus =")));
      expect(screenSource, isNot(contains("shipping_status'] =")));
    });

    test('18. orders.status DB value is not changed by Flutter UI', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains("o['status'] =")));
      expect(screenSource, isNot(contains("order['status'] =")));
    });
  });

  group('T5 payment summary remains intact', () {
    test(
      'ORD-20260813-B39D1569 products = 12343, shipping = 0, total = 12343',
      () {
        final breakdown = buildIncludedVatOrderPaymentBreakdown(
          subtotal: 12343,
          total: 12343,
          storedTax: 1702.48,
          customerShippingAmount: 0,
        );

        expect(breakdown.products, 12343.0);
        expect(breakdown.shipping, 0.0);
        expect(breakdown.total, 12343.0);
      },
    );

    test('separate IVA amount row stays removed from order detail', () {
      final screenSource = _orderDetailSource();

      expect(screenSource, isNot(contains("_summaryRow('IVA incluido'")));
      expect(screenSource, contains('Los precios incluyen IVA.'));
    });
  });
}

List<ShipmentEvent> _sandboxEvents() {
  return [
    ShipmentEvent(
      id: 'event-delivered',
      shipmentId: 'shipment-1',
      status: 'delivered',
      description: 'delivered',
      eventAt: DateTime(2026, 8, 14, 1, 3),
    ),
    ShipmentEvent(
      id: 'event-out',
      shipmentId: 'shipment-1',
      status: 'out_for_delivery',
      description: 'out_for_delivery',
      eventAt: DateTime(2026, 8, 14, 1, 2),
    ),
    ShipmentEvent(
      id: 'event-transit',
      shipmentId: 'shipment-1',
      status: 'in_transit',
      description: 'in_transit',
      eventAt: DateTime(2026, 8, 14, 1, 1),
    ),
    ShipmentEvent(
      id: 'event-picked',
      shipmentId: 'shipment-1',
      status: 'picked_up',
      description: 'picked_up',
      eventAt: DateTime(2026, 8, 14, 1),
    ),
    ShipmentEvent(
      id: 'event-created',
      shipmentId: 'shipment-1',
      status: 'label_created',
      description: 'CREADO',
      eventAt: DateTime(2026, 8, 14, 0, 59),
    ),
  ];
}

String _orderDetailSource() {
  return File(
    'lib/screens/profile/order_detail_screen.dart',
  ).readAsStringSync();
}
