import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper centralizado para resolver la identidad efectiva del cliente.
///
/// Algunas tablas de negocio cuelgan de `profiles.client_id` y otras
/// instalaciones antiguas aún dependen de `auth.uid()`. Este helper mantiene
/// el mismo fallback conservador para no romper flujos existentes.
class AuthIdentityService {
  static final _client = Supabase.instance.client;

  static String? get currentUserId => _client.auth.currentUser?.id;

  static Future<String?> getEffectiveClientId() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await _client
          .from('profiles')
          .select('client_id')
          .eq('id', user.id)
          .maybeSingle();
      final clientId = profile?['client_id'] as String?;
      if (clientId != null && clientId.isNotEmpty) {
        return clientId;
      }
    } catch (_) {
      // Fallback silencioso a auth.uid para instalaciones con perfil incompleto.
    }

    return user.id;
  }
}
