class TicketMessage {
  final String id;
  final String ticketId;
  final String senderType; // 'client' | 'staff' | 'system'
  final String? senderProfileId;
  final String? senderName;
  final String message;
  final String? attachmentUrl;
  final bool isInternal;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? deliveredAt;

  TicketMessage({
    required this.id,
    required this.ticketId,
    required this.senderType,
    this.senderProfileId,
    this.senderName,
    required this.message,
    this.attachmentUrl,
    required this.isInternal,
    required this.createdAt,
    this.readAt,
    this.deliveredAt,
  });

  factory TicketMessage.fromJson(Map<String, dynamic> json) {
    String? name;
    if (json['profiles'] != null) {
      name = json['profiles']['full_name'] as String?;
    }
    return TicketMessage(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      senderType: json['sender_type'] as String? ?? 'client',
      senderProfileId: json['sender_profile_id'] as String?,
      senderName:
          name ?? (json['sender_type'] == 'client' ? 'Cliente' : 'Soporte'),
      message: json['message'] as String? ?? '',
      attachmentUrl: json['attachment_url'] as String?,
      isInternal: json['is_internal'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'] as String)
          : null,
    );
  }
}
