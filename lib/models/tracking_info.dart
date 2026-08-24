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

  String get displayLabel {
    final descriptionLabel = shipmentStatusLabel(description);
    if (descriptionLabel != null) return descriptionLabel;

    final statusLabel = shipmentStatusLabel(status);
    if (statusLabel != null) return statusLabel;

    final safeDescription = description?.trim();
    if (safeDescription != null && safeDescription.isNotEmpty) {
      return safeDescription;
    }

    return status.trim().isEmpty ? 'Evento de envío' : status;
  }

  String get uiDescription {
    return shipmentEventMessage(status) ??
        shipmentEventMessage(description) ??
        shipmentStatusMessage(status) ??
        shipmentStatusMessage(description) ??
        'Se registró una actualización del envío.';
  }

  bool get hasLocation => location?.trim().isNotEmpty == true;
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
  final DateTime? createdAt;
  final DateTime? updatedAt;
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
    this.createdAt,
    this.updatedAt,
    this.events = const [],
  });

  String get carrierDisplayName {
    if (carrier == null || carrier!.trim().isEmpty) return 'Paquetería';
    final c = carrier!.trim().toLowerCase();
    if (c.contains('ampm')) return 'AMPM';
    if (c.contains('fedex')) return 'FedEx';
    if (c.contains('estafeta')) return 'Estafeta';
    if (c.contains('dhl')) return 'DHL Express';
    if (c.contains('99minutos')) return '99minutos';
    if (c.contains('sendex')) return 'Sendex';
    if (c.contains('redpack')) return 'Redpack';
    return carrier![0].toUpperCase() + carrier!.substring(1);
  }

  String get statusLabel {
    final knownLabel = shipmentStatusLabel(shippingStatus);
    if (knownLabel != null) return knownLabel;

    switch (shippingStatus.toLowerCase()) {
      case 'pending':
        return 'En preparación';
      case 'ready_to_ship':
        return 'Listo para envío';
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
      case 'last_mile':
      case 'ready_to_ship':
        return Colors.blue;
      case 'created':
      case 'pending':
      case 'label_created':
        return kOrange;
      case 'exception':
      case 'failed':
      case 'canceled':
      case 'cancelled':
        return kRed;
      case 'returned':
        return Colors.deepOrange;
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
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal()
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())?.toLocal()
          : null,
      events: events,
    );
  }
}

const List<String> kSkyDropXProcesses = [
  'Guía creada',
  'Listo para envío',
  'Recogido',
  'En tránsito',
  'En reparto',
  'Entregado',
];

String? shipmentProgressStepLabel(String? value) {
  final key = _normalizeShipmentStatus(value);
  switch (key) {
    case 'created':
    case 'creado':
    case 'label_created':
    case 'pending':
    case 'pendiente':
    case 'en_preparacion':
      return 'Guía creada';
    case 'ready_to_ship':
    case 'listo_para_envio':
      return 'Listo para envío';
    case 'picked_up':
    case 'recogido':
    case 'recolectado':
      return 'Recogido';
    case 'in_transit':
    case 'en_transito':
    case 'en_camino':
      return 'En tránsito';
    case 'out_for_delivery':
    case 'last_mile':
    case 'en_reparto':
      return 'En reparto';
    case 'delivered':
    case 'entregado':
      return 'Entregado';
    default:
      return null;
  }
}

int shipmentProgressStepIndex(String? value) {
  switch (shipmentProgressStepLabel(value)) {
    case 'Guía creada':
      return 0;
    case 'Listo para envío':
      return 1;
    case 'Recogido':
      return 2;
    case 'En tránsito':
      return 3;
    case 'En reparto':
      return 4;
    case 'Entregado':
      return 5;
    default:
      return -1;
  }
}

String? shipmentCompactStatusMessage(String? value) {
  final label = shipmentStatusLabel(value);
  switch (label) {
    case 'Guía creada':
    case 'Listo para envío':
      return 'Estamos preparando tu envío.';
    case 'Recogido':
    case 'En tránsito':
      return 'Tu paquete está en camino.';
    case 'En reparto':
      return 'Tu paquete salió a entrega.';
    case 'Entregado':
      return 'Tu pedido fue entregado.';
    case 'Incidencia':
      return 'Hay una incidencia con el envío.';
    case 'Cancelado':
      return 'El envío fue cancelado.';
    case 'Devuelto':
      return 'El paquete está en devolución.';
    default:
      return null;
  }
}

String? shipmentStatusMessage(String? value) {
  final label = shipmentStatusLabel(value);
  switch (label) {
    case 'Guía creada':
      return 'Tu envío fue preparado y está listo para ser recolectado.';
    case 'Listo para envío':
      return 'Tu paquete está listo para ser entregado a la paquetería.';
    case 'Recogido':
      return 'La paquetería recibió tu paquete.';
    case 'En tránsito':
      return 'Tu paquete está en camino.';
    case 'En reparto':
      return 'Tu paquete salió a ruta de entrega.';
    case 'Entregado':
      return 'Tu pedido fue entregado correctamente.';
    case 'Incidencia':
      return 'Se reportó una incidencia con el envío.';
    case 'Cancelado':
      return 'El envío fue cancelado.';
    case 'Devuelto':
      return 'El paquete está en proceso de devolución.';
    default:
      return null;
  }
}

String? shipmentEventMessage(String? value) {
  final label = shipmentStatusLabel(value);
  switch (label) {
    case 'Guía creada':
      return 'El envío fue preparado.';
    case 'Listo para envío':
      return 'Tu paquete está listo para paquetería.';
    case 'Recogido':
      return 'La paquetería recibió tu paquete.';
    case 'En tránsito':
      return 'Tu paquete está en camino.';
    case 'En reparto':
      return 'La paquetería salió a entregar tu pedido.';
    case 'Entregado':
      return 'Tu pedido llegó a su destino.';
    case 'Incidencia':
      return 'Se reportó una incidencia con el envío.';
    case 'Cancelado':
      return 'El envío fue cancelado.';
    case 'Devuelto':
      return 'El paquete está en proceso de devolución.';
    default:
      return null;
  }
}

String? shipmentStatusLabel(String? value) {
  final key = _normalizeShipmentStatus(value);
  switch (key) {
    case 'created':
    case 'creado':
    case 'label_created':
      return 'Guía creada';
    case 'ready_to_ship':
    case 'listo_para_envio':
      return 'Listo para envío';
    case 'picked_up':
    case 'recogido':
    case 'recolectado':
      return 'Recogido';
    case 'in_transit':
    case 'en_transito':
    case 'en_camino':
      return 'En tránsito';
    case 'out_for_delivery':
    case 'last_mile':
    case 'en_reparto':
      return 'En reparto';
    case 'delivered':
    case 'entregado':
      return 'Entregado';
    case 'canceled':
    case 'cancelled':
    case 'cancelado':
      return 'Cancelado';
    case 'returned':
    case 'devuelto':
      return 'Devuelto';
    case 'exception':
    case 'failed':
    case 'incidencia':
      return 'Incidencia';
    case 'pending':
    case 'pendiente':
    case 'en_preparacion':
      return 'En preparación';
    default:
      return null;
  }
}

String _normalizeShipmentStatus(String? value) {
  return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
}
