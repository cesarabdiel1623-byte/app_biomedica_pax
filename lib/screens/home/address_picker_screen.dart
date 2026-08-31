import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/address_service.dart';

// Colores locales (no conflictan con home_screen.dart)
const _kPrimaryAddr = Color(0xFF024C8B);
const _kNavyAddr = Color(0xFF024C8B);

class AddressPickerScreen extends StatefulWidget {
  const AddressPickerScreen({super.key});

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  final _mapController = MapController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _localityController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _interiorController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _recipientNameController = TextEditingController();
  final _recipientPhoneController = TextEditingController();

  LatLng _pinLocation = const LatLng(20.9674, -89.5926); // Default: Mérida
  String _currentAddress = 'Mueve el mapa para elegir tu ubicación';
  bool _loadingGps = false;
  bool _loadingAddress = false;
  bool _saving = false;
  List<ClientAddress> _savedAddresses = [];
  ClientAddress? _selectedAddress;
  bool _loadingSaved = true;
  bool _showAddressForm = false;
  bool _loadingNeighborhoods = false;
  bool _showNeighborhoodOptions = false;
  List<String> _neighborhoodOptions = [];
  final Map<String, List<String>> _neighborhoodCache = {};
  String? _lastNeighborhoodPostalCode;
  Timer? _mapMoveDebounce;
  ClientAddress? _editingAddress;

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  @override
  void dispose() {
    _mapMoveDebounce?.cancel();
    _mapController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _localityController.dispose();
    _neighborhoodController.dispose();
    _interiorController.dispose();
    _instructionsController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddresses() async {
    setState(() => _loadingSaved = true);
    try {
      final list = await AddressService.getAddresses();
      if (mounted) {
        ClientAddress? selected;
        for (final address in list) {
          if (address.isDefault) {
            selected = address;
            break;
          }
        }
        selected ??= list.isNotEmpty ? list.first : null;
        setState(() {
          _savedAddresses = list;
          _selectedAddress = selected;
          _loadingSaved = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSaved = false);
      }
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

  Future<List<String>> _fetchNeighborhoods(String postalCode) async {
    final cached = _neighborhoodCache[postalCode];
    if (cached != null) return cached;

    try {
      final response = await http.get(
        Uri.parse('https://postali.app/api/v1/mx/cp/$postalCode'),
        headers: {'User-Agent': 'GoMedicalApp/1.0'},
      );
      if (response.statusCode != 200) return const [];
      final data =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final settlements = data['asentamientos'] as List<dynamic>? ?? const [];
      final names =
          settlements
              .map(
                (item) =>
                    (item as Map<String, dynamic>)['nombre']
                        ?.toString()
                        .trim() ??
                    '',
              )
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      _neighborhoodCache[postalCode] = names;
      return names;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _refreshNeighborhoods(
    String postalCode, {
    String? detectedNeighborhood,
  }) async {
    final detected = detectedNeighborhood?.trim() ?? '';
    if (!RegExp(r'^\d{5}$').hasMatch(postalCode)) {
      if (detected.isNotEmpty) {
        _neighborhoodController.text = detected;
      }
      return;
    }
    final postalCodeChanged = _lastNeighborhoodPostalCode != postalCode;
    _lastNeighborhoodPostalCode = postalCode;
    if (mounted) setState(() => _loadingNeighborhoods = true);

    final options = await _fetchNeighborhoods(postalCode);
    if (!mounted) return;

    setState(() {
      _neighborhoodOptions = detected.isNotEmpty && !options.contains(detected)
          ? [detected, ...options]
          : options;
      if (detected.isNotEmpty) {
        _neighborhoodController.text = detected;
      } else if (options.length == 1) {
        _neighborhoodController.text = options.first;
      } else if (postalCodeChanged) {
        _neighborhoodController.clear();
      }
      _loadingNeighborhoods = false;
    });
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
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data != null && data['address'] != null) {
          final a = data['address'] as Map<String, dynamic>;
          final road = (a['road'] ?? a['pedestrian'] ?? '') as String;
          final house = (a['house_number'] ?? '') as String;
          final locality =
              (a['city'] ?? a['town'] ?? a['village'] ?? '') as String;
          final municipality =
              (a['municipality'] ?? a['county'] ?? locality) as String;
          final neighborhood =
              (a['neighbourhood'] ??
                      a['neighborhood'] ??
                      a['suburb'] ??
                      a['quarter'] ??
                      a['residential'] ??
                      a['city_district'] ??
                      a['borough'] ??
                      a['district'] ??
                      '')
                  as String;
          final stateVal = (a['state'] ?? '') as String;
          final pc = (a['postcode'] ?? '') as String;
          final streetPart = house.isNotEmpty ? '$road $house' : road;
          final parts = [
            streetPart,
            neighborhood,
            locality,
            municipality,
            stateVal,
          ].where((s) => s.isNotEmpty).toSet().toList();
          final full = parts.join(', ');
          if (mounted) {
            final detectedAddress = full.isNotEmpty
                ? full
                : (data['display_name'] as String?) ?? 'Dirección desconocida';
            setState(() => _currentAddress = detectedAddress);
            _addressController.text = streetPart.isNotEmpty
                ? streetPart
                : detectedAddress;
            _cityController.text = municipality;
            _localityController.text = locality;
            _stateController.text = stateVal;
            _postalCodeController.text = pc;
          }
          await _refreshNeighborhoods(pc, detectedNeighborhood: neighborhood);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  void _scheduleReverseGeocode(LatLng latLng) {
    _mapMoveDebounce?.cancel();
    _mapMoveDebounce = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        _reverseGeocode(latLng);
      }
    });
  }

  void _toggleNeighborhoodOptions() {
    if (_neighborhoodOptions.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _showNeighborhoodOptions = !_showNeighborhoodOptions;
    });
  }

  void _selectNeighborhood(String neighborhood) {
    setState(() {
      _neighborhoodController.text = neighborhood;
      _showNeighborhoodOptions = false;
    });
  }

  String _composeAddressSummary({
    required String streetAddress,
    required String municipality,
    required String locality,
    required String neighborhood,
    required String state,
  }) {
    return [
      streetAddress,
      if (neighborhood.isNotEmpty) neighborhood,
      if (locality.isNotEmpty && locality != municipality) locality,
      municipality,
      state,
    ].where((part) => part.trim().isNotEmpty).join(', ');
  }

  Future<bool> _confirmAddressDetails(String addressSummary) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: _kNavyAddr,
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      addressSummary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 20,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryAddr,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Guardar dirección',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    return result == true;
  }

  Future<void> _saveAndReturn() async {
    final streetAddress = _addressController.text.trim();
    final municipality = _cityController.text.trim();
    final locality = _localityController.text.trim();
    final neighborhood = _neighborhoodController.text.trim();
    final interior = _interiorController.text.trim();
    final instructions = _instructionsController.text.trim();
    final state = _stateController.text.trim();
    final postalCode = _postalCodeController.text.trim();
    final recipientName = _recipientNameController.text.trim();
    final recipientPhone = _recipientPhoneController.text.trim();
    final normalizedPhone = recipientPhone.replaceAll(RegExp(r'[^0-9]'), '');

    if (streetAddress.isEmpty ||
        municipality.isEmpty ||
        state.isEmpty ||
        postalCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa la dirección, municipio, estado y código postal.',
          ),
        ),
      );
      return;
    }
    if (!RegExp(r'^\d{5}$').hasMatch(postalCode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El código postal debe tener 5 dígitos.')),
      );
      return;
    }
    if (recipientName.isEmpty || normalizedPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Agrega el nombre de quien recibe y un teléfono válido.',
          ),
        ),
      );
      return;
    }

    final details = ClientAddressDetails(
      streetAddress: streetAddress,
      municipality: municipality,
      locality: locality,
      neighborhood: neighborhood,
      interior: interior,
      instructions: instructions,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
    );
    final fullAddress = details.toStoredAddress(
      state: state,
      postalCode: postalCode,
    );
    final addressSummary = _composeAddressSummary(
      streetAddress: streetAddress,
      municipality: municipality,
      locality: locality,
      neighborhood: neighborhood,
      state: state,
    );
    final confirmed = await _confirmAddressDetails(addressSummary);
    if (!confirmed || !mounted) return;
    final addressLabel = (_editingAddress?.label.trim().isNotEmpty ?? false)
        ? _editingAddress!.label
        : 'Dirección de entrega';

    setState(() => _saving = true);
    try {
      final editing = _editingAddress;
      final addr = editing == null
          ? await AddressService.saveAddress(
              label: addressLabel,
              address: fullAddress,
              city: municipality,
              state: state,
              postalCode: postalCode,
              latitude: _pinLocation.latitude,
              longitude: _pinLocation.longitude,
              isDefault: true,
            )
          : await AddressService.updateAddress(
              addressId: editing.id,
              label: addressLabel,
              address: fullAddress,
              city: municipality,
              state: state,
              postalCode: postalCode,
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

  Future<void> _confirmSelectedAddress() async {
    final selected = _selectedAddress;
    if (selected == null || _saving) return;
    setState(() => _saving = true);
    try {
      await AddressService.setDefault(selected.id);
      if (mounted) Navigator.of(context).pop(selected);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No pudimos seleccionar la dirección: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openAddressForm() {
    _clearAddressForm();
    setState(() => _showAddressForm = true);
  }

  void _clearAddressForm() {
    _editingAddress = null;
    _addressController.clear();
    _cityController.clear();
    _stateController.clear();
    _postalCodeController.clear();
    _localityController.clear();
    _neighborhoodController.clear();
    _interiorController.clear();
    _instructionsController.clear();
    _recipientNameController.clear();
    _recipientPhoneController.clear();
    _showNeighborhoodOptions = false;
    _neighborhoodOptions = [];
    _lastNeighborhoodPostalCode = null;
    _currentAddress = 'Mueve el mapa para elegir tu ubicación';
  }

  void _editAddress(ClientAddress address) {
    _mapMoveDebounce?.cancel();
    final location = (address.latitude != null && address.longitude != null)
        ? LatLng(address.latitude!, address.longitude!)
        : _pinLocation;
    final details = address.details;
    _editingAddress = address;
    _addressController.text = details.streetAddress;
    _cityController.text = details.municipality.isNotEmpty
        ? details.municipality
        : address.city ?? '';
    _stateController.text = address.state ?? '';
    _postalCodeController.text = address.postalCode ?? '';
    _localityController.text = details.locality;
    _neighborhoodController.text = details.neighborhood;
    _interiorController.text = details.interior;
    _instructionsController.text = details.instructions;
    _recipientNameController.text = details.recipientName;
    _recipientPhoneController.text = details.recipientPhone;
    _showNeighborhoodOptions = false;
    _pinLocation = location;
    _currentAddress = _composeAddressSummary(
      streetAddress: details.streetAddress,
      municipality: _cityController.text,
      locality: details.locality,
      neighborhood: details.neighborhood,
      state: address.state ?? '',
    );
    setState(() => _showAddressForm = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(location, 16);
        _refreshNeighborhoods(
          address.postalCode ?? '',
          detectedNeighborhood: details.neighborhood,
        );
      }
    });
  }

  String _savedAddressTitle(ClientAddress address) {
    final details = address.details;
    final visibleAddress = [
      details.streetAddress,
      details.neighborhood,
      details.municipality,
    ].where((part) => part.trim().isNotEmpty).join(', ');
    if (visibleAddress.isNotEmpty) {
      return visibleAddress;
    }
    return address.displayText;
  }

  void _handleBack() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_showNeighborhoodOptions) {
      setState(() => _showNeighborhoodOptions = false);
      return;
    }
    if (_showAddressForm) {
      setState(() {
        _showAddressForm = false;
        _editingAddress = null;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      labelStyle: const TextStyle(fontSize: 14),
      floatingLabelStyle: const TextStyle(color: _kPrimaryAddr, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kPrimaryAddr, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildAddressSelection() {
    if (_savedAddresses.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: _kPrimaryAddr,
          foregroundColor: Colors.white,
          title: const Text(
            'Dirección de entrega',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const Icon(
                  Icons.location_off_outlined,
                  size: 64,
                  color: Color(0xFF9CA3AF),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Agrega tu primera dirección',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kNavyAddr,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La usaremos para calcular la entrega y mostrar tu código postal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _openAddressForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimaryAddr,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Agregar nueva dirección',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _kPrimaryAddr,
        foregroundColor: Colors.white,
        title: const Text(
          'Dirección de entrega',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Elige dónde quieres recibir tu compra',
                style: TextStyle(
                  color: _kNavyAddr,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Los tiempos y costos de envío dependen de la ubicación.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _savedAddresses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final address = _savedAddresses[index];
                final selected = _selectedAddress?.id == address.id;
                return Stack(
                  children: [
                    Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: selected
                              ? _kPrimaryAddr
                              : const Color(0xFFE5E7EB),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          selected ? 20 : 12,
                          8,
                          12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setState(() => _selectedAddress = address),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? _kPrimaryAddr
                                          : const Color(0xFF9CA3AF),
                                      width: 2,
                                    ),
                                  ),
                                  child: selected
                                      ? const Center(
                                          child: CircleAvatar(
                                            radius: 5,
                                            backgroundColor: _kPrimaryAddr,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() => _selectedAddress = address);
                                  _editAddress(address);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _savedAddressTitle(address),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _kNavyAddr,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          height: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        address.displayText,
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Eliminar dirección',
                              onPressed: () => _deleteAddress(address),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Color(0xFFDC2626),
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Ubicación actual',
                            style: TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _confirmSelectedAddress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimaryAddr,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
                              'Confirmar dirección',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _openAddressForm,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPrimaryAddr,
                        side: const BorderSide(color: _kPrimaryAddr),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Agregar nueva dirección',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSaved) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: _kPrimaryAddr)),
      );
    }
    if (!_showAddressForm) return _buildAddressSelection();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: _kPrimaryAddr,
          foregroundColor: Colors.white,
          leading: IconButton(
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(
            'Nueva dirección',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          elevation: 0,
        ),
        body: ListView(
          children: [
            // ── Map ──────────────────────────────────────────
            SizedBox(
              height: 240,
              child: Stack(
                children: [
                  FlutterMap(
                    key: ValueKey(
                      'address-map-${_editingAddress?.id ?? 'new'}',
                    ),
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _pinLocation,
                      initialZoom: _editingAddress == null ? 13 : 16,
                      // flutter_map v7: onPositionChanged recibe (MapCamera, bool)
                      onPositionChanged: (camera, hasGesture) {
                        setState(() => _pinLocation = camera.center);
                        if (hasGesture) {
                          _scheduleReverseGeocode(camera.center);
                        }
                      },
                      onMapEvent: (event) {
                        // Geocodificar solo cuando el usuario soltó el mapa
                        if (event is MapEventMoveEnd) {
                          _scheduleReverseGeocode(_pinLocation);
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

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _addressController,
                    maxLines: 1,
                    textCapitalization: TextCapitalization.none,
                    decoration: _fieldDecoration(
                      label: 'Dirección o lugar de entrega',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cityController,
                          textCapitalization: TextCapitalization.none,
                          decoration: _fieldDecoration(
                            label: 'Ciudad o municipio',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _postalCodeController,
                          keyboardType: TextInputType.number,
                          maxLength: 5,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (value) {
                            if (value.length == 5) {
                              _refreshNeighborhoods(value);
                            }
                          },
                          decoration: _fieldDecoration(
                            label: 'Código postal',
                          ).copyWith(counterText: ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stateController,
                    textCapitalization: TextCapitalization.none,
                    decoration: _fieldDecoration(label: 'Estado'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _localityController,
                    textCapitalization: TextCapitalization.none,
                    decoration: _fieldDecoration(label: 'Localidad'),
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        children: [
                          TextField(
                            controller: _neighborhoodController,
                            readOnly: _neighborhoodOptions.isNotEmpty,
                            onTap: _neighborhoodOptions.isEmpty
                                ? null
                                : _toggleNeighborhoodOptions,
                            textCapitalization: TextCapitalization.none,
                            decoration:
                                _fieldDecoration(
                                  label: 'Colonia o barrio',
                                ).copyWith(
                                  suffixIcon: _loadingNeighborhoods
                                      ? const Padding(
                                          padding: EdgeInsets.all(14),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              color: _kPrimaryAddr,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : _neighborhoodOptions.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Elegir colonia',
                                          onPressed: _toggleNeighborhoodOptions,
                                          icon: AnimatedRotation(
                                            turns: _showNeighborhoodOptions
                                                ? 0.5
                                                : 0,
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            child: const Icon(
                                              Icons.keyboard_arrow_down,
                                            ),
                                          ),
                                        ),
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _interiorController,
                            textCapitalization: TextCapitalization.none,
                            decoration: _fieldDecoration(
                              label: 'Número interior o departamento',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _instructionsController,
                            maxLines: 3,
                            maxLength: 128,
                            textCapitalization: TextCapitalization.none,
                            decoration: _fieldDecoration(
                              label: 'Indicaciones para la entrega',
                            ).copyWith(alignLabelWithHint: true),
                          ),
                        ],
                      ),
                      if (_showNeighborhoodOptions &&
                          _neighborhoodOptions.isNotEmpty)
                        Positioned(
                          top: 60,
                          left: 0,
                          right: 0,
                          child: Material(
                            color: Colors.transparent,
                            elevation: 10,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFD1D5DB),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _neighborhoodOptions.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: Color(0xFFE5E7EB),
                                ),
                                itemBuilder: (_, index) {
                                  final option = _neighborhoodOptions[index];
                                  final isSelected =
                                      option ==
                                      _neighborhoodController.text.trim();
                                  return InkWell(
                                    onTap: () => _selectNeighborhood(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: TextStyle(
                                                color: _kNavyAddr,
                                                fontSize: 14,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(
                                              Icons.check,
                                              color: _kPrimaryAddr,
                                              size: 20,
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Datos de quien recibe',
                    style: TextStyle(
                      color: _kNavyAddr,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Usaremos estos datos si necesitamos contactarte durante la entrega.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _recipientNameController,
                    textCapitalization: TextCapitalization.none,
                    decoration: _fieldDecoration(
                      label: 'Nombre y apellido',
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: _kPrimaryAddr,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientPhoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                    ],
                    decoration: _fieldDecoration(
                      label: 'Teléfono',
                      prefixIcon: const Icon(
                        Icons.phone_outlined,
                        color: _kPrimaryAddr,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_saving || _loadingAddress)
                        ? null
                        : _saveAndReturn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimaryAddr,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
            ),
          ],
        ),
      ),
    );
  }
}
