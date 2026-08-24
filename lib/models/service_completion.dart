/// Modelo representativo del resultado de ejecución técnica de un servicio.
class ServicePartUsedItem {
  final String id;
  final String serviceOrderId;
  final String productId;
  final String? productName;
  final String? warehouseId;
  final double quantity;
  final double unitCost;
  final DateTime? createdAt;

  const ServicePartUsedItem({
    required this.id,
    required this.serviceOrderId,
    required this.productId,
    this.productName,
    this.warehouseId,
    required this.quantity,
    this.unitCost = 0.0,
    this.createdAt,
  });

  factory ServicePartUsedItem.fromJson(Map<String, dynamic> json) {
    final productMap = json['products'] as Map<String, dynamic>?;
    return ServicePartUsedItem(
      id: json['id']?.toString() ?? '',
      serviceOrderId: json['service_order_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: productMap?['name']?.toString() ?? json['product_name']?.toString(),
      warehouseId: json['warehouse_id']?.toString(),
      quantity: double.tryParse(json['quantity']?.toString() ?? '1') ?? 1.0,
      unitCost: double.tryParse(json['unit_cost']?.toString() ?? '0') ?? 0.0,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }
}

/// Datos consolidados de finalización técnica de una orden de servicio.
class ServiceCompletion {
  final String id;
  final String serviceTicketId;
  final String? assignedTechnicianId;
  final String? assignedTechnicianName;
  final String? diagnosis;
  final String? solution;
  final String? recommendations;
  final String status;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? reportPdfPath;
  final List<ServicePartUsedItem> partsUsed;

  const ServiceCompletion({
    required this.id,
    required this.serviceTicketId,
    this.assignedTechnicianId,
    this.assignedTechnicianName,
    this.diagnosis,
    this.solution,
    this.recommendations,
    required this.status,
    this.scheduledAt,
    this.startedAt,
    this.completedAt,
    this.reportPdfPath,
    this.partsUsed = const [],
  });

  bool get isCompleted =>
      completedAt != null && (status == 'resolved' || status == 'closed');

  factory ServiceCompletion.fromJson(Map<String, dynamic> json) {
    final profile = json['assigned_technician'] as Map<String, dynamic>?;
    final parts = (json['service_parts_used'] as List<dynamic>?)
            ?.map((e) => ServicePartUsedItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    return ServiceCompletion(
      id: json['id']?.toString() ?? '',
      serviceTicketId: json['service_ticket_id']?.toString() ?? '',
      assignedTechnicianId: json['assigned_technician_id']?.toString(),
      assignedTechnicianName: profile?['full_name']?.toString(),
      diagnosis: json['diagnosis']?.toString(),
      solution: json['solution']?.toString(),
      recommendations: json['recommendations']?.toString(),
      status: json['status']?.toString() ?? 'assigned',
      scheduledAt: json['scheduled_at'] != null ? DateTime.tryParse(json['scheduled_at'].toString()) : null,
      startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at'].toString()) : null,
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'].toString()) : null,
      reportPdfPath: json['report_pdf_path']?.toString(),
      partsUsed: parts,
    );
  }
}
