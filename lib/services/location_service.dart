import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_identity_service.dart';

class LocationService {
  /// Solicita permisos y obtiene la posición actual del dispositivo
  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Los servicios de ubicación están deshabilitados.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Los permisos de ubicación fueron denegados.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Los permisos de ubicación están denegados permanentemente.',
      );
    }

    return await Geolocator.getCurrentPosition();
  }

  /// Obtiene la dirección (Ciudad, CP) usando OpenStreetMap Nominatim
  static Future<String?> getAddressFromCoordinates(
    double lat,
    double lon,
  ) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'GoMedicalApp/1.0', // Nominatim requires a User-Agent
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['address'] != null) {
          final address = data['address'];
          final city =
              address['city'] ??
              address['town'] ??
              address['village'] ??
              address['county'] ??
              '';
          final postcode = address['postcode'] ?? '';

          if (city.isNotEmpty && postcode.isNotEmpty) {
            return '$city, CP: $postcode';
          } else if (city.isNotEmpty) {
            return city;
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Guarda la dirección en la tabla clients de Supabase
  static Future<void> saveAddressToSupabase(String address) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final clientId =
            await AuthIdentityService.getEffectiveClientId() ?? user.id;
        await Supabase.instance.client
            .from('clients')
            .update({'address': address})
            .eq('id', clientId);
      }
    } catch (e) {
      // Ignorar errores silenciosamente para no interrumpir
    }
  }

  /// Obtiene la dirección guardada del usuario
  static Future<String?> getSavedAddress() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final clientId =
            await AuthIdentityService.getEffectiveClientId() ?? user.id;
        final response = await Supabase.instance.client
            .from('clients')
            .select('address')
            .eq('id', clientId)
            .maybeSingle();

        if (response != null && response['address'] != null) {
          return response['address'] as String;
        }
      }
    } catch (e) {
      // Ignorar
    }
    return null;
  }
}
