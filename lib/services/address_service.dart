import 'package:supabase_flutter/supabase_flutter.dart';

class ClientAddressDetails {
  final String streetAddress;
  final String municipality;
  final String locality;
  final String neighborhood;
  final String interior;
  final String instructions;
  final String recipientName;
  final String recipientPhone;

  const ClientAddressDetails({
    this.streetAddress = '',
    this.municipality = '',
    this.locality = '',
    this.neighborhood = '',
    this.interior = '',
    this.instructions = '',
    this.recipientName = '',
    this.recipientPhone = '',
  });

  factory ClientAddressDetails.fromStoredAddress(
    String storedAddress, {
    String? municipality,
  }) {
    final values = <String, String>{};
    final unlabeled = <String>[];
    String? activeMultilineField;

    for (final rawPart in storedAddress.split(RegExp(r'\r?\n|,\s+'))) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;

      final separator = part.indexOf(':');
      if (separator > 0) {
        final rawLabel = part.substring(0, separator).trim().toLowerCase();
        final value = part.substring(separator + 1).trim();
        final label = switch (rawLabel) {
          'dirección' || 'direccion' => 'street',
          'interior' => 'interior',
          'colonia' || 'barrio' => 'neighborhood',
          'localidad' => 'locality',
          'municipio' || 'ciudad' => 'municipality',
          'estado' => 'state',
          'código postal' || 'codigo postal' => 'postalCode',
          'indicaciones' => 'instructions',
          'recibe' => 'recipientName',
          'teléfono' || 'telefono' => 'recipientPhone',
          _ => null,
        };
        if (label != null) {
          values[label] = value;
          activeMultilineField = label == 'instructions' ? label : null;
          continue;
        }
      }

      if (part.toLowerCase().startsWith('interior ')) {
        values['interior'] = part.substring('interior '.length).trim();
        activeMultilineField = null;
      } else if (activeMultilineField != null) {
        values[activeMultilineField] = '${values[activeMultilineField]}, $part';
      } else {
        unlabeled.add(part);
      }
    }

    final normalizedMunicipality = municipality?.trim() ?? '';
    values['street'] ??= unlabeled.isNotEmpty ? unlabeled.removeAt(0) : '';
    unlabeled.removeWhere(
      (part) =>
          normalizedMunicipality.isNotEmpty &&
          part.toLowerCase() == normalizedMunicipality.toLowerCase(),
    );
    values['neighborhood'] ??= unlabeled.isNotEmpty
        ? unlabeled.removeAt(0)
        : '';
    values['locality'] ??= unlabeled.isNotEmpty ? unlabeled.removeAt(0) : '';
    values['municipality'] ??= normalizedMunicipality;

    return ClientAddressDetails(
      streetAddress: values['street'] ?? '',
      municipality: values['municipality'] ?? '',
      locality: values['locality'] ?? '',
      neighborhood: values['neighborhood'] ?? '',
      interior: values['interior'] ?? '',
      instructions: values['instructions'] ?? '',
      recipientName: values['recipientName'] ?? '',
      recipientPhone: values['recipientPhone'] ?? '',
    );
  }

  String toStoredAddress({required String state, required String postalCode}) {
    return <String>[
      'Dirección: $streetAddress',
      if (interior.isNotEmpty) 'Interior: $interior',
      if (neighborhood.isNotEmpty) 'Colonia: $neighborhood',
      if (locality.isNotEmpty) 'Localidad: $locality',
      if (municipality.isNotEmpty) 'Municipio: $municipality',
      if (state.isNotEmpty) 'Estado: $state',
      if (postalCode.isNotEmpty) 'Código postal: $postalCode',
      if (instructions.isNotEmpty) 'Indicaciones: $instructions',
      if (recipientName.isNotEmpty) 'Recibe: $recipientName',
      if (recipientPhone.isNotEmpty) 'Teléfono: $recipientPhone',
    ].join('\n');
  }
}

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
  final ClientAddressDetails details;

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
    ClientAddressDetails? details,
  }) : details =
           details ??
           ClientAddressDetails.fromStoredAddress(address, municipality: city);

  factory ClientAddress.fromMap(Map<String, dynamic> m) {
    final address = m['address'] as String;
    final city = m['city'] as String?;
    return ClientAddress(
      id: m['id'] as String,
      clientId: m['client_id'] as String,
      label: m['label'] as String? ?? 'Dirección de entrega',
      address: address,
      city: city,
      state: m['state'] as String?,
      postalCode: m['postal_code'] as String?,
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      isDefault: m['is_default'] as bool? ?? false,
      details: ClientAddressDetails.fromStoredAddress(
        address,
        municipality: city,
      ),
    );
  }

  String get displayText {
    final normalizedCity = city?.trim() ?? '';
    final normalizedPostalCode = postalCode?.trim() ?? '';
    if (normalizedCity.isNotEmpty && normalizedPostalCode.isNotEmpty) {
      return '$normalizedCity, CP $normalizedPostalCode';
    }
    if (normalizedCity.isNotEmpty) return normalizedCity;
    return address.length > 40 ? '${address.substring(0, 40)}...' : address;
  }

  String get deliveryLabel {
    final normalizedPostalCode = postalCode?.trim() ?? '';
    return normalizedPostalCode.isNotEmpty
        ? 'CP $normalizedPostalCode'
        : displayText;
  }
}

