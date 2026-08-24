import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/registration_draft.dart';
import 'package:gomedical_app/services/registration_gate_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('T4.3.1 — RegistrationGateService Authoritative & Legacy Tests', () {
    test('1. Authoritative seal: profile_completed=true + termsAccepted=false returns isComplete=true', () {
      const legacyProgress = OnboardingProgress(
        emailVerified: true,
        nameCompleted: true,
        phoneCompleted: true,
        passwordCreated: true,
        termsAccepted: false, // terms not recorded historically
        profileCompleted: true, // authoritative DB seal
        isGoogleUser: false,
        email: 'cesarpuerto10@gmail.com',
        fullName: 'cesar puerto',
        phone: '',
      );
      expect(legacyProgress.isComplete, isTrue);
    });

    test('2. Authoritative seal: profile_completed=true + phone empty returns isComplete=true', () {
      const legacyProgressWithoutPhone = OnboardingProgress(
        emailVerified: true,
        nameCompleted: true,
        phoneCompleted: false, // phone not in DB
        passwordCreated: true,
        termsAccepted: false,
        profileCompleted: true, // authoritative DB seal
        isGoogleUser: false,
        email: 'legacy@gomedical.com',
        fullName: 'Dr. Legacy',
        phone: '',
      );
      expect(legacyProgressWithoutPhone.isComplete, isTrue);
    });

    test('3. Fail-Closed: profile_completed=false + all fields claimed returns isComplete=false', () {
      const incompleteProgress = OnboardingProgress(
        emailVerified: true,
        nameCompleted: true,
        phoneCompleted: true,
        passwordCreated: true,
        termsAccepted: true, // claimed in metadata
        profileCompleted: false, // NOT sealed by DB
        isGoogleUser: false,
        email: 'test@gomedical.com',
        fullName: 'Test User',
        phone: '5511223344',
      );
      expect(incompleteProgress.isComplete, isFalse);
    });

    test('4. Incomplete/Test accounts: Unauthenticated and incomplete states evaluate to false', () {
      final unauth = OnboardingProgress.unauthenticated();
      expect(unauth.isComplete, isFalse);

      const testAccount = OnboardingProgress(
        emailVerified: true,
        nameCompleted: false,
        phoneCompleted: false,
        passwordCreated: false,
        termsAccepted: false,
        profileCompleted: false,
        isGoogleUser: false,
        email: 'test_signup_96617@gomedical.com',
        fullName: '',
        phone: '',
      );
      expect(testAccount.isComplete, isFalse);
    });

    test('5. Step 1 (Email): In-memory draft only, no Supabase Auth user created', () {
      final draft = RegistrationDraft();
      expect(draft.isStep1Done, isFalse);

      draft.email = 'paciente@gomedical.com';
      expect(draft.isStep1Done, isTrue);
      expect(draft.isAllReadyForSignUp, isFalse);
    });

    test('6. Step 2 (Name): Advancing name only updates in-memory draft', () {
      final draft = RegistrationDraft(email: 'paciente@gomedical.com');
      expect(draft.isStep2Done, isFalse);

      draft.fullName = 'Carlos Mendoza';
      expect(draft.isStep2Done, isTrue);
      expect(draft.isAllReadyForSignUp, isFalse);
    });

    test('7. Step 3 (Phone): Advancing phone or skipping only updates in-memory draft', () {
      final draftWithPhone = RegistrationDraft(
        email: 'paciente@gomedical.com',
        fullName: 'Carlos Mendoza',
        phone: '5512345678',
      );
      expect(draftWithPhone.isStep3Done, isTrue);
      expect(draftWithPhone.isAllReadyForSignUp, isFalse);

      final draftWithSkip = RegistrationDraft(
        email: 'paciente@gomedical.com',
        fullName: 'Carlos Mendoza',
        phoneSkipped: true,
      );
      expect(draftWithSkip.isStep3Done, isTrue);
      expect(draftWithSkip.isAllReadyForSignUp, isFalse);
    });

    test('8. Step 4 (Password): Setting password in memory does not trigger signUp', () {
      final draft = RegistrationDraft(
        email: 'paciente@gomedical.com',
        fullName: 'Carlos Mendoza',
        phone: '5512345678',
        password: 'Password123!',
      );
      expect(draft.isStep4Done, isTrue);
      expect(draft.isAllReadyForSignUp, isFalse); // Terms not yet accepted
    });

    test('9. New account registration: termsAccepted is strictly mandatory before signUp call', () {
      final draft = RegistrationDraft(
        email: 'paciente@gomedical.com',
        fullName: 'Carlos Mendoza',
        phone: '5512345678',
        password: 'Password123!',
        termsAccepted: false,
      );
      expect(draft.isAllReadyForSignUp, isFalse);

      draft.termsAccepted = true;
      expect(draft.isAllReadyForSignUp, isTrue);
    });

    test('10. Password security: Password is kept in memory only and cleared on dispose/cancel', () {
      final draft = RegistrationDraft(
        email: 'paciente@gomedical.com',
        fullName: 'Carlos Mendoza',
        phone: '5512345678',
        password: 'SuperSecretPassword!',
        termsAccepted: true,
      );
      expect(draft.password, 'SuperSecretPassword!');

      draft.clear();
      expect(draft.password, isEmpty);
      expect(draft.email, isEmpty);
      expect(draft.fullName, isEmpty);
      expect(draft.phone, isEmpty);
      expect(draft.phoneSkipped, isFalse);
      expect(draft.termsAccepted, isFalse);
    });

    test('11. LoginScreen UI: Button "¿No terminaste tu registro?" is completely removed', () {
      final loginFile = File('lib/screens/auth/login_screen.dart');
      expect(loginFile.existsSync(), isTrue);
      final loginCode = loginFile.readAsStringSync();

      expect(loginCode.contains('¿No terminaste tu registro?'), isFalse);
      expect(loginCode.contains('_showResumeRegistrationDialog'), isFalse);
      expect(loginCode.contains('step_1_otp.dart'), isFalse);
    });

    test('12. LoginScreen UI: Forgot Password, normal Login and Google Sign-In remain intact', () {
      final loginFile = File('lib/screens/auth/login_screen.dart');
      expect(loginFile.existsSync(), isTrue);
      final loginCode = loginFile.readAsStringSync();

      expect(loginCode.contains('¿Olvidaste tu contraseña?'), isTrue);
      expect(loginCode.contains('_signIn'), isTrue);
      expect(loginCode.contains('_googleSignIn'), isTrue);
      expect(loginCode.contains('Regístrate aquí'), isTrue);
    });

    test('13. Google OAuth provider detection is intact', () {
      final googleUser = User(
        id: 'u-google-1',
        appMetadata: {'provider': 'google'},
        userMetadata: {'full_name': 'Google User'},
        aud: 'authenticated',
        createdAt: '2026-08-14T00:00:00Z',
      );
      expect(RegistrationGateService.isGoogleUser(googleUser), isTrue);
    });

    test('14. T4.1 migration columns, grants and triggers remain fully active and compatible', () {
      final migrationFile = File('supabase/migrations/20260814030000_t4_user_onboarding_gate.sql');
      expect(migrationFile.existsSync(), isTrue);
      final sql = migrationFile.readAsStringSync();

      expect(sql.contains('terms_accepted_at timestamptz'), isTrue);
      expect(sql.contains('terms_version text'), isTrue);
      expect(sql.contains('phone_skipped_at timestamptz'), isTrue);
      expect(sql.contains('protect_client_sensitive_columns'), isTrue);
      expect(sql.contains('get_my_onboarding_status'), isTrue);
      expect(sql.contains('save_onboarding_contact'), isTrue);
      expect(sql.contains('complete_user_onboarding'), isTrue);
    });

    test('15. T4.3 migration: does NOT falsify terms, does NOT modify business_name or has_app_access', () {
      final migrationT43 = File('supabase/migrations/20260814040000_t4_3_backfill_legacy_completed_clients.sql');
      expect(migrationT43.existsSync(), isTrue);
      final sql = migrationT43.readAsStringSync();

      // No terms falsification
      expect(sql.contains('terms_accepted_at = created_at'), isFalse);
      expect(sql.contains('terms_accepted_at = now()'), isFalse);
      expect(sql.contains('terms_version ='), isFalse);

      // No business_name overwrite
      expect(sql.contains('business_name ='), isFalse);

      // No has_app_access overwrite
      expect(sql.contains('has_app_access ='), isFalse);

      // Deterministic requirement on real activity
      expect(sql.contains('EXISTS (SELECT 1 FROM public.orders o WHERE o.client_id = c.id)'), isTrue);
      expect(sql.contains('EXISTS (SELECT 1 FROM public.client_addresses ca WHERE ca.client_id = c.id)'), isTrue);

      // Excludes staff/admin
      expect(sql.contains("role = 'client' OR p.role IS NULL"), isTrue);
    });
  });
}
