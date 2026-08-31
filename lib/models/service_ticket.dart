import '../utils/service_ticket_type.dart';

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
  final String? assignedTechnicianCustomName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Additional Admin/Service fields
  final String? serviceAddress;
  final String? serviceCity;
  final String? serviceState;
  final String? serviceRegion;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final String? requestedServiceDate;
  final bool? isLocalService;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;
  final String? serviceLocation;
  final String? errorCode;
  final String? productId;
  final String? equipmentBrand;
  final String? equipmentModel;
  final String? serialNumber;
  final String? institution;
  final String? department;
  final String? equipmentOperating;
  final String? failureDescription;
  final Map<String, dynamic>? intakeDetails;

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
    this.assignedTechnicianCustomName,
    required this.createdAt,
    this.updatedAt,
    this.serviceAddress,
    this.serviceCity,
    this.serviceState,
    this.serviceRegion,
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.requestedServiceDate,
    this.isLocalService,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
    this.serviceLocation,
    this.errorCode,
    this.productId,
    this.equipmentBrand,
    this.equipmentModel,
    this.serialNumber,
    this.institution,
    this.department,
    this.equipmentOperating,
    this.failureDescription,
    this.intakeDetails,
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

    final rawIntakeDetails = json['intake_details'];
    final intakeDetails = rawIntakeDetails is Map
        ? Map<String, dynamic>.from(rawIntakeDetails)
        : null;

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
      assignedTechnician: json['assigned_technician_id'] as String?,
      assignedTechnicianCustomName:
          json['assigned_technician_custom_name'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      serviceAddress: json['service_address'] as String?,
      serviceCity: json['service_city'] as String?,
      serviceState: json['service_state'] as String?,
      serviceRegion: json['service_region'] as String?,
      scheduledStartAt: json['scheduled_start_at'] != null
          ? DateTime.tryParse(json['scheduled_start_at'] as String)
          : null,
      scheduledEndAt: json['scheduled_end_at'] != null
          ? DateTime.tryParse(json['scheduled_end_at'] as String)
          : null,
      requestedServiceDate: json['requested_service_date'] as String?,
      isLocalService: json['is_local_service'] as bool?,
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      contactEmail: json['contact_email'] as String?,
      serviceLocation: json['service_location'] as String?,
      errorCode: json['error_code'] as String?,
      productId: json['product_id'] as String?,
      equipmentBrand: json['equipment_brand'] as String?,
      equipmentModel: json['equipment_model'] as String?,
      serialNumber: json['serial_number'] as String?,
      institution: json['institution'] as String?,
      department: json['department'] as String?,
      equipmentOperating: _parseEquipmentOperating(json['equipment_operating']),
      failureDescription: json['failure_description'] as String?,
      intakeDetails: intakeDetails,
      clientName: clientName,
      equipmentName: json['equipment_name'] as String?,
    );
  }

  /// Returns a color-keyed status label
  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'open':
        return 'Abierto';
      case 'assigned':
        return 'Asignado';
      case 'in_progress':
        return 'En progreso';
      case 'resolved':
        return 'Servicio realizado';
      case 'closed':
        return 'Cerrado';
      case 'cancelled':
      case 'canceled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  String get priorityLabel {
    switch (priority) {
      case 'low':
        return 'Programable';
      case 'medium':
        return 'Regular';
      case 'high':
        return 'Urgente';
      case 'critical':
        return 'Inmediata';
      default:
        return priority;
    }
  }

  String get typeLabel {
    return ServiceTicketType.label(type, title: title);
  }

  String? get equipmentSummary {
    if (equipmentName != null && equipmentName!.trim().isNotEmpty) {
      return equipmentName!.trim();
    }
    final parts = [equipmentBrand, equipmentModel]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    return title.trim().isNotEmpty ? title.trim() : null;
  }

  static String? _parseEquipmentOperating(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? 'Sí' : 'No';
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    switch (text.toLowerCase()) {
      case 'true':
      case 't':
      case '1':
      case 'si':
      case 'sí':
        return 'Sí';
      case 'false':
      case 'f':
      case '0':
      case 'no':
        return 'No';
      default:
        return text;
    }
  }
}
