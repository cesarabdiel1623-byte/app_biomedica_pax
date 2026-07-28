import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_ticket.dart';
import '../models/ticket_message.dart';
import '../utils/ui_helpers.dart';

class TicketService {
  static final _db = Supabase.instance.client;
  static const _attachmentBucket = 'ticket-attachments';
  static const _storageReferencePrefix = 'storage://';
  static const _maxVideoBytes = 40 * 1024 * 1024;
  static const _allowedVideoExtensions = {'mp4', 'mov', 'm4v', 'webm'};

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
    final effectiveClientId = (clientId != null && clientId.isNotEmpty)
        ? clientId
        : userId;

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

  /// Ticket individual por número de ticket (ej. TCK-20260622-8CA2922A)
  static Future<ServiceTicket?> getTicketByNumber(String ticketNumber) async {
    final res = await _db
        .from('service_tickets')
        .select(_select)
        .eq('ticket_number', ticketNumber)
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

    return Future.wait(
      (res as List).map((entry) async {
        final json = Map<String, dynamic>.from(entry as Map);
        json['attachment_url'] = await resolveAttachmentUrl(
          json['attachment_url'] as String?,
        );
        return TicketMessage.fromJson(json);
      }),
    );
  }

  /// Enviar un mensaje de chat desde la app móvil (siempre sender_type = 'client')
  static Future<void> sendTicketMessage(
    String ticketId,
    String message, {
    String? attachmentUrl,
  }) async {
    final userId = _db.auth.currentUser?.id;
    final normalizedAttachment = _normalizeAttachmentReference(attachmentUrl);
    if (attachmentUrl != null && normalizedAttachment == null) {
      throw Exception('URL de adjunto no permitida.');
    }
    await _db.from('service_ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_type': 'client',
      'sender_profile_id': userId,
      'message': message,
      'attachment_url': normalizedAttachment,
      'is_internal': false,
    });
  }

  /// Sube una imagen y retorna una referencia interna para generar URL firmada.
  static Future<String> uploadChatAttachment(
    String ticketId,
    String fileName,
    Uint8List bytes,
  ) async {
    UiHelpers.validateImageUpload(bytes, fileName);
    return uploadTicketAttachment(
      ticketId: ticketId,
      fileName: fileName,
      bytes: bytes,
      contentType: _imageContentType(fileName),
      isVideo: false,
    );
  }

  static Future<String> uploadTicketAttachment({
    required String ticketId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required bool isVideo,
  }) async {
    if (isVideo) {
      _validateVideoUpload(bytes, fileName);
    } else {
      UiHelpers.validateImageUpload(bytes, fileName);
    }

    final cleanName = UiHelpers.sanitizeStorageFileName(fileName);
    final cleanFileName = '${DateTime.now().microsecondsSinceEpoch}_$cleanName';
    final path = '$ticketId/$cleanFileName';

    await _db.storage
        .from(_attachmentBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );

    return '$_storageReferencePrefix$_attachmentBucket/$path';
  }

  static Future<String?> resolveAttachmentUrl(String? reference) async {
    if (reference == null || reference.trim().isEmpty) return null;
    final value = reference.trim();
    final trustedUrl = UiHelpers.sanitizeTrustedRemoteUrl(value);
    if (trustedUrl != null) return trustedUrl;

    final storageReference = _parseStorageReference(value);
    if (storageReference == null) return null;

    try {
      return await _db.storage
          .from(storageReference.bucket)
          .createSignedUrl(storageReference.path, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeAttachmentReference(String? reference) {
    if (reference == null) return null;
    final value = reference.trim();
    if (value.isEmpty) return null;

    if (_parseStorageReference(value) != null) return value;
    return UiHelpers.sanitizeTrustedRemoteUrl(value);
  }

  static _StorageAttachment? _parseStorageReference(String reference) {
    final uri = Uri.tryParse(reference);
    if (uri == null ||
        uri.scheme != 'storage' ||
        uri.host != _attachmentBucket) {
      return null;
    }

    final path = uri.path.replaceFirst(RegExp(r'^/+'), '');
    if (path.isEmpty || path.contains('..')) return null;
    return _StorageAttachment(bucket: uri.host, path: path);
  }

  static void _validateVideoUpload(Uint8List bytes, String fileName) {
    if (bytes.isEmpty) {
      throw Exception('El video está vacío.');
    }
    if (bytes.length > _maxVideoBytes) {
      throw Exception('El video excede 40 MB.');
    }

    final cleanName = UiHelpers.sanitizeStorageFileName(fileName);
    final dotIndex = cleanName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == cleanName.length - 1) {
      throw Exception('El video debe tener una extensión válida.');
    }
    final extension = cleanName.substring(dotIndex + 1).toLowerCase();
    if (!_allowedVideoExtensions.contains(extension)) {
      throw Exception('Formato de video no permitido.');
    }
  }

  static String _imageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  /// Marcar todos los mensajes del soporte como leídos (implica entregados)
  static Future<void> markMessagesAsRead(String ticketId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final nowStr = DateTime.now().toIso8601String();
      await _db
          .from('service_ticket_messages')
          .update({'read_at': nowStr, 'delivered_at': nowStr})
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

class _StorageAttachment {
  final String bucket;
  final String path;

  const _StorageAttachment({required this.bucket, required this.path});
}
