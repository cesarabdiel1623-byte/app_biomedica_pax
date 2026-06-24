class ServiceTicket {
  final String id;
  final String ticketNumber;
  final String? clientId;
  final String? equipmentUnitId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String type;
  final String? requestedBy;
  final String? assignedTechnician;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Relations (loaded via join)
  final String? clientName;
  final String? equipmentName;

  ServiceTicket({
    required this.id,
    required this.ticketNumber,
    this.clientId,
    this.equipmentUnitId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    required this.type,
    this.requestedBy,
    this.assignedTechnician,
    required this.createdAt,
    this.updatedAt,
    this.clientName,
    this.equipmentName,
  });

  factory ServiceTicket.fromJson(Map<String, dynamic> json) {
    // Try to extract client name from join
    String? clientName;
    if (json['clients'] != null) {
      final c = json['clients'] as Map<String, dynamic>;
      clientName = c['business_name'] as String? ?? c['trade_name'] as String?;
    }

    // equipment_units no se hace join (schema variable); se muestra el ID si existe
    final String? equipmentName = null;

    return ServiceTicket(
      id: json['id'] as String,
      ticketNumber: json['ticket_number'] as String? ?? '',
      clientId: json['client_id'] as String?,
      equipmentUnitId: json['equipment_unit_id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'open',
      priority: json['priority'] as String? ?? 'medium',
      type: json['type'] as String? ?? 'otro',
      requestedBy: json['requested_by'] as String?,
      assignedTechnician: json['assigned_technician'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      clientName: clientName,
      equipmentName: equipmentName,
    );
  }

  /// Returns a color-keyed status label
  String get statusLabel {
    switch (status) {
      case 'open': return 'Abierto';
      case 'in_progress': return 'En Progreso';
      case 'resolved': return 'Resuelto';
      case 'closed': return 'Cerrado';
      case 'cancelled': return 'Cancelado';
      default: return status;
    }
  }

  String get priorityLabel {
    switch (priority) {
      case 'low': return 'Baja';
      case 'medium': return 'Media';
      case 'high': return 'Alta';
      case 'critical': return 'Crítica';
      default: return priority;
    }
  }

  String get typeLabel {
    switch (type) {
      case 'correctivo': return 'Correctivo';
      case 'preventivo': return 'Preventivo';
      case 'instalacion': return 'Instalación';
      case 'garantia': return 'Garantía';
      case 'otro': return 'Otro';
      default: return type;
    }
  }
}
