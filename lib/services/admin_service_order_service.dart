import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_completion.dart';

/// Servicio administrativo y técnico para la ejecución, consumo de partes y cierre de órdenes de servicio.
class AdminServiceOrderService {
  AdminServiceOrderService(this._supabase);

  final SupabaseClient _supabase;

  /// Valida los campos técnicos requeridos para completar una orden.
  static void validateCompletionInput({
    required String diagnosis,
    required String solution,
  }) {
    if (diagnosis.trim().isEmpty) {
      throw ArgumentError('El diagnóstico técnico final es obligatorio.');
    }
    if (solution.trim().isEmpty) {
      throw ArgumentError(
        'La descripción del trabajo y solución aplicada es obligatoria.',
      );
    }
  }

  /// Valida la información de consumo de refacciones físicas.
  static void validatePartUsage({
    required String serviceOrderId,
    required String productId,
    required String warehouseId,
    required double quantity,
  }) {
    if (serviceOrderId.trim().isEmpty) {
      throw ArgumentError('serviceOrderId requerido.');
    }
    if (productId.trim().isEmpty) {
      throw ArgumentError('productId requerido.');
    }
    if (warehouseId.trim().isEmpty) {
      throw ArgumentError('warehouseId requerido.');
    }
    if (quantity <= 0) {
      throw ArgumentError('La cantidad de refacción debe ser mayor a 0.');
    }
  }

  /// Inicia formalmente la ejecución de una orden de servicio mediante la RPC `start_service_order`.
  Future<Map<String, dynamic>> startServiceOrder({
    required String ticketId,
    String? technicianId,
    DateTime? scheduledAt,
  }) async {
    if (ticketId.trim().isEmpty) {
      throw ArgumentError('ticketId requerido.');
    }

    final params = {
      'p_ticket_id': ticketId.trim(),
      if (technicianId != null && technicianId.trim().isNotEmpty)
        'p_technician_id': technicianId.trim(),
      if (scheduledAt != null)
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
    };

    try {
      final res = await _supabase.rpc('start_service_order', params: params);
      if (res is! Map) {
        throw Exception(
          'Respuesta inesperada al iniciar la orden de servicio.',
        );
      }
      return Map<String, dynamic>.from(res);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      throw Exception('Error al iniciar orden de servicio: $msg');
    }
  }

  /// Registra el consumo físico de una refacción mediante la RPC autoritativa `register_service_part_usage`.
  /// No inserta directamente en inventory_movements.
  Future<void> registerPartUsage({
    required String serviceOrderId,
    required String productId,
    required String warehouseId,
    required double quantity,
    double unitCost = 0.0,
  }) async {
    validatePartUsage(
      serviceOrderId: serviceOrderId,
      productId: productId,
      warehouseId: warehouseId,
      quantity: quantity,
    );

    final params = {
      'p_service_order_id': serviceOrderId.trim(),
      'p_product_id': productId.trim(),
      'p_warehouse_id': warehouseId.trim(),
      'p_quantity': quantity,
      'p_unit_cost': unitCost >= 0 ? unitCost : 0.0,
    };

    try {
      await _supabase.rpc('register_service_part_usage', params: params);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      throw Exception('Error al registrar refacción en almacén: $msg');
    }
  }

  /// Finaliza la orden de servicio y mueve el ticket a `resolved` mediante la RPC `complete_service_order`.
  Future<Map<String, dynamic>> completeServiceOrder({
    required String serviceOrderId,
    required String diagnosis,
    required String solution,
    String? recommendations,
    String? partsUsedNotes,
  }) async {
    if (serviceOrderId.trim().isEmpty) {
      throw ArgumentError('serviceOrderId requerido.');
    }

    validateCompletionInput(diagnosis: diagnosis, solution: solution);

    final params = {
      'p_service_order_id': serviceOrderId.trim(),
      'p_diagnosis': diagnosis.trim(),
      'p_solution': solution.trim(),
      if (recommendations != null && recommendations.trim().isNotEmpty)
        'p_recommendations': recommendations.trim(),
      if (partsUsedNotes != null && partsUsedNotes.trim().isNotEmpty)
        'p_parts_used_notes': partsUsedNotes.trim(),
    };

    try {
      final res = await _supabase.rpc('complete_service_order', params: params);
      if (res is! Map) {
        throw Exception(
          'Respuesta inesperada al completar la orden de servicio.',
        );
      }
      return Map<String, dynamic>.from(res);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      throw Exception('Error al completar la orden de servicio: $msg');
    }
  }

  /// Cierra definitivamente el ticket y la orden de servicio mediante la RPC `close_service_ticket`.
  Future<Map<String, dynamic>> closeServiceTicket({
    required String ticketId,
    String? reason,
  }) async {
    if (ticketId.trim().isEmpty) {
      throw ArgumentError('ticketId requerido.');
    }

    final params = {
      'p_ticket_id': ticketId.trim(),
      if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
    };

    try {
      final res = await _supabase.rpc('close_service_ticket', params: params);
      if (res is! Map) {
        throw Exception('Respuesta inesperada al cerrar el ticket.');
      }
      return Map<String, dynamic>.from(res);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      throw Exception('Error al cerrar el ticket: $msg');
    }
  }

  /// Obtiene los detalles de ejecución técnica vinculados a un ticket.
  Future<ServiceCompletion?> getServiceOrderDetails(String ticketId) async {
    if (ticketId.trim().isEmpty) return null;

    final rows = await _supabase
        .from('service_orders')
        .select('''
          id,
          service_ticket_id,
          assigned_technician_id,
          diagnosis,
          solution,
          recommendations,
          parts_used_notes,
          status,
          scheduled_at,
          started_at,
          completed_at,
          report_pdf_path,
          assigned_technician:assigned_technician_id (
            full_name
          ),
          service_parts_used (
            id,
            service_order_id,
            product_id,
            warehouse_id,
            quantity,
            unit_cost,
            created_at,
            products:product_id (
              name
            )
          )
        ''')
        .eq('service_ticket_id', ticketId.trim())
        .order('updated_at', ascending: false)
        .limit(25);

    final orders = rows
        .whereType<Map<String, dynamic>>()
        .map(ServiceCompletion.fromJson)
        .toList();

    if (orders.isEmpty) return null;

    const activeStatuses = {
      'assigned',
      'in_progress',
      'waiting_parts',
      'paused',
    };
    final activeOrders = orders
        .where((order) => activeStatuses.contains(order.status.toLowerCase()))
        .toList();

    if (activeOrders.length > 1) {
      throw Exception(
        'Se encontraron múltiples órdenes de servicio activas para este ticket. Requiere revisión administrativa.',
      );
    }

    if (activeOrders.length == 1) return activeOrders.first;

    orders.sort((a, b) {
      final aDate = a.completedAt ?? a.startedAt ?? a.scheduledAt;
      final bDate = b.completedAt ?? b.startedAt ?? b.scheduledAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return orders.first;
  }
}
