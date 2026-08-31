class NotificationPresentation {
  const NotificationPresentation({
    required this.title,
    required this.body,
    required this.isServiceNotification,
  });

  final String title;
  final String body;
  final bool isServiceNotification;
}

NotificationPresentation notificationPresentation(
  Map<String, dynamic> notification,
) {
  final rawTitle = notification['title']?.toString() ?? 'Notificación';
  final rawBody = notification['body']?.toString() ?? '';
  final resourceType = _notificationValue(notification, const [
    'resource_type',
    'resourceType',
  ])?.toLowerCase();
  final serviceTicketId = _notificationValue(notification, const [
    'service_ticket_id',
    'serviceTicketId',
  ]);
  final isServiceNotification =
      resourceType == 'service_ticket' || serviceTicketId != null;

  if (!isServiceNotification) {
    return NotificationPresentation(
      title: rawTitle,
      body: rawBody,
      isServiceNotification: false,
    );
  }

  final normalizedTitle = rawTitle.toLowerCase();
  final isQuoteStatus =
      normalizedTitle.contains('actualización de cotización') ||
      normalizedTitle.contains('actualizacion de cotizacion');
  final isQuoteMessage =
      normalizedTitle.contains('mensaje de cotización') ||
      normalizedTitle.contains('mensaje de cotizacion');

  if (isQuoteStatus) {
    final status =
        _textAfter(rawBody, 'cambió a estado:') ??
        _textAfter(rawBody, 'cambio a estado:');
    return NotificationPresentation(
      title: 'Actualización de tu servicio',
      body: status == null
          ? 'Hay una actualización en la propuesta de tu servicio.'
          : 'La propuesta de tu servicio cambió a estado: $status',
      isServiceNotification: true,
    );
  }

  if (isQuoteMessage) {
    final separator = rawBody.indexOf(':');
    final message = separator >= 0
        ? rawBody.substring(separator + 1).trim()
        : '';
    return NotificationPresentation(
      title: 'Nuevo mensaje sobre tu servicio',
      body: message.isEmpty
          ? 'Tienes un nuevo mensaje sobre la propuesta de tu servicio.'
          : 'Mensaje sobre la propuesta de tu servicio: $message',
      isServiceNotification: true,
    );
  }

  return NotificationPresentation(
    title: rawTitle,
    body: rawBody,
    isServiceNotification: true,
  );
}

String? _notificationValue(
  Map<String, dynamic> notification,
  List<String> keys,
) {
  final sources = <Map<String, dynamic>>[notification];
  for (final containerKey in const ['data', 'metadata', 'payload']) {
    final value = notification[containerKey];
    if (value is Map) {
      sources.add(value.map((key, value) => MapEntry(key.toString(), value)));
    }
  }
  for (final source in sources) {
    for (final key in keys) {
      final value = source[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  return null;
}

String? _textAfter(String source, String marker) {
  final index = source.toLowerCase().indexOf(marker);
  if (index < 0) return null;
  final value = source.substring(index + marker.length).trim();
  return value.isEmpty ? null : value;
}
