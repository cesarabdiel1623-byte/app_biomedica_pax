import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_helpers.dart';

class MaintenanceScreen extends StatefulWidget {
  final String clientId;
  const MaintenanceScreen({super.key, required this.clientId});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _customEquipmentController = TextEditingController();
  final _customSerialController = TextEditingController();
  
  // Controllers
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _areaController = TextEditingController();
  final _errorCodeController = TextEditingController();
  final _brandController = TextEditingController();
  final _locationController = TextEditingController();

  String _ticketType = 'preventivo';
  String _priority = 'medium';
  String? _selectedEquipmentId;
  List<dynamic> _equipments = [];
  bool _loading = true;
  bool _submitting = false;

  // Diagnosis States
  String _powerStatus = 'Sí';
  String _failureFrequency = 'Falla constante';
  String _accessoriesStatus = 'No';
  String? _effectiveClientId;
  String? _accessError;

  @override
  void initState() {
    super.initState();
    _loadEquipments();
  }

  @override
  void dispose() {
    _descController.dispose();
    _customEquipmentController.dispose();
    _customSerialController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _areaController.dispose();
    _errorCodeController.dispose();
    _brandController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadEquipments() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _accessError = 'No hay una sesión activa.';
            _loading = false;
          });
        }
        return;
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('client_id')
          .eq('id', userId)
          .maybeSingle();
      final resolvedClientId = (profile?['client_id'] as String?) ?? userId;

      final response = await Supabase.instance.client
          .from('equipment_units')
          .select('*, products(name)')
          .eq('current_client_id', resolvedClientId);
      if (mounted) {
        setState(() {
          _effectiveClientId = resolvedClientId;
          _accessError = widget.clientId != resolvedClientId
              ? 'Se actualizó el cliente activo para proteger el acceso a tus equipos.'
              : null;
          _equipments = response as List;
          _loading = false;
          if (_equipments.isNotEmpty) {
            _selectedEquipmentId = _equipments.first['id'] as String?;
          } else {
            _selectedEquipmentId = 'otro';
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_effectiveClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo validar el cliente activo.'),
          backgroundColor: kRed,
        ),
      );
      return;
    }
    setState(() => _submitting = true);

    try {
      String eqName = 'Equipo general';
      String? eqUnitId = _selectedEquipmentId;
      String eqSerial = '';

      if (_selectedEquipmentId == 'otro' || _equipments.isEmpty) {
        eqName = _customEquipmentController.text.trim();
        eqSerial = _customSerialController.text.trim();
        eqUnitId = null;
      } else if (_selectedEquipmentId != null) {
        final eq = _equipments.firstWhere((e) => e['id'] == _selectedEquipmentId);
        eqName = eq['products']?['name'] ?? 'Equipo';
        eqSerial = eq['serial_number'] ?? '';
      }

      final descriptionText = StringBuffer();
      descriptionText.writeln('=== INFORMACIÓN TÉCNICA Y DIAGNÓSTICO ===');
      descriptionText.writeln('• Equipo/Modelo: $eqName');
      if (_selectedEquipmentId == 'otro' || _equipments.isEmpty) {
        descriptionText.writeln('• Marca: ${_brandController.text.trim()}');
      }
      descriptionText.writeln('• Número de Serie: ${eqSerial.isNotEmpty ? eqSerial : "No proporcionado"}');
      descriptionText.writeln('• Ubicación: ${_locationController.text.trim()}');
      descriptionText.writeln('• ¿Enciende?: $_powerStatus');
      descriptionText.writeln('• Frecuencia de Falla: $_failureFrequency');
      descriptionText.writeln('• Accesorios Conectados: $_accessoriesStatus');
      if (_errorCodeController.text.trim().isNotEmpty) {
        descriptionText.writeln('• Código de Error: ${_errorCodeController.text.trim()}');
      }
      descriptionText.writeln('\n=== DATOS DE CONTACTO ===');
      descriptionText.writeln('• Responsable: ${_contactNameController.text.trim()}');
      descriptionText.writeln('• Teléfono: ${_contactPhoneController.text.trim()}');
      descriptionText.writeln('• Área/Depto: ${_areaController.text.trim()}');
      descriptionText.writeln('• Fecha/Hora: Coordinar con Administración');
      descriptionText.writeln('\n=== DESCRIPCIÓN DEL REQUERIMIENTO ===');
      descriptionText.writeln(_descController.text.trim());

      await Supabase.instance.client.from('service_tickets').insert({
        'client_id': _effectiveClientId,
        'equipment_unit_id': eqUnitId,
        'title': 'Solicitud Mantenimiento: $eqName',
        'description': descriptionText.toString(),
        'type': _ticketType,
        'priority': _priority,
        'status': 'open',
        'requested_by': Supabase.instance.client.auth.currentUser?.id,
        'contact_name': _contactNameController.text.trim(),
        'contact_phone': _contactPhoneController.text.trim(),
        'service_location': _locationController.text.trim(),
        'error_code': _errorCodeController.text.trim().isNotEmpty ? _errorCodeController.text.trim() : null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud de mantenimiento enviada con éxito'), backgroundColor: kPrimary),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar solicitud: $e'), backgroundColor: kRed),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDropdown = _equipments.isNotEmpty;
    final isCustom = _selectedEquipmentId == 'otro' || !showDropdown;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Programar Mantenimiento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_accessError != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        _accessError!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Solicitud de Servicio Biomédico',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Completa los datos técnicos del equipo y los detalles de contacto para agendar la visita de un ingeniero biomédico calificado.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _sectionHeader('INFORMACIÓN DEL EQUIPO'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDropdown) ...[
                            DropdownButtonFormField<String>(
                              initialValue: _selectedEquipmentId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Selecciona tu Equipo *',
                                prefixIcon: const Icon(Icons.medical_services_outlined, color: kPrimary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              items: [
                                ..._equipments.map<DropdownMenuItem<String>>((e) {
                                  final name = e['products']?['name'] ?? 'Equipo';
                                  final sn = e['serial_number'] ?? '';
                                  return DropdownMenuItem<String>(
                                    value: e['id'] as String,
                                    child: Text('$name ($sn)', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
                                  );
                                }),
                                const DropdownMenuItem<String>(
                                  value: 'otro',
                                  child: Text('Otro (Ingresar manualmente)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kPrimary)),
                                ),
                              ],
                              onChanged: (v) => setState(() => _selectedEquipmentId = v),
                              validator: (v) => v == null ? 'Por favor selecciona un equipo' : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (isCustom) ...[
                            TextFormField(
                              controller: _customEquipmentController,
                              decoration: InputDecoration(
                                labelText: 'Nombre / Modelo del Equipo *',
                                prefixIcon: const Icon(Icons.settings_outlined, color: kPrimary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el nombre del equipo' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _brandController,
                              decoration: InputDecoration(
                                labelText: 'Marca del Equipo *',
                                prefixIcon: const Icon(Icons.copyright_outlined, color: kPrimary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa la marca del equipo' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _customSerialController,
                              decoration: InputDecoration(
                                labelText: 'Número de Serie (opcional)',
                                prefixIcon: const Icon(Icons.tag_outlined, color: kPrimary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _locationController,
                            decoration: InputDecoration(
                              labelText: 'Ubicación Física del Equipo *',
                              hintText: 'Ej. Quirófano 1, Consultorio 2, Urgencias',
                              prefixIcon: const Icon(Icons.pin_drop_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa la ubicación del equipo' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _sectionHeader('ESTADO Y DIAGNÓSTICO DEL EQUIPO'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _ticketType,
                            decoration: InputDecoration(
                              labelText: 'Tipo de Servicio *',
                              prefixIcon: const Icon(Icons.engineering_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'preventivo', child: Text('Mantenimiento Preventivo')),
                              DropdownMenuItem(value: 'correctivo', child: Text('Mantenimiento Correctivo')),
                              DropdownMenuItem(value: 'otro', child: Text('Reparación y Soporte Técnico')),
                            ],
                            onChanged: (v) => setState(() => _ticketType = v ?? 'preventivo'),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _priority,
                            decoration: InputDecoration(
                              labelText: 'Prioridad del Reporte *',
                              prefixIcon: const Icon(Icons.warning_amber_rounded, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'low', child: Text('Baja - Rutinario')),
                              DropdownMenuItem(value: 'medium', child: Text('Media - Normal')),
                              DropdownMenuItem(value: 'high', child: Text('Alta - Urgente')),
                              DropdownMenuItem(value: 'urgent', child: Text('Crítica - Fuera de servicio')),
                            ],
                            onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _powerStatus,
                            decoration: InputDecoration(
                              labelText: '¿El equipo enciende? *',
                              prefixIcon: const Icon(Icons.power_settings_new_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Sí', child: Text('Sí')),
                              DropdownMenuItem(value: 'No', child: Text('No')),
                              DropdownMenuItem(value: 'Intermitente', child: Text('Intermitente')),
                            ],
                            onChanged: (v) => setState(() => _powerStatus = v ?? 'Sí'),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _failureFrequency,
                            decoration: InputDecoration(
                              labelText: 'Frecuencia de la Falla *',
                              prefixIcon: const Icon(Icons.repeat_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Falla constante', child: Text('Falla constante')),
                              DropdownMenuItem(value: 'Falla intermitente / aleatoria', child: Text('Falla intermitente / aleatoria')),
                              DropdownMenuItem(value: 'Falla ocasional', child: Text('Falla ocasional')),
                            ],
                            onChanged: (v) => setState(() => _failureFrequency = v ?? 'Falla constante'),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _accessoriesStatus,
                            decoration: InputDecoration(
                              labelText: '¿Tiene consumibles/accesorios conectados? *',
                              prefixIcon: const Icon(Icons.cable_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'No', child: Text('No')),
                              DropdownMenuItem(value: 'Sí (especificar en descripción)', child: Text('Sí (especificar en descripción)')),
                            ],
                            onChanged: (v) => setState(() => _accessoriesStatus = v ?? 'No'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _errorCodeController,
                            decoration: InputDecoration(
                              labelText: 'Código de Error (opcional)',
                              hintText: 'Ej. Err 03, E-102',
                              prefixIcon: const Icon(Icons.bug_report_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _sectionHeader('CONTACTO Y LOGÍSTICA'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _contactNameController,
                            decoration: InputDecoration(
                              labelText: 'Nombre del Responsable *',
                              prefixIcon: const Icon(Icons.person_outline, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el nombre del responsable' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _contactPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Teléfono de Contacto *',
                              prefixIcon: const Icon(Icons.phone_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Ingresa el teléfono';
                              if (v.trim().length < 10) return 'El teléfono debe tener al menos 10 dígitos';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _areaController,
                            decoration: InputDecoration(
                              labelText: 'Área / Departamento *',
                              hintText: 'Ej. Rayos X, Quirófano, Urgencias',
                              prefixIcon: const Icon(Icons.meeting_room_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el área del equipo' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _sectionHeader('DESCRIPCIÓN DE LA FALLA'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextFormField(
                        controller: _descController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Detalla el síntoma o requerimiento *',
                          hintText: 'Describe detalladamente el comportamiento del equipo y los accesorios conectados.',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Describe los detalles de la falla' : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      icon: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send),
                      label: Text(
                        _submitting ? 'Enviando Reporte...' : 'Enviar Reporte de Servicio',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8),
      ),
    );
  }
}
