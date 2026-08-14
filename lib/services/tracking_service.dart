import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tracking_info.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene el registro de envío y sus eventos para una orden desde las vistas seguras
  static Future<OrderShipment?> getShipmentForOrder(String orderId) async {
    if (_supabase.auth.currentSession == null) return null;

    try {
      final shipmentData = await _supabase
          .from('customer_order_shipments')
          .select()
          .eq('order_id', orderId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (shipmentData == null) return null;

      final shipmentId = shipmentData['id'] as String;

      final eventsData = await _supabase
          .from('customer_shipment_events')
          .select()
          .eq('shipment_id', shipmentId)
          .order('event_at', ascending: false);

      final events = (eventsData as List)
          .map((e) => ShipmentEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      return OrderShipment.fromJson(
        Map<String, dynamic>.from(shipmentData),
        events: events,
      );
    } catch (_) {
      // Manejo seguro en caso de falla de red o vista no disponible
      return null;
    }
  }
}
