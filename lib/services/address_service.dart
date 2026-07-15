import 'package:supabase_flutter/supabase_flutter.dart';

class ClientAddress {
  final String id;
  final String clientId;
  final String label;
  final String address;
  final String? city;
  final String? state;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  ClientAddress({
    required this.id,
    required this.clientId,
    required this.label,
    required this.address,
    this.city,
    this.state,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.isDefault = false,
  });

  factory ClientAddress.fromMap(Map<String, dynamic> m) => ClientAddress(
    id: m['id'] as String,
    clientId: m['client_id'] as String,
    label: m['label'] as String? ?? 'Mi dirección',
    address: m['address'] as String,
    city: m['city'] as String?,
    state: m['state'] as String?,
    postalCode: m['postal_code'] as String?,
    latitude: (m['latitude'] as num?)?.toDouble(),
    longitude: (m['longitude'] as num?)?.toDouble(),
    isDefault: m['is_default'] as bool? ?? false,
  );

  String get displayText {
    if (city != null && postalCode != null) return '$city, CP $postalCode';
    if (city != null) return city!;
    return address.length > 40 ? '${address.substring(0, 40)}...' : address;
  }
}

class AddressService {
  static final _db = Supabase.instance.client;

  static Future<List<ClientAddress>> getAddresses() async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final data = await _db
        .from('client_addresses')
        .select()
        .eq('client_id', user.id)
        .order('created_at', ascending: false);
    return (data as List).map((e) => ClientAddress.fromMap(e)).toList();
  }

  static Future<ClientAddress?> getDefaultAddress() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final data = await _db
        .from('client_addresses')
        .select()
        .eq('client_id', user.id)
        .eq('is_default', true)
        .maybeSingle();
    return data != null ? ClientAddress.fromMap(data) : null;
  }

  /// Asegura que el usuario tiene un registro en la tabla 'clients'.
  static Future<void> _ensureClientExists() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    final meta = user.userMetadata;
    try {
      final nameStr = (meta?['full_name'] ?? meta?['name'] ?? '').toString();
      await _db.from('clients').upsert({
        'id': user.id,
        'business_name': nameStr.isEmpty ? 'Usuario' : nameStr,
        'contact_name': nameStr,
        'email': user.email ?? '',
        'is_active': true,
        'preferred_currency': 'MXN',
        'country': 'México',
      }, onConflict: 'id', ignoreDuplicates: true);
    } catch (e) {
      print('Aviso _ensureClientExists: $e');
    }
  }

  static Future<ClientAddress> saveAddress({
    required String label,
    required String address,
    String? city,
    String? state,
    String? postalCode,
    double? latitude,
    double? longitude,
    bool isDefault = true,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('No hay sesión activa');

    // Garantizar que el perfil existe antes de insertar
    await _ensureClientExists();

    final payload = {
      'client_id': user.id,
      'label': label,
      'address': address,
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'latitude': latitude,
      'longitude': longitude,
      'is_default': isDefault,
    };

    final data = await _db
        .from('client_addresses')
        .insert(payload)
        .select()
        .single();
    return ClientAddress.fromMap(data);
  }

  static Future<void> setDefault(String addressId) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    // Quitar default de todas
    await _db
        .from('client_addresses')
        .update({'is_default': false})
        .eq('client_id', user.id);
    // Poner default en la elegida
    await _db
        .from('client_addresses')
        .update({'is_default': true})
        .eq('id', addressId);
  }

  static Future<void> deleteAddress(String addressId) async {
    await _db.from('client_addresses').delete().eq('id', addressId);
  }
}
