import 'package:flutter/foundation.dart';

double _doubleFromJson(
  Object? value, {
  required double fallback,
}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

@immutable
class ServiceQuoteLineItem {
  final String id;
  final String quoteId;
  final String? productId;
  final String? skuSnapshot;
  final String productNameSnapshot;
  final String? productCategorySnapshot;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double totalLinePrice;
  final DateTime? createdAt;

  const ServiceQuoteLineItem({
    required this.id,
    required this.quoteId,
    this.productId,
    this.skuSnapshot,
    required this.productNameSnapshot,
    this.productCategorySnapshot,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.totalLinePrice,
    this.createdAt,
  });

  bool get hasDiscount => discount > 0.0001;

  factory ServiceQuoteLineItem.fromJson(Map<String, dynamic> json) {
    return ServiceQuoteLineItem(
      id: json['id']?.toString() ?? '',
      quoteId: json['quote_id']?.toString() ?? '',
      productId: json['product_id']?.toString(),
      skuSnapshot: json['sku_snapshot']?.toString(),
      productNameSnapshot:
          json['product_name_snapshot']?.toString() ?? 'Concepto de servicio',
      productCategorySnapshot: json['product_category_snapshot']?.toString(),
      quantity: _doubleFromJson(json['quantity'], fallback: 1.0),
      unitPrice: _doubleFromJson(json['unit_price'], fallback: 0.0),
      discount: _doubleFromJson(json['discount'], fallback: 0.0),
      totalLinePrice: _doubleFromJson(
        json['total_line_price'],
        fallback: 0.0,
      ),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quote_id': quoteId,
      'product_id': productId,
      'sku_snapshot': skuSnapshot,
      'product_name_snapshot': productNameSnapshot,
      'product_category_snapshot': productCategorySnapshot,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'total_line_price': totalLinePrice,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

@immutable
class ServiceQuote {
  final String id;
  final String quoteNumber;
  final String clientId;
  final String? clientNameSnapshot;
  final String status;
  final double subtotal;
  final double taxPct;
  final bool taxExempt;
  final double tax;
  final double total;
  final DateTime? validUntil;
  final String? notes;
  final String? pdfPath;
  final String? serviceTicketId;
  final String? convertedOrderId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ServiceQuoteLineItem> items;

  const ServiceQuote({
    required this.id,
    required this.quoteNumber,
    required this.clientId,
    this.clientNameSnapshot,
    required this.status,
    required this.subtotal,
    required this.taxPct,
    required this.taxExempt,
    required this.tax,
    required this.total,
    this.validUntil,
    this.notes,
    this.pdfPath,
    this.serviceTicketId,
    this.convertedOrderId,
    this.createdAt,
    this.updatedAt,
    this.items = const [],
  });

  bool get isDraft => status.toLowerCase() == 'draft';
  bool get isSent => status.toLowerCase() == 'sent';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';
  bool get isExpired => status.toLowerCase() == 'expired';
  bool get isConverted => status.toLowerCase() == 'converted';

  bool get isActionable => isSent;

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'Borrador';
      case 'sent':
        return 'Enviada';
      case 'approved':
        return 'Aprobada';
      case 'rejected':
        return 'Rechazada';
      case 'expired':
        return 'Vencida';
      case 'converted':
        return 'Convertida';
      default:
        return status;
    }
  }

  double get totalLineDiscount =>
      items.fold(0.0, (sum, item) => sum + item.discount);

  bool get hasAnyDiscount => totalLineDiscount > 0.0001;

  factory ServiceQuote.fromJson(
    Map<String, dynamic> json, {
    List<ServiceQuoteLineItem>? items,
  }) {
    final rawItems = json['quote_items'];
    List<ServiceQuoteLineItem> parsedItems = items ?? [];
    if (parsedItems.isEmpty && rawItems is List) {
      parsedItems = rawItems
          .map(_stringKeyedMap)
          .whereType<Map<String, dynamic>>()
          .map(ServiceQuoteLineItem.fromJson)
          .toList();
    }

    return ServiceQuote(
      id: json['id']?.toString() ?? '',
      quoteNumber: json['quote_number']?.toString() ?? 'COT-N/A',
      clientId: json['client_id']?.toString() ?? '',
      clientNameSnapshot: json['client_name_snapshot']?.toString(),
      status: json['status']?.toString() ?? 'draft',
      subtotal: _doubleFromJson(json['subtotal'], fallback: 0.0),
      taxPct: _doubleFromJson(json['tax_pct'], fallback: 0.16),
      taxExempt: json['tax_exempt'] == true,
      tax: _doubleFromJson(json['tax'], fallback: 0.0),
      total: _doubleFromJson(json['total'], fallback: 0.0),
      validUntil: DateTime.tryParse(json['valid_until']?.toString() ?? ''),
      notes: json['notes']?.toString(),
      pdfPath: json['pdf_path']?.toString(),
      serviceTicketId: json['service_ticket_id']?.toString(),
      convertedOrderId: json['converted_order_id']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      items: parsedItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quote_number': quoteNumber,
      'client_id': clientId,
      'client_name_snapshot': clientNameSnapshot,
      'status': status,
      'subtotal': subtotal,
      'tax_pct': taxPct,
      'tax_exempt': taxExempt,
      'tax': tax,
      'total': total,
      'valid_until': validUntil?.toIso8601String(),
      'notes': notes,
      'pdf_path': pdfPath,
      'service_ticket_id': serviceTicketId,
      'converted_order_id': convertedOrderId,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'quote_items': items.map((i) => i.toJson()).toList(),
    };
  }
}
