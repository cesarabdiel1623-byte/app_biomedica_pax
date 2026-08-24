import 'package:supabase_flutter/supabase_flutter.dart';

typedef ServiceOrderPdfInvoke =
    Future<ServiceOrderPdfRawResponse> Function(Map<String, dynamic> body);

class ServiceOrderPdfRawResponse {
  final int status;
  final dynamic data;

  const ServiceOrderPdfRawResponse({required this.status, required this.data});
}

class ServiceOrderPdfResult {
  final bool ok;
  final String documentType;
  final String ticketNumber;
  final String path;
  final int expiresIn;
  final String signedUrl;

  const ServiceOrderPdfResult({
    required this.ok,
    required this.documentType,
    required this.ticketNumber,
    required this.path,
    required this.expiresIn,
    required this.signedUrl,
  });

  factory ServiceOrderPdfResult.fromJson(Map<dynamic, dynamic> json) {
    final ok = json['ok'] == true;
    final signedUrl = json['signed_url']?.toString().trim() ?? '';

    if (ok && signedUrl.isEmpty) {
      throw const ServiceOrderPdfException(
        'La orden de servicio no devolvió una URL válida.',
      );
    }

    return ServiceOrderPdfResult(
      ok: ok,
      documentType: json['document_type']?.toString() ?? '',
      ticketNumber: json['ticket_number']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      signedUrl: signedUrl,
    );
  }
}

class ServiceOrderPdfException implements Exception {
  final String message;
  final int? status;

  const ServiceOrderPdfException(this.message, {this.status});

  @override
  String toString() => message;
}

class ServiceOrderPdfService {
  ServiceOrderPdfService({
    SupabaseClient? supabase,
    ServiceOrderPdfInvoke? invoke,
  }) : _supabase = supabase,
       _invoke = invoke;

  final SupabaseClient? _supabase;
  final ServiceOrderPdfInvoke? _invoke;

  Future<ServiceOrderPdfResult> generate({
    required String ticketId,
    String? documentType,
  }) async {
    final cleanTicketId = ticketId.trim();
    if (cleanTicketId.isEmpty) {
      throw const ServiceOrderPdfException('Solicitud inválida.', status: 400);
    }

    final payload = <String, dynamic>{
      'ticket_id': cleanTicketId,
      if (documentType != null && documentType.trim().isNotEmpty)
        'document_type': documentType.trim(),
    };

    final response = await (_invoke ?? _invokeEdgeFunction).call(payload);

    if (response.status >= 400) {
      throw ServiceOrderPdfException(
        friendlyMessageForStatus(response.status),
        status: response.status,
      );
    }

    if (response.data is! Map) {
      throw const ServiceOrderPdfException(
        'No se pudo generar la orden de servicio.',
      );
    }

    final result = ServiceOrderPdfResult.fromJson(response.data as Map);
    if (!result.ok) {
      throw const ServiceOrderPdfException(
        'No se pudo generar la orden de servicio.',
      );
    }
    return result;
  }

  Future<ServiceOrderPdfRawResponse> _invokeEdgeFunction(
    Map<String, dynamic> body,
  ) async {
    final supabase = _supabase ?? Supabase.instance.client;
    final response = await supabase.functions.invoke(
      'generate-service-order-pdf',
      body: body,
    );
    return ServiceOrderPdfRawResponse(
      status: response.status,
      data: response.data,
    );
  }

  static String friendlyMessageForStatus(int status) {
    switch (status) {
      case 400:
        return 'Solicitud inválida.';
      case 401:
        return 'Tu sesión expiró. Inicia sesión nuevamente.';
      case 403:
        return 'No tienes acceso a esta orden de servicio.';
      case 404:
        return 'No se encontró el ticket de servicio.';
      default:
        return 'No se pudo generar la orden de servicio.';
    }
  }
}
