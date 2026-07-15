import 'dart:convert';

import 'package:flutter/services.dart';

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

  static Map<String, dynamic> _fileConfig = const {};

  static Future<void> init() async {
    try {
      final raw = await rootBundle.loadString('dart_defines.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _fileConfig = decoded;
      }
    } catch (_) {
      _fileConfig = const {};
    }
  }

  static String _value(String key, String envValue) {
    if (envValue.isNotEmpty) return envValue;
    final fileValue = _fileConfig[key];
    if (fileValue is String) return fileValue;
    return '';
  }

  static String get supabaseUrl => _value('SUPABASE_URL', _envSupabaseUrl);

  static String get supabaseAnonKey =>
      _value('SUPABASE_ANON_KEY', _envSupabaseAnonKey);

  static String get androidClientId =>
      _value('GOOGLE_ANDROID_CLIENT_ID', _envAndroidClientId);

  static String get webClientId =>
      _value('GOOGLE_WEB_CLIENT_ID', _envWebClientId);

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
