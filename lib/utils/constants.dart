class Constants {
  static const String _envSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String _envSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const String _envAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );
  static const String _envWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static Future<void> init() async {}

  static String get supabaseUrl => _envSupabaseUrl;

  static String get supabaseAnonKey => _envSupabaseAnonKey;

  static String get androidClientId => _envAndroidClientId;

  static String get webClientId => _envWebClientId;

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasGoogleMobileConfig =>
      androidClientId.isNotEmpty && webClientId.isNotEmpty;

  static List<String> get missingSupabaseKeys {
    final missing = <String>[];
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    return missing;
  }
}
