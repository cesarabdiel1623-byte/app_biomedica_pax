import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum RegistrationGateState { unauthenticated, incomplete, complete }

class OnboardingProgress {
  final bool emailVerified;
  final bool nameCompleted;
  final bool phoneCompleted;
  final bool passwordCreated;
  final bool termsAccepted;
  final bool profileCompleted;
  final bool isGoogleUser;
  final String email;
  final String fullName;
  final String phone;
  final String? role;

  const OnboardingProgress({
    required this.emailVerified,
    required this.nameCompleted,
    required this.phoneCompleted,
    required this.passwordCreated,
    required this.termsAccepted,
    required this.profileCompleted,
    required this.isGoogleUser,
    required this.email,
    required this.fullName,
    required this.phone,
    this.role,
  });

  /// Certificación autoritativa: La base de datos es la única fuente de verdad.
  /// Si profileCompleted es true, la cuenta está autorizada para acceder a Home.
  bool get isComplete => profileCompleted;

  factory OnboardingProgress.unauthenticated() {
    return const OnboardingProgress(
      emailVerified: false,
      nameCompleted: false,
      phoneCompleted: false,
      passwordCreated: false,
      termsAccepted: false,
      profileCompleted: false,
      isGoogleUser: false,
      email: '',
      fullName: '',
      phone: '',
      role: null,
    );
  }
}

