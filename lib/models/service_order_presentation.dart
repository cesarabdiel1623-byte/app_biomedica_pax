import '../utils/service_ticket_type.dart';
import 'service_ticket.dart';

class ServiceOrderPresentation {
  final bool isStructured;
  final String? subject;
  final String? equipmentName;
  final String? equipmentBrand;
  final String? equipmentModel;
  final String? serialNumber;
  final String? equipmentOperating;
  final String serviceTypeLabel;
  final String? clientName;
  final String? institution;
  final String? department;
  final String? responsible;
  final String? phone;
  final String? email;
  final String? address;
  final String descriptionLabel;
  final String? failureDescription;
  final Map<String, String> intakeDetails;
  final String? legacyEvidenceSummary;
  final bool usesServiceOrders;
  final bool usesMaintenanceLogs;

  const ServiceOrderPresentation({
    required this.isStructured,
    required this.serviceTypeLabel,
    required this.descriptionLabel,
    required this.intakeDetails,
    required this.usesServiceOrders,
    required this.usesMaintenanceLogs,
    this.subject,
    this.equipmentName,
    this.equipmentBrand,
    this.equipmentModel,
    this.serialNumber,
    this.equipmentOperating,
    this.clientName,
    this.institution,
    this.department,
    this.responsible,
    this.phone,
    this.email,
    this.address,
    this.failureDescription,
    this.legacyEvidenceSummary,
  });

  factory ServiceOrderPresentation.fromTicket(ServiceTicket ticket) {
    final hasStructured = _hasStructuredTicketData(ticket);
    if (hasStructured) {
      return ServiceOrderPresentation(
        isStructured: true,
        subject: _blankToNull(ticket.title),
        equipmentName: _blankToNull(ticket.equipmentName),
        equipmentBrand: _blankToNull(ticket.equipmentBrand),
        equipmentModel: _blankToNull(ticket.equipmentModel),
        serialNumber: _blankToNull(ticket.serialNumber),
        equipmentOperating: _blankToNull(ticket.equipmentOperating),
        serviceTypeLabel: ticket.typeLabel,
        clientName: _blankToNull(ticket.clientName),
        institution: _blankToNull(ticket.institution),
        department: _blankToNull(ticket.department),
        responsible: _blankToNull(ticket.contactName),
        phone: _blankToNull(ticket.contactPhone),
        email: _blankToNull(ticket.contactEmail),
        address: _serviceAddress(ticket),
        descriptionLabel: descriptionLabelForType(ticket.type),
        failureDescription:
            _blankToNull(ticket.failureDescription) ??
            _blankToNull(ticket.description),
        intakeDetails: _intakeMapFromJson(ticket.intakeDetails),
        usesServiceOrders: false,
        usesMaintenanceLogs: false,
      );
    }

    final legacy = parseLegacyServiceTicketDescription(ticket.description);
    if (legacy != null) {
      return ServiceOrderPresentation(
        isStructured: false,
        subject: _blankToNull(ticket.title),
        equipmentName: legacy.equipment['Nombre'],
        equipmentBrand: legacy.equipment['Marca'],
        equipmentModel: legacy.equipment['Modelo'],
        serialNumber: legacy.equipment['Número de serie'],
        equipmentOperating:
            legacy.request['¿El equipo está operando actualmente?'] ??
            legacy.request['¿El equipo enciende?'],
        serviceTypeLabel: ServiceTicketType.label(
          ticket.type,
          title: ticket.title,
        ),
        clientName: _blankToNull(ticket.clientName),
        institution: legacy.contact['Institución'],
        department: legacy.contact['Área o departamento'],
        responsible: legacy.contact['Responsable'],
        phone: legacy.contact['Teléfono'],
        email: _blankToNull(ticket.contactEmail),
        address: legacy.contact['Dirección'] ?? _serviceAddress(ticket),
        descriptionLabel: descriptionLabelForType(ticket.type),
        failureDescription:
            _blankToNull(legacy.description) ??
            _blankToNull(ticket.description),
        intakeDetails: {
          for (final entry in legacy.request.entries)
            if (!_mainLegacyRequestKeys.contains(entry.key))
              entry.key: entry.value,
        },
        legacyEvidenceSummary: legacy.contact['Evidencia'],
        usesServiceOrders: false,
        usesMaintenanceLogs: false,
      );
    }

    return ServiceOrderPresentation(
      isStructured: false,
      subject: _blankToNull(ticket.title),
      serviceTypeLabel: ticket.typeLabel,
      clientName: _blankToNull(ticket.clientName),
      responsible: _blankToNull(ticket.contactName),
      phone: _blankToNull(ticket.contactPhone),
      email: _blankToNull(ticket.contactEmail),
      address: _serviceAddress(ticket),
      descriptionLabel: descriptionLabelForType(ticket.type),
      failureDescription: _blankToNull(ticket.description),
      intakeDetails: const {},
      usesServiceOrders: false,
      usesMaintenanceLogs: false,
    );
  }

