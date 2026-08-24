import 'service_ticket_type.dart';

Map<String, dynamic> buildServiceTicketIntakeDetails({
  required String type,
  String? previousMaintenance,
  DateTime? lastMaintenanceDate,
  String? issueDuration,
  String? visibleDamage,
  String? previousRepair,
  String? showsErrorCode,
}) {
  final normalizedType = ServiceTicketType.normalize(type);
  final details = <String, dynamic>{};

  void putIfPresent(String key, Object? value) {
    if (value == null) return;
    if (value is String && value.trim().isEmpty) return;
    details[key] = value;
  }

  switch (normalizedType) {
    case ServiceTicketType.preventivo:
      putIfPresent('previous_maintenance', previousMaintenance);
      if (lastMaintenanceDate != null) {
        putIfPresent(
          'last_maintenance_date',
          lastMaintenanceDate.toIso8601String().split('T').first,
        );
      }
      break;
    case ServiceTicketType.correctivo:
      putIfPresent('issue_duration', issueDuration);
      putIfPresent('visible_damage', visibleDamage);
      putIfPresent('previous_repair', previousRepair);
      break;
    case ServiceTicketType.diagnostico:
      putIfPresent('issue_duration', issueDuration);
      putIfPresent('shows_error_code', showsErrorCode);
      putIfPresent('visible_damage', visibleDamage);
      break;
  }

  return details;
}
