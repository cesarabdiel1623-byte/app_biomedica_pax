import '../models/service_order_presentation.dart';
import '../models/service_ticket.dart';
import 'service_ticket_type.dart';

String serviceTicketCardTitle(ServiceTicket ticket) {
  final normalizedLabel = ServiceTicketType.label(
    ticket.type,
    title: ticket.title,
  );
  final title = ticket.title.trim();
  if (title.isEmpty) return normalizedLabel;

  final colonIndex = title.indexOf(':');
  if (colonIndex <= 0) return title;

  final prefix = title.substring(0, colonIndex).trim();
  final suffix = title.substring(colonIndex + 1).trim();
  final normalizedPrefix = ServiceTicketType.label(
    ServiceTicketType.normalize(ticket.type),
    title: '$prefix:',
  );

  if (suffix.isEmpty) {
    return title;
  }
  if (prefix == normalizedLabel || prefix == normalizedPrefix) return title;
  return '$normalizedLabel: $suffix';
}

String serviceTicketCardPreview(ServiceTicket ticket) {
  final structured = ticket.failureDescription?.trim();
  if (structured != null && structured.isNotEmpty) return structured;

  final legacy = parseLegacyServiceTicketDescription(ticket.description);
  final legacyDescription = legacy?.description?.trim();
  if (legacyDescription != null && legacyDescription.isNotEmpty) {
    return legacyDescription;
  }

  final description = ticket.description?.trim();
  if (description == null || description.isEmpty) return '';
  if (legacy != null) return '';
  return description;
}