  static String descriptionLabelForType(String type) {
    switch (ServiceTicketType.normalize(type)) {
      case ServiceTicketType.correctivo:
        return 'Descripción de la falla';
      case ServiceTicketType.diagnostico:
        return 'Descripción del problema';
      default:
        return 'Descripción / observaciones de la solicitud';
    }
  }
}

class LegacyServiceTicketSections {
  final Map<String, String> equipment;
  final Map<String, String> request;
  final Map<String, String> contact;
  final String? description;

  const LegacyServiceTicketSections({
    required this.equipment,
    required this.request,
    required this.contact,
    required this.description,
  });
}

LegacyServiceTicketSections? parseLegacyServiceTicketDescription(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  if (!text.contains('=== INFORMACIÓN DEL EQUIPO ===')) return null;

  final sections = <String, String>{};
  final matches = RegExp(
    r'===\s*([^=]+?)\s*===\s*([\s\S]*?)(?=\n===|$)',
  ).allMatches(text);

  for (final match in matches) {
    final title = match.group(1)?.trim();
    final body = match.group(2)?.trim();
    if (title != null && body != null) {
      sections[title] = body;
    }
  }

  if (sections.isEmpty) return null;

  String? descriptionEntry;
  for (final entry in sections.entries) {
    if (entry.key.toLowerCase().contains('descripción') &&
        entry.value.trim().isNotEmpty) {
      descriptionEntry = entry.value;
      break;
    }
  }

  return LegacyServiceTicketSections(
    equipment: _parseBulletMap(sections['INFORMACIÓN DEL EQUIPO']),
    request: _parseBulletMap(sections['SOLICITUD']),
    contact: _parseBulletMap(sections['CONTACTO Y LOGÍSTICA']),
    description: _blankToNull(descriptionEntry),
  );
}

bool _hasStructuredTicketData(ServiceTicket ticket) {
  return [
        ticket.equipmentName,
        ticket.equipmentBrand,
        ticket.equipmentModel,
        ticket.serialNumber,
        ticket.institution,
        ticket.department,
        ticket.equipmentOperating,
        ticket.failureDescription,
      ].any((value) => _blankToNull(value) != null) ||
      (ticket.intakeDetails?.isNotEmpty ?? false);
}

Map<String, String> _parseBulletMap(String? body) {
  if (body == null || body.trim().isEmpty) return const {};
  final result = <String, String>{};

  for (final rawLine in body.split('\n')) {
    final line = rawLine
        .replaceFirst(RegExp(r'^\s*•\s*'), '')
        .replaceFirst(RegExp(r'^\s*-\s*'), '')
        .trim();
    if (line.isEmpty || !line.contains(':')) continue;
    final colon = line.indexOf(':');
    final key = line.substring(0, colon).trim();
    final value = line.substring(colon + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      result[key] = value;
    }
  }

  return result;
}

Map<String, String> _intakeMapFromJson(Map<String, dynamic>? json) {
  if (json == null || json.isEmpty) return const {};
  const labels = {
    'previous_maintenance': 'Mantenimiento preventivo anterior',
    'last_maintenance_date': 'Fecha del último mantenimiento',
    'issue_duration': 'Desde cuándo ocurre',
    'visible_damage': 'Daños visibles',
    'previous_repair': 'Reparado anteriormente',
    'shows_error_code': 'Muestra código de error',
  };

  final result = <String, String>{};
  for (final entry in json.entries) {
    final value = entry.value?.toString().trim();
    if (value == null || value.isEmpty) continue;
    result[labels[entry.key] ?? entry.key] = value;
  }
  return result;
}

String? _serviceAddress(ServiceTicket ticket) {
  if (_blankToNull(ticket.serviceAddress) == null) {
    return _blankToNull(ticket.serviceLocation);
  }
  final cityPart = _blankToNull(ticket.serviceCity) != null
      ? ', ${ticket.serviceCity}'
      : '';
  final statePart = _blankToNull(ticket.serviceState) != null
      ? ', ${ticket.serviceState}'
      : '';
  return '${ticket.serviceAddress}$cityPart$statePart';
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed == 'No proporcionado' || trimmed == 'No indicado') return null;
  return trimmed;
}

const _mainLegacyRequestKeys = {
  'Tipo',
  '¿El equipo enciende?',
  '¿El equipo está operando actualmente?',
};
