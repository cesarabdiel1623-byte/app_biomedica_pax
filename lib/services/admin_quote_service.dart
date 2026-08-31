import 'package:supabase_flutter/supabase_flutter.dart';

/// Representa una partida en borrador para una cotización administrativa de servicio.
class AdminQuoteItemDraft {
  final String productNameSnapshot;
  final double quantity;
  final double unitPrice;
  final double discount;

  const AdminQuoteItemDraft({
    required this.productNameSnapshot,
    this.quantity = 1.0,
    this.unitPrice = 0.0,
    this.discount = 0.0,
  });

  /// Total visual estimado por partida (Cálculo cliente solo para PREVIEW).
  /// El total oficial en BD es calculado por el trigger `trg_quote_items_line_total`.
  double get totalLinePrice {
    final gross = quantity * unitPrice;
    final net = gross - discount;
    return net < 0 ? 0.0 : net;
  }

  /// Validación estricta de valores antes de enviar a BD.
  void validate() {
    if (productNameSnapshot.trim().isEmpty) {
      throw ArgumentError('La descripción del concepto no puede estar vacía.');
    }
    if (quantity <= 0) {
      throw ArgumentError('La cantidad debe ser mayor a 0.');
    }
    if (unitPrice < 0) {
      throw ArgumentError('El precio unitario no puede ser negativo.');
    }
    if (discount < 0) {
      throw ArgumentError('El descuento no puede ser negativo.');
    }
    if (discount > (quantity * unitPrice)) {
      throw ArgumentError(
        'El descuento no puede ser mayor al importe bruto de la partida ($quantity x $unitPrice).',
      );
    }
  }

  /// Payload seguro para enviar a la RPC `create_service_quote`.
  /// `product_id` y `total_line_price` no se envían desde Flutter (gestionados en BD).
  Map<String, dynamic> toJson() {
    validate();
    return {
      'product_name_snapshot': productNameSnapshot.trim(),
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
    };
  }
}

/// Totales de previsualización cliente en Flutter.
/// Los valores definitivos provienen del trigger `trg_quote_items_recalculate` en PostgreSQL.
class AdminQuotePreviewTotals {
  final double subtotal;
  final double tax;
  final double total;

  const AdminQuotePreviewTotals({
    required this.subtotal,
    required this.tax,
    required this.total,
  });

  factory AdminQuotePreviewTotals.calculate(
    List<AdminQuoteItemDraft> items, {
    double taxPct = 0.16,
    bool taxExempt = false,
  }) {
    final subtotal = items.fold<double>(
      0.0,
      (sum, item) => sum + item.totalLinePrice,
    );
    final tax = taxExempt ? 0.0 : (subtotal * taxPct);
    final total = subtotal + tax;

    return AdminQuotePreviewTotals(
      subtotal: double.parse(subtotal.toStringAsFixed(2)),
      tax: double.parse(tax.toStringAsFixed(2)),
      total: double.parse(total.toStringAsFixed(2)),
    );
  }
}

/// Servicio administrativo para la creación y gestión de cotizaciones de servicio.
/// Separado del TicketService del cliente. Utiliza RPCs autoritativas atómicas.
class AdminQuoteService {
  AdminQuoteService(this._supabase);

  final SupabaseClient _supabase;

  /// Valida que el estado permita edición administrativa.
  static bool isQuoteEditable(String status) {
    return status.toLowerCase() == 'draft';
  }

  /// Crea una cotización de servicio atómica y transaccional mediante la RPC `create_service_quote`.
  /// El `client_id` se deriva exclusivamente del ticket en backend.
  Future<Map<String, dynamic>> createServiceQuoteDraft({
    required String serviceTicketId,
    required List<AdminQuoteItemDraft> items,
    DateTime? validUntil,
    String? notes,
    bool taxExempt = false,
  }) async {
    if (serviceTicketId.trim().isEmpty) {
      throw ArgumentError('Se requiere serviceTicketId.');
    }
    if (items.isEmpty) {
      throw ArgumentError(
        'Debes agregar al menos un concepto a la cotización.',
      );
    }

    for (final item in items) {
      item.validate();
    }

    final params = {
      'p_ticket_id': serviceTicketId.trim(),
      'p_items': items.map((i) => i.toJson()).toList(),
      if (validUntil != null)
        'p_valid_until': validUntil.toIso8601String().split('T').first,
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      'p_tax_exempt': taxExempt,
    };

    try {
      final res = await _supabase.rpc('create_service_quote', params: params);
      if (res is! Map) {
        throw Exception('Respuesta inesperada al crear la cotización.');
      }
      return Map<String, dynamic>.from(res);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      throw Exception('Error al crear la cotización: $msg');
    }
  }

  /// Envía la cotización formalmente al cliente mediante la RPC autoritativa `send_service_quote`.
  Future<Map<String, dynamic>> sendServiceQuote({
    required String quoteId,
  }) async {
    if (quoteId.trim().isEmpty) {
      throw ArgumentError('quoteId requerido.');
    }

    try {
      final res = await _supabase.rpc(
        'send_service_quote',
        params: {'p_quote_id': quoteId.trim()},
      );

      if (res is! Map) {
        throw Exception('Respuesta inesperada al enviar la cotización.');
      }

      return Map<String, dynamic>.from(res);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      throw Exception('Error al enviar la cotización: $msg');
    }
  }
}