class AddressService {
  static final _db = Supabase.instance.client;

  static Future<String?> _getEffectiveClientId() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await _db
          .from('profiles')
          .select('client_id')
          .eq('id', user.id)
          .maybeSingle();
      final clientId = profile?['client_id'] as String?;
      if (clientId != null && clientId.isNotEmpty) {
        return clientId;
      }
    } catch (_) {
      // Fallback silencioso al auth.uid cuando aún no existe el perfil enlazado.
    }

    return user.id;
  }

  static Future<List<ClientAddress>> getAddresses() async {
    final clientId = await _getEffectiveClientId();
    if (clientId == null) return [];
    final data = await _db
        .from('client_addresses')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => ClientAddress.fromMap(e)).toList();
  }

  static Future<ClientAddress?> getDefaultAddress() async {
    final clientId = await _getEffectiveClientId();
    if (clientId == null) return null;
    var data = await _db
        .from('client_addresses')
        .select()
        .eq('client_id', clientId)
        .eq('is_default', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    data ??= await _db
        .from('client_addresses')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return data != null ? ClientAddress.fromMap(data) : null;
  }

  /// Asegura que el usuario tiene un registro en la tabla 'clients'.
  static Future<void> _ensureClientExists() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    final meta = user.userMetadata;
    try {
      final clientId = await _getEffectiveClientId();
      if (clientId == null) return;
      final nameStr = (meta?['full_name'] ?? meta?['name'] ?? '').toString();
      await _db
          .from('clients')
          .upsert(
            {
              'id': clientId,
              'business_name': nameStr.isEmpty ? 'Usuario' : nameStr,
              'contact_name': nameStr,
              'email': user.email ?? '',
              'is_active': true,
              'preferred_currency': 'MXN',
              'country': 'México',
            },
            onConflict: 'id',
            ignoreDuplicates: true,
          );
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
    final clientId = await _getEffectiveClientId();
    if (clientId == null) throw Exception('No hay sesión activa');

    // Garantizar que el perfil existe antes de insertar
    await _ensureClientExists();

    if (isDefault) {
      await _db
          .from('client_addresses')
          .update({'is_default': false})
          .eq('client_id', clientId);
    }

    final payload = {
      'client_id': clientId,
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

  static Future<ClientAddress> updateAddress({
    required String addressId,
    required String label,
    required String address,
    String? city,
    String? state,
    String? postalCode,
    double? latitude,
    double? longitude,
    bool isDefault = true,
  }) async {
    final clientId = await _getEffectiveClientId();
    if (clientId == null) throw Exception('No hay sesión activa');

    if (isDefault) {
      await _db
          .from('client_addresses')
          .update({'is_default': false})
          .eq('client_id', clientId);
    }

    final payload = {
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
        .update(payload)
        .eq('id', addressId)
        .eq('client_id', clientId)
        .select()
        .single();
    return ClientAddress.fromMap(data);
  }

  static Future<void> setDefault(String addressId) async {
    final clientId = await _getEffectiveClientId();
    if (clientId == null) return;
    // Quitar default de todas
    await _db
        .from('client_addresses')
        .update({'is_default': false})
        .eq('client_id', clientId);
    // Poner default en la elegida
    await _db
        .from('client_addresses')
        .update({'is_default': true})
        .eq('id', addressId)
        .eq('client_id', clientId);
  }

  static Future<void> deleteAddress(String addressId) async {
    final clientId = await _getEffectiveClientId();
    if (clientId == null) return;
    final deleted = await _db
        .from('client_addresses')
        .delete()
        .eq('id', addressId)
        .eq('client_id', clientId)
        .select('is_default')
        .maybeSingle();

    if (deleted?['is_default'] == true) {
      final fallback = await _db
          .from('client_addresses')
          .select('id')
          .eq('client_id', clientId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final fallbackId = fallback?['id'] as String?;
      if (fallbackId != null) {
        await _db
            .from('client_addresses')
            .update({'is_default': true})
            .eq('id', fallbackId)
            .eq('client_id', clientId);
      }
    }
  }
}
