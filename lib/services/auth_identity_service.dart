import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper centralizado para resolver la identidad de negocio del cliente.
///
/// `auth.uid()` identifica al usuario autenticado y no debe tratarse como si
/// fuera un `clients.id`. La relación válida se obtiene de
/// `profiles.client_id`.
class AuthIdentityService {
  static final _client = Supabase.instance.client;

  static String? get currentUserId => _client.auth.currentUser?.id;

  static Future<String?> getEffectiveClientId() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return requireLinkedClientId();
  }

  /// Returns the client linked by the backend or throws a clear integration
  /// error. Sensitive business flows must not treat `auth.uid()` as a
  /// `clients.id`.
  static Future<String> requireLinkedClientId() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión para continuar.');
    }

    final profile = await _client
        .from('profiles')
        .select('client_id')
        .eq('id', user.id)
        .maybeSingle();
    final clientId = profile?['client_id'] as String?;

    if (clientId == null || clientId.trim().isEmpty) {
      throw Exception(
        'Tu cuenta todavía no está vinculada a un cliente. '
        'Contacta a soporte para completar el acceso.',
      );
    }

    return clientId;
  }
}
