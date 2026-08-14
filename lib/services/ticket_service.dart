import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/service_ticket.dart';
import '../models/ticket_message.dart';
import '../utils/ui_helpers.dart';
import 'auth_identity_service.dart';

class TicketService {
  static final _db = Supabase.instance.client;
  static const _attachmentBucket = 'ticket-attachments';
  static const _storageReferencePrefix = 'storage://';
  static const _maxVideoBytes = 40 * 1024 * 1024;
  static const _allowedVideoExtensions = {'mp4', 'mov', 'm4v', 'webm'};
  static const _uuid = Uuid();

  // Solo join a 'clients' (columnas confirmadas). El join a equipment_units
  // se omite porque las columnas varían según el schema.
  static const _select = '*, clients(business_name, trade_name)';

  /// Fetches tickets linked to the current user's client profile.
  static Future<List<ServiceTicket>> getMyTickets() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];

    final clientId = await AuthIdentityService.requireLinkedClientId();
    final res = await _db
        .from('service_tickets')
        .select(_select)
        .eq('client_id', clientId)
        .order('created_at', ascending: false);

    return (res as List)
        .map((e) => ServiceTicket.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Ticket individual por ID
  static Future<ServiceTicket?> getTicketById(String id) async {
    await _ensureTicketBelongsToCurrentClient(id);
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
    final clientId = await AuthIdentityService.requireLinkedClientId();
    final res = await _db
        .from('service_tickets')
        .select(_select)
        .eq('ticket_number', ticketNumber)
        .eq('client_id', clientId)
        .maybeSingle();

    if (res == null) return null;
    return ServiceTicket.fromJson(res);
  }

  /// Obtener mensajes de chat asociados al ticket (solo no internos)
  static Future<List<TicketMessage>> getTicketMessages(String ticketId) async {
    await _ensureTicketBelongsToCurrentClient(ticketId);
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
    if (userId == null) {
      throw Exception('Debes iniciar sesión para enviar mensajes.');
    }
    await _ensureTicketBelongsToCurrentClient(ticketId);

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

    await _ensureTicketBelongsToCurrentClient(ticketId);
    final extension = _fileExtension(fileName);
    final path = '$ticketId/${_uuid.v4()}.$extension';

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
    final storageReference = _parseStorageReference(value);
    if (storageReference == null) {
      return UiHelpers.sanitizeTrustedRemoteUrl(value);
    }

    try {
      return await _db.storage
          .from(storageReference.bucket)
          .createSignedUrl(storageReference.path, 60 * 60);
    } catch (_) {
      return UiHelpers.sanitizeTrustedRemoteUrl(value);
    }
  }

  static String? _normalizeAttachmentReference(String? reference) {
    if (reference == null) return null;
    final value = reference.trim();
    if (value.isEmpty) return null;

    if (_parseStorageReference(value) != null) return value;
    return null;
  }

  static _StorageAttachment? _parseStorageReference(String reference) {
    final uri = Uri.tryParse(reference);
    if (uri == null) return null;
    final normalizedReference = reference
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');

    if (!uri.hasScheme && normalizedReference.isNotEmpty) {
      final path = normalizedReference.startsWith('$_attachmentBucket/')
          ? normalizedReference.substring(_attachmentBucket.length + 1)
          : normalizedReference;
      if (_isSafeStoragePath(path)) {
        return _StorageAttachment(bucket: _attachmentBucket, path: path);
      }
    }

    if (uri.scheme == 'storage' && uri.host == _attachmentBucket) {
      final path = uri.path.replaceFirst(RegExp(r'^/+'), '');
      if (_isSafeStoragePath(path)) {
        return _StorageAttachment(bucket: uri.host, path: path);
      }
      return null;
    }

    // Compatibilidad con referencias antiguas de Supabase: se extrae la ruta,
    // pero nunca se reutiliza la URL pública o firmada recibida.
    if (uri.scheme == 'https') {
      final segments = uri.pathSegments;
      final objectIndex = segments.indexOf('object');
      if (objectIndex >= 0 && objectIndex + 3 < segments.length) {
        final accessType = segments[objectIndex + 1];
        final bucket = segments[objectIndex + 2];
        if ({'public', 'sign', 'authenticated'}.contains(accessType) &&
            bucket == _attachmentBucket) {
          final path = segments.sublist(objectIndex + 3).join('/');
          if (_isSafeStoragePath(path)) {
            return _StorageAttachment(bucket: bucket, path: path);
          }
        }
      }
    }

    return null;
  }

  static bool _isSafeStoragePath(String path) {
    if (path.isEmpty || path.contains('..') || path.startsWith('/')) {
      return false;
    }
    final segments = path.split('/');
    return segments.length >= 2 &&
        segments.length <= 8 &&
        segments.every((segment) => segment.trim().isNotEmpty);
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

  static String _fileExtension(String fileName) {
    final cleanName = UiHelpers.sanitizeStorageFileName(fileName);
    final dotIndex = cleanName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == cleanName.length - 1) {
      throw Exception('El archivo debe tener una extensión válida.');
    }
    return cleanName.substring(dotIndex + 1).toLowerCase();
  }

  static Future<void> _ensureTicketBelongsToCurrentClient(
    String ticketId,
  ) async {
    final clientId = await AuthIdentityService.requireLinkedClientId();
    final ticket = await _db
        .from('service_tickets')
        .select('id')
        .eq('id', ticketId)
        .eq('client_id', clientId)
        .maybeSingle();
    if (ticket == null) {
      throw Exception('No tienes acceso a este ticket.');
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
      await _ensureTicketBelongsToCurrentClient(ticketId);
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
      await _ensureTicketBelongsToCurrentClient(ticketId);
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
