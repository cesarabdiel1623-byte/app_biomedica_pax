import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/quote.dart';
import '../models/service_completion.dart';
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

  static bool isVideoFile(String fileName) {
    try {
      final ext = _fileExtension(fileName);
      return _allowedVideoExtensions.contains(ext);
    } catch (_) {
      return false;
    }
  }

  static String _videoContentType(String fileName) {
    try {
      final ext = _fileExtension(fileName);
      return switch (ext) {
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        'm4v' => 'video/x-m4v',
        _ => 'video/mp4',
      };
    } catch (_) {
      return 'video/mp4';
    }
  }

  /// Sube un adjunto (imagen o video) y retorna una referencia interna para generar URL firmada.
  static Future<String> uploadChatAttachment(
    String ticketId,
    String fileName,
    Uint8List bytes,
  ) async {
    final isVideo = isVideoFile(fileName);
    final contentType = isVideo
        ? _videoContentType(fileName)
        : _imageContentType(fileName);
    return uploadTicketAttachment(
      ticketId: ticketId,
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
      isVideo: isVideo,
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

  /// Obtener la cotización de servicio relevante para el ticket.
  /// Prioridad:
  /// 1. sent
  /// 2. approved
  /// 3. la más reciente entre converted / rejected / expired / draft
  static Future<ServiceQuote?> getRelevantServiceQuote(String ticketId) async {
    await _ensureTicketBelongsToCurrentClient(ticketId);
    final res = await _db
        .from('quotes')
        .select('*, quote_items(*)')
        .eq('service_ticket_id', ticketId)
        .order('created_at', ascending: false);

    if (res.isEmpty) return null;

    final quotes = res
        .map((m) => ServiceQuote.fromJson(m))
        .toList();

    if (quotes.isEmpty) return null;

    final sentQuote = quotes.where((q) => q.isSent).firstOrNull;
    if (sentQuote != null) return sentQuote;

    final approvedQuote = quotes.where((q) => q.isApproved).firstOrNull;
    if (approvedQuote != null) return approvedQuote;

    return quotes.firstOrNull;
  }

  /// Aceptar la cotización de servicio mediante RPC autoritativa
  static Future<void> acceptServiceQuote(String quoteId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Debes iniciar sesión para responder a la cotización.');
    }
    await _db.rpc(
      'respond_to_quote',
      params: {
        'p_quote_id': quoteId,
        'p_accept': true,
      },
    );
  }

  /// Rechazar la cotización de servicio mediante RPC autoritativa
  static Future<void> rejectServiceQuote(String quoteId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Debes iniciar sesión para responder a la cotización.');
    }
    await _db.rpc(
      'respond_to_quote',
      params: {
        'p_quote_id': quoteId,
        'p_accept': false,
      },
    );
  }

  /// Preparar la orden de compra en backend a partir de la cotización aprobada.
  /// (Base lista para T2A-4. NO envía p_environment).
  static Future<Map<String, dynamic>> prepareServiceQuoteOrder(
    String quoteId, {
    String? notes,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Debes iniciar sesión para preparar la orden.');
    }
    final res = await _db.rpc(
      'prepare_quote_order',
      params: {
        'p_quote_id': quoteId,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      },
    );
    if (res is! Map) {
      throw Exception('Respuesta inesperada al preparar la orden.');
    }
    return Map<String, dynamic>.from(res);
  }

  /// Obtiene los datos de finalización técnica del servicio (sólo lectura para el cliente).
  /// Si existen múltiples órdenes históricas, selecciona la orden finalizada más reciente
  /// (status = 'resolved' o 'closed' con completed_at no nulo).
  static Future<ServiceCompletion?> getServiceCompletion(
    String ticketId,
  ) async {
    final cleanId = ticketId.trim();
    if (cleanId.isEmpty) return null;

    try {
      await _ensureTicketBelongsToCurrentClient(cleanId);
      final res = await _db
          .from('service_orders')
          .select(
            '*, assigned_technician:assigned_technician_id(full_name), service_parts_used(id, service_order_id, product_id, quantity, products:product_id(name))',
          )
          .eq('service_ticket_id', cleanId)
          .inFilter('status', ['resolved', 'closed'])
          .not('completed_at', 'is', null)
          .order('completed_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res == null) return null;
      final completion = ServiceCompletion.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
      return completion.isCompleted ? completion : null;
    } catch (e) {
      return null;
    }
  }
}

class _StorageAttachment {
  final String bucket;
  final String path;

  const _StorageAttachment({required this.bucket, required this.path});
}
