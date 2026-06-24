import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_ticket.dart';
import '../models/ticket_message.dart';

class TicketService {
  static final _db = Supabase.instance.client;

  // Solo join a 'clients' (columnas confirmadas). El join a equipment_units
  // se omite porque las columnas varían según el schema.
  static const _select = '*, clients(business_name, trade_name)';

  /// Fetches tickets linked to the current user's client profile or created by the user.
  static Future<List<ServiceTicket>> getMyTickets() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];

    // 1. Obtener client_id del perfil del usuario (si está vinculado)
    final profileRes = await _db
        .from('profiles')
        .select('client_id')
        .eq('id', userId)
        .maybeSingle();

    final clientId = profileRes?['client_id'] as String?;
    final effectiveClientId = (clientId != null && clientId.isNotEmpty) ? clientId : userId;

    // 2. Traer todos los tickets que pertenezcan a este cliente (effectiveClientId)
    //    O que hayan sido creados por este usuario (requested_by = userId)
    final res = await _db
        .from('service_tickets')
        .select(_select)
        .or('client_id.eq.$effectiveClientId,requested_by.eq.$userId')
        .order('created_at', ascending: false);

    return (res as List)
        .map((e) => ServiceTicket.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Ticket individual por ID
  static Future<ServiceTicket?> getTicketById(String id) async {
    final res = await _db
        .from('service_tickets')
        .select(_select)
        .eq('id', id)
        .maybeSingle();

    if (res == null) return null;
    return ServiceTicket.fromJson(res);
  }

  /// Obtener mensajes de chat asociados al ticket (solo no internos)
  static Future<List<TicketMessage>> getTicketMessages(String ticketId) async {
    final res = await _db
        .from('service_ticket_messages')
        .select('*, profiles:sender_profile_id(full_name)')
        .eq('ticket_id', ticketId)
        .eq('is_internal', false)
        .order('created_at', ascending: true);

    return (res as List)
        .map((e) => TicketMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Enviar un mensaje de chat desde la app móvil (siempre sender_type = 'client')
  static Future<void> sendTicketMessage(String ticketId, String message, {String? attachmentUrl}) async {
    final userId = _db.auth.currentUser?.id;
    await _db.from('service_ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_type': 'client',
      'sender_profile_id': userId,
      'message': message,
      'attachment_url': attachmentUrl,
      'is_internal': false,
    });
  }

  /// Subir archivo adjunto de chat a Supabase Storage y retornar su URL pública
  static Future<String> uploadChatAttachment(String ticketId, String fileName, Uint8List bytes) async {
    final cleanFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final path = '$ticketId/$cleanFileName';

    await _db.storage.from('ticket-attachments').uploadBinary(path, bytes);

    final url = _db.storage.from('ticket-attachments').getPublicUrl(path);
    return url;
  }

  /// Marcar todos los mensajes del soporte como leídos (implica entregados)
  static Future<void> markMessagesAsRead(String ticketId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final nowStr = DateTime.now().toIso8601String();
      await _db
          .from('service_ticket_messages')
          .update({
            'read_at': nowStr,
            'delivered_at': nowStr,
          })
          .eq('ticket_id', ticketId)
          .neq('sender_type', 'client')
          .isFilter('read_at', null);
    } catch (e) {
      // Ignorar errores silenciosamente
    }
  }

  /// Marcar todos los mensajes del soporte como entregados
  static Future<void> markMessagesAsDelivered(String ticketId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _db
          .from('service_ticket_messages')
          .update({'delivered_at': DateTime.now().toIso8601String()})
          .eq('ticket_id', ticketId)
          .neq('sender_type', 'client')
          .isFilter('delivered_at', null);
    } catch (e) {
      // Ignorar errores silenciosamente
    }
  }
}
