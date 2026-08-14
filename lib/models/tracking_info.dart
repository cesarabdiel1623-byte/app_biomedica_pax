import 'package:flutter/material.dart';
import '../screens/profile/profile_helpers.dart';

class ShipmentEvent {
  final String id;
  final String shipmentId;
  final String status;
  final String? description;
  final String? location;
  final DateTime eventAt;

  const ShipmentEvent({
    required this.id,
    required this.shipmentId,
    required this.status,
    this.description,
    this.location,
    required this.eventAt,
  });

  factory ShipmentEvent.fromJson(Map<String, dynamic> json) {
    return ShipmentEvent(
      id: json['id']?.toString() ?? '',
      shipmentId: json['shipment_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      description: json['description']?.toString(),
      location: json['location']?.toString(),
      eventAt: json['event_at'] != null
          ? DateTime.tryParse(json['event_at'].toString())?.toLocal() ??
                DateTime.now()
          : DateTime.now(),
    );
  }
}

class OrderShipment {
  final String id;
  final String orderId;
  final String? carrier;
  final String? serviceName;
  final String? trackingNumber;
  final String? trackingUrl;
  final String shippingStatus;
  final DateTime? estimatedDelivery;
  final List<ShipmentEvent> events;

  const OrderShipment({
    required this.id,
    required this.orderId,
    this.carrier,
    this.serviceName,
    this.trackingNumber,
    this.trackingUrl,
    required this.shippingStatus,
    this.estimatedDelivery,
    this.events = const [],
  });

  String get carrierDisplayName {
    if (carrier == null || carrier!.trim().isEmpty) return 'Paquetería';
    final c = carrier!.trim().toLowerCase();
    if (c.contains('fedex')) return 'FedEx';
    if (c.contains('estafeta')) return 'Estafeta';
    if (c.contains('dhl')) return 'DHL Express';
    if (c.contains('99minutos')) return '99minutos';
    if (c.contains('sendex')) return 'Sendex';
    if (c.contains('redpack')) return 'Redpack';
    return carrier![0].toUpperCase() + carrier!.substring(1);
  }

  String get statusLabel {
    switch (shippingStatus.toLowerCase()) {
      case 'pending':
        return 'En preparación';
      case 'label_created':
        return 'Guía generada';
      case 'ready_to_ship':
        return 'Listo para envío';
      case 'picked_up':
      case 'in_transit':
        return 'En camino';
      case 'out_for_delivery':
        return 'En reparto';
      case 'delivered':
        return 'Entregado';
      case 'exception':
        return 'Incidencia';
      case 'canceled':
        return 'Cancelado';
      default:
        return shippingStatus;
    }
  }

  Color get statusColor {
    switch (shippingStatus.toLowerCase()) {
      case 'delivered':
        return kGreen;
      case 'picked_up':
      case 'in_transit':
      case 'out_for_delivery':
      case 'ready_to_ship':
        return Colors.blue;
      case 'pending':
      case 'label_created':
        return kOrange;
      case 'exception':
      case 'canceled':
        return kRed;
      default:
        return Colors.grey;
    }
  }

  factory OrderShipment.fromJson(
    Map<String, dynamic> json, {
    List<ShipmentEvent> events = const [],
  }) {
    return OrderShipment(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      carrier: json['carrier']?.toString(),
      serviceName: json['service_name']?.toString(),
      trackingNumber: json['tracking_number']?.toString(),
      trackingUrl: json['tracking_url']?.toString(),
      shippingStatus: json['shipping_status']?.toString() ?? 'pending',
      estimatedDelivery: json['estimated_delivery'] != null
          ? DateTime.tryParse(json['estimated_delivery'].toString())?.toLocal()
          : null,
      events: events,
    );
  }
}
