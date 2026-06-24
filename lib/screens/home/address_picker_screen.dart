import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/address_service.dart';
import '../../core/theme/app_colors.dart';

// Colores locales (no conflictan con home_screen.dart)
const _kPrimaryAddr = AppColors.primary;
const _kNavyAddr = AppColors.textPrimary;

class AddressPickerScreen extends StatefulWidget {
  const AddressPickerScreen({super.key});

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  final _mapController = MapController();
  final _labelController = TextEditingController(text: 'Mi dirección');
  final _searchController = TextEditingController();

  LatLng _pinLocation = const LatLng(20.9674, -89.5926); // Default: Mérida
  String _currentAddress = 'Mueve el mapa para elegir tu ubicación';
  bool _loadingGps = false;
  bool _loadingAddress = false;
  bool _saving = false;
  List<ClientAddress> _savedAddresses = [];
  bool _loadingSaved = true;

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _labelController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddresses() async {
    setState(() => _loadingSaved = true);
    try {
      final list = await AddressService.getAddresses();
      if (mounted)
        setState(() {
          _savedAddresses = list;
          _loadingSaved = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Activa el GPS de tu dispositivo');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Necesitas permitir el acceso a tu ubicación');
      }

      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      _mapController.move(latLng, 15);
      setState(() => _pinLocation = latLng);
      await _reverseGeocode(latLng);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade400),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
    setState(() => _loadingAddress = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${latLng.latitude}&lon=${latLng.longitude}&zoom=18&addressdetails=1',
      );
      final res = await http.get(
        url,
        headers: {'User-Agent': 'GoMedicalApp/1.0'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data != null && data['address'] != null) {
          final a = data['address'] as Map<String, dynamic>;
          final road = (a['road'] ?? a['pedestrian'] ?? '') as String;
          final house = (a['house_number'] ?? '') as String;
          final city =
              (a['city'] ?? a['town'] ?? a['village'] ?? a['county'] ?? '')
                  as String;
          final stateVal = (a['state'] ?? '') as String;
          final pc = (a['postcode'] ?? '') as String;
          final streetPart = house.isNotEmpty ? '$road $house' : road;
          final parts = [
            streetPart,
            city,
            stateVal,
          ].where((s) => s.isNotEmpty).toList();
          final full = parts.join(', ');
          if (mounted) {
            setState(
              () => _currentAddress = full.isNotEmpty
                  ? full
                  : (data['display_name'] as String?) ??
                        'Dirección desconocida',
            );
          }
          _city = city;
          _state = stateVal;
          _postalCode = pc;
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  String _city = '', _state = '', _postalCode = '';

  Future<void> _saveAndReturn() async {
    setState(() => _saving = true);
    try {
      final addr = await AddressService.saveAddress(
        label: _labelController.text.trim().isEmpty
            ? 'Mi dirección'
            : _labelController.text.trim(),
        address: _currentAddress,
        city: _city.isEmpty ? null : _city,
        state: _state.isEmpty ? null : _state,
        postalCode: _postalCode.isEmpty ? null : _postalCode,
        latitude: _pinLocation.latitude,
        longitude: _pinLocation.longitude,
        isDefault: true,
      );
      if (mounted) Navigator.of(context).pop(addr);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAddress(ClientAddress addr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar dirección'),
        content: Text('¿Eliminar "${addr.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await AddressService.deleteAddress(addr.id);
      _loadSavedAddresses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: _kPrimaryAddr,
        foregroundColor: Colors.white,
        title: const Text(
          'Elige tu dirección',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Map ──────────────────────────────────────────
          SizedBox(
            height: 240,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pinLocation,
                    initialZoom: 13,
                    // flutter_map v7: onPositionChanged recibe (MapCamera, bool)
                    onPositionChanged: (camera, hasGesture) {
                      setState(() => _pinLocation = camera.center);
                    },
                    onMapEvent: (event) {
                      // Geocodificar solo cuando el usuario soltó el mapa
                      if (event is MapEventMoveEnd) {
                        _reverseGeocode(_pinLocation);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.gomedical.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _pinLocation,
                          child: const Icon(
                            Icons.location_pin,
                            color: _kPrimaryAddr,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // GPS button
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    onPressed: _loadingGps ? null : _useCurrentLocation,
                    child: _loadingGps
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kPrimaryAddr,
                            ),
                          )
                        : const Icon(Icons.my_location, color: _kPrimaryAddr),
                  ),
                ),
              ],
            ),
          ),

          // ── Dirección detectada ────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: _kPrimaryAddr, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: _loadingAddress
                      ? const Text(
                          'Buscando dirección...',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      : Text(
                          _currentAddress,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                        ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Nombre de la dirección ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: 'Nombre de esta dirección',
                hintText: 'Ej: Clínica, Consultorio, Casa...',
                prefixIcon: const Icon(
                  Icons.label_outline,
                  color: _kPrimaryAddr,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kPrimaryAddr, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),

          // ── Botón confirmar ────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: (_saving || _loadingAddress) ? null : _saveAndReturn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Confirmar esta dirección',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),

          // ── Direcciones guardadas ──────────────────────
          if (!_loadingSaved && _savedAddresses.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Direcciones guardadas',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _savedAddresses.length,
                itemBuilder: (_, i) {
                  final a = _savedAddresses[i];
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: a.isDefault
                            ? _kPrimaryAddr.withOpacity(0.5)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: a.isDefault
                            ? _kPrimaryAddr.withOpacity(0.1)
                            : Colors.grey.shade100,
                        child: Icon(
                          Icons.location_on,
                          size: 18,
                          color: a.isDefault
                              ? _kPrimaryAddr
                              : Colors.grey.shade500,
                        ),
                      ),
                      title: Text(
                        a.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: a.isDefault ? _kNavyAddr : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        a.displayText,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (a.isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _kPrimaryAddr,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Principal',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red.shade300,
                            ),
                            onPressed: () => _deleteAddress(a),
                          ),
                        ],
                      ),
                      onTap: () {
                        AddressService.setDefault(
                          a.id,
                        ).then((_) => Navigator.of(context).pop(a));
                      },
                    ),
                  );
                },
              ),
            ),
          ] else if (_loadingSaved)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: _kPrimaryAddr),
              ),
            ),
        ],
      ),
    );
  }
}