class RegistrationGateService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Checks whether a user authenticated via Google
  static bool isGoogleUser(User? user) {
    if (user == null) return false;
    final provider = user.appMetadata['provider'];
    if (provider == 'google') return true;
    final identities = user.identities;
    if (identities != null) {
      for (final identity in identities) {
        if (identity.provider == 'google') return true;
      }
    }
    return false;
  }

  /// Evaluates current onboarding state from Supabase DB (authoritative)
  /// Fail-Closed: En caso de error, timeout o inconsistencia, siempre devuelve incomplete
  static Future<RegistrationGateState> evaluateGateState({User? user}) async {
    final currentUser = user ?? _client.auth.currentUser;
    if (currentUser == null) {
      return RegistrationGateState.unauthenticated;
    }

    try {
      final progress = await loadOnboardingProgress(user: currentUser);
      if (progress.isComplete && progress.profileCompleted) {
        return RegistrationGateState.complete;
      }
      return RegistrationGateState.incomplete;
    } catch (e) {
      debugPrint(
        'RegistrationGateService.evaluateGateState error (failing closed): $e',
      );
      return RegistrationGateState.incomplete;
    }
  }

  /// Loads full onboarding progress from authoritative DB records
  static Future<OnboardingProgress> loadOnboardingProgress({User? user}) async {
    final currentUser = user ?? _client.auth.currentUser;
    if (currentUser == null) {
      return OnboardingProgress.unauthenticated();
    }

    final isGoogle = isGoogleUser(currentUser);
    final userEmail = currentUser.email ?? '';
    final metadata = currentUser.userMetadata ?? {};

    // 1. Intentar leer desde RPC get_my_onboarding_status
    try {
      final rpcRes = await _client.rpc('get_my_onboarding_status');
      if (rpcRes is Map<String, dynamic> && rpcRes['authenticated'] == true) {
        final profileCompleted = rpcRes['profile_completed'] == true;
        final hasValidName = rpcRes['has_valid_name'] == true;
        final hasValidPhone = rpcRes['has_valid_phone'] == true;
        final phoneSkipped =
            rpcRes['phone_skipped'] == true ||
            metadata['phone_skipped'] == true;
        final termsAccepted = rpcRes['terms_accepted'] == true;

        final role = (rpcRes['role'] as String?) ?? 'client';
        final fullName = (rpcRes['full_name'] as String?) ?? '';
        final phone = (rpcRes['phone'] as String?) ?? '';

        return OnboardingProgress(
          emailVerified: userEmail.isNotEmpty,
          nameCompleted: hasValidName,
          phoneCompleted: hasValidPhone || phoneSkipped,
          passwordCreated:
              isGoogle || metadata['password_set'] == true || profileCompleted,
          termsAccepted: termsAccepted,
          profileCompleted: profileCompleted,
          isGoogleUser: isGoogle,
          email: userEmail,
          fullName: fullName == 'Sin especificar' ? '' : fullName,
          phone: phone,
          role: role,
        );
      }
    } catch (_) {
      // Fallback a consulta directa por tablas si la RPC aún no está aplicada
    }

    // 2. Fallback resiliente: consultar profiles y clients directamente
    String dbFullName = '';
    String dbPhone = '';
    String dbRole = 'client';
    bool profileCompleted = false;
    bool termsAccepted = false;
    bool phoneSkipped = metadata['phone_skipped'] == true;

    try {
      final profileRes = await _client
          .from('profiles')
          .select('full_name, phone, client_id, role')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (profileRes != null) {
        dbFullName = (profileRes['full_name'] as String?) ?? '';
        dbPhone = (profileRes['phone'] as String?) ?? '';
        dbRole = (profileRes['role'] as String?) ?? 'client';
        final clientId = profileRes['client_id'] as String?;

        if (clientId != null && clientId.isNotEmpty) {
          final clientRes = await _client
              .from('clients')
              .select('profile_completed, terms_accepted_at, phone_skipped_at')
              .eq('id', clientId)
              .maybeSingle();

          if (clientRes != null) {
            profileCompleted = clientRes['profile_completed'] == true;
            if (clientRes['terms_accepted_at'] != null) {
              termsAccepted = true;
            }
            if (clientRes['phone_skipped_at'] != null) {
              phoneSkipped = true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('RegistrationGateService: error consultando DB: $e');
    }

    final hasValidName =
        dbFullName.isNotEmpty && dbFullName != 'Sin especificar';
    final hasValidPhone =
        dbPhone.isNotEmpty ||
        (currentUser.phone != null && currentUser.phone!.isNotEmpty);
    final isPhoneDone = hasValidPhone || phoneSkipped;

    return OnboardingProgress(
      emailVerified: userEmail.isNotEmpty,
      nameCompleted: hasValidName,
      phoneCompleted: isPhoneDone,
      passwordCreated: isGoogle || profileCompleted,
      termsAccepted: termsAccepted,
      profileCompleted: profileCompleted,
      isGoogleUser: isGoogle,
      email: userEmail,
      fullName: dbFullName == 'Sin especificar' ? '' : dbFullName,
      phone: dbPhone,
      role: dbRole,
    );
  }

  /// Guarda el nombre del usuario de forma persistente en profiles y clients
  static Future<bool> saveContactName(String fullName) async {
    final cleanName = fullName.trim();
    if (cleanName.length < 2 || cleanName == 'Sin especificar') return false;

    // 1. Intentar RPC save_onboarding_contact
    try {
      await _client.rpc(
        'save_onboarding_contact',
        params: {'p_full_name': cleanName},
      );
      return true;
    } catch (_) {}

    // 2. Fallback a update_my_profile_contact o updateUser
    try {
      await _client.rpc(
        'update_my_profile_contact',
        params: {'p_full_name': cleanName, 'p_phone': null},
      );
    } catch (_) {}

    try {
      await _client.auth.updateUser(
        UserAttributes(data: {'full_name': cleanName}),
      );
      return true;
    } catch (e) {
      debugPrint('RegistrationGateService: error guardando nombre: $e');
      return false;
    }
  }

  /// Guarda el teléfono del usuario o marca el estado de omitido
  static Future<bool> saveContactPhone(
    String? phone, {
    bool skipped = false,
  }) async {
    try {
      await _client.rpc(
        'save_onboarding_contact',
        params: {'p_phone': phone, 'p_phone_skipped': skipped},
      );
      return true;
    } catch (_) {}

    try {
      if (skipped) {
        await _client.auth.updateUser(
          UserAttributes(data: {'phone_skipped': true}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('RegistrationGateService: error guardando teléfono: $e');
      return false;
    }
  }

  /// Finaliza de forma autoritativa el onboarding invocando complete_user_onboarding
  static Future<bool> completeOnboarding({
    required String fullName,
    String? phone,
    bool phoneSkipped = false,
    String? termsVersion,
  }) async {
    final cleanName = fullName.trim();
    if (cleanName.length < 2) return false;

    // 1. Intentar RPC complete_user_onboarding (vía autorizada)
    try {
      final params = <String, dynamic>{
        'p_full_name': cleanName,
        'p_phone': phone,
        'p_phone_skipped': phoneSkipped,
      };
      if (termsVersion != null && termsVersion.isNotEmpty) {
        params['p_terms_version'] = termsVersion;
      }

      final res = await _client.rpc('complete_user_onboarding', params: params);
      if (res is Map && res['success'] == true) {
        // Sincronizar metadata local
        await _client.auth.updateUser(
          UserAttributes(
            data: {'terms_accepted': true, 'full_name': cleanName},
          ),
        );
        await _client.auth.refreshSession();
        return true;
      }
    } catch (e) {
      debugPrint(
        'RegistrationGateService: error en RPC complete_user_onboarding: $e',
      );
      return false;
    }

    return false;
  }

  static bool skippedPhoneFallback(bool skipped) => skipped;

  /// Envía OTP para nuevo registro o para reanudar cuenta existente
  static Future<void> sendNewOrResumeOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: true,
    );
  }

  /// Envía OTP estrictamente para reanudar registro de una cuenta ya creada
  static Future<void> sendResumeOtpOnly(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: false,
    );
  }
}
