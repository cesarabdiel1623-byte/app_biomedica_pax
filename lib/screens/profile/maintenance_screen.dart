import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../services/address_service.dart';
import '../../services/ticket_service.dart';
import '../../utils/ui_helpers.dart';
import '../home/address_picker_screen.dart';
import 'profile_helpers.dart';

class MaintenanceScreen extends StatefulWidget {
  final String clientId;

  const MaintenanceScreen({super.key, required this.clientId});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  static const _maxPhotos = 5;
  static const _maxVideoBytes = 40 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _equipmentNameController = TextEditingController();
  final _equipmentModelController = TextEditingController();
  final _brandController = TextEditingController();
  final _serialController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _errorCodeController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _areaController = TextEditingController();
  final _institutionController = TextEditingController();
  final _imagePicker = ImagePicker();

  String _ticketType = 'preventivo';
  String _urgency = 'low';
  String _powerStatus = 'Sí';
  String _previousMaintenance = 'No';
  String _failureFrequency = 'Falla constante';
  String _issueDuration = 'Hoy';
  String _visibleDamage = 'No';
  String _previousRepair = 'No';
  String? _selectedEquipmentId;
  String? _effectiveClientId;
  String? _accessNotice;
  ClientAddress? _selectedAddress;
  DateTime? _lastMaintenanceDate;
  List<dynamic> _equipments = [];
  final List<_PendingAttachment> _attachments = [];
  bool _loading = true;
  bool _submitting = false;
  bool _selectingMedia = false;

  String get _serviceLabel {
    switch (_ticketType) {
      case 'correctivo':
        return 'Mantenimiento correctivo';
      case 'reparacion':
        return 'Reparación';
      default:
        return 'Mantenimiento preventivo';
    }
  }

  String get _databaseTicketType =>
      _ticketType == 'reparacion' ? 'correctivo' : _ticketType;

  String get _descriptionSectionTitle {
    switch (_ticketType) {
      case 'correctivo':
        return 'Descripción de la falla';
      case 'reparacion':
        return 'Descripción del problema';
      default:
        return 'Descripción';
    }
  }

  String get _descriptionFieldLabel {
    switch (_ticketType) {
      case 'correctivo':
        return 'Explica qué ocurrió y qué mostró el equipo';
      case 'reparacion':
        return 'Describe el daño o problema del equipo';
      default:
        return 'Indica el problema u observaciones del equipo';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFormData();
  }

  @override
  void dispose() {
    _equipmentNameController.dispose();
    _equipmentModelController.dispose();
    _brandController.dispose();
    _serialController.dispose();
    _descriptionController.dispose();
    _errorCodeController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _areaController.dispose();
    _institutionController.dispose();
    super.dispose();
  }

  Future<void> _loadFormData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _accessNotice = 'No hay una sesión activa.';
          _loading = false;
        });
      }
      return;
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('client_id')
          .eq('id', user.id)
          .maybeSingle();
      final resolvedClientId = (profile?['client_id'] as String?) ?? user.id;

      List<dynamic> equipments = [];
      try {
        final response = await Supabase.instance.client
            .from('equipment_units')
            .select('*, products(name, brand, model)')
            .eq('current_client_id', resolvedClientId);
        equipments = response as List;
      } catch (_) {
        final fallback = await Supabase.instance.client
            .from('equipment_units')
            .select('*, products(name)')
            .eq('current_client_id', resolvedClientId);
        equipments = fallback as List;
      }

      ClientAddress? address;
      try {
        address = await AddressService.getDefaultAddress();
      } catch (_) {
        address = null;
      }

      if (!mounted) return;
      setState(() {
        _effectiveClientId = resolvedClientId;
        _accessNotice = widget.clientId != resolvedClientId
            ? 'Se validó el cliente activo para proteger el acceso a tus equipos.'
            : null;
        _equipments = equipments;
        _selectedAddress = address;
        _selectedEquipmentId = equipments.isEmpty
            ? 'otro'
            : equipments.first['id'] as String?;
        _loading = false;
      });

      if (equipments.isNotEmpty) {
        _fillEquipmentFrom(equipments.first);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accessNotice =
            'No se pudieron cargar los equipos. Puedes registrar los datos manualmente.';
        _selectedEquipmentId = 'otro';
        _loading = false;
      });
    }
  }

  void _fillEquipmentFrom(dynamic equipment) {
    final product = equipment['products'];
    _equipmentNameController.text = product is Map
        ? (product['name'] ?? '').toString()
        : '';
    _equipmentModelController.text = product is Map
        ? (product['model'] ?? '').toString()
        : '';
    _brandController.text = product is Map
        ? (product['brand'] ?? '').toString()
        : '';
    _serialController.text = (equipment['serial_number'] ?? '').toString();
  }

  void _selectEquipment(String? equipmentId) {
    if (equipmentId == null) return;
    setState(() => _selectedEquipmentId = equipmentId);
    if (equipmentId == 'otro') {
      _equipmentNameController.clear();
      _equipmentModelController.clear();
      _brandController.clear();
      _serialController.clear();
      return;
    }

    final equipment = _equipments.firstWhere(
      (item) => item['id'] == equipmentId,
    );
    _fillEquipmentFrom(equipment);
  }

  Future<void> _openAddressPicker() async {
    FocusScope.of(context).unfocus();
    final selected = await Navigator.of(context).push<ClientAddress>(
      MaterialPageRoute(builder: (_) => const AddressPickerScreen()),
    );
    if (selected != null && mounted) {
      setState(() => _selectedAddress = selected);
      _formKey.currentState?.validate();
    }
  }

  void _changeTicketType(String? value) {
    final type = value ?? 'preventivo';
    setState(() {
      _ticketType = type;
      _urgency = type == 'preventivo' ? 'low' : 'medium';
      _powerStatus = 'Sí';
      _errorCodeController.clear();
    });
  }

  Future<void> _pickLastMaintenanceDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _lastMaintenanceDate ?? now,
      firstDate: DateTime(1990),
      lastDate: now,
      helpText: 'Fecha del último mantenimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (selected != null && mounted) {
      setState(() => _lastMaintenanceDate = selected);
    }
  }

  Future<void> _showMediaOptions() async {
    if (_selectingMedia || _submitting) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Agregar evidencia',
                  style: TextStyle(
                    color: kNavy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.add_a_photo_outlined,
                  color: kPrimary,
                ),
                title: const Text('Agregar fotografía'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickPhoto();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.video_library_outlined,
                  color: kPrimary,
                ),
                title: const Text('Agregar video'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickVideo();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final photoCount = _attachments.where((item) => !item.isVideo).length;
    if (photoCount >= _maxPhotos) {
      await _showMediaWarning(
        icon: Icons.photo_library_outlined,
        title: 'Límite de fotografías',
        message: 'Puedes adjuntar un máximo de 5 fotografías.',
      );
      return;
    }

    setState(() => _selectingMedia = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      UiHelpers.validateImageUpload(bytes, picked.name);
      if (!mounted) return;
      setState(
        () => _attachments.add(
          _PendingAttachment(
            name: picked.name,
            bytes: bytes,
            contentType: _imageContentType(picked.name, picked.mimeType),
            isVideo: false,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        UiHelpers.showErrorToast(
          context,
          error.toString().contains('tamaño máximo')
              ? 'La fotografía es demasiado pesada.'
              : 'No se pudo agregar la fotografía.',
        );
      }
    } finally {
      if (mounted) setState(() => _selectingMedia = false);
    }
  }

  Future<void> _pickVideo() async {
    if (_attachments.any((item) => item.isVideo)) {
      await _showMediaWarning(
        icon: Icons.video_library_outlined,
        title: 'Solo un video',
        message: 'Quita el video actual antes de seleccionar otro.',
      );
      return;
    }

    setState(() => _selectingMedia = true);
    VideoPlayerController? controller;
    try {
      final picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 1),
      );
      if (picked == null) return;

      final size = await picked.length();
      if (size > _maxVideoBytes) {
        await _showMediaWarning(
          icon: Icons.video_file_outlined,
          title: 'El video es demasiado pesado',
          message: 'Selecciona un video que pese menos de 40 MB.',
        );
        return;
      }

      controller = VideoPlayerController.file(File(picked.path));
      await controller.initialize();
      if (controller.value.duration > const Duration(minutes: 1)) {
        await _showMediaWarning(
          icon: Icons.timer_off_outlined,
          title: 'El video dura demasiado',
          message: 'Selecciona un video de máximo 1 minuto.',
        );
        return;
      }

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(
        () => _attachments.add(
          _PendingAttachment(
            name: picked.name,
            bytes: bytes,
            contentType: _videoContentType(picked.name, picked.mimeType),
            isVideo: true,
            duration: controller!.value.duration,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        UiHelpers.showErrorToast(
          context,
          'No se pudo agregar el video. Usa un archivo MP4 de máximo 1 minuto.',
        );
      }
    } finally {
      await controller?.dispose();
      if (mounted) setState(() => _selectingMedia = false);
    }
  }

  Future<void> _showMediaWarning({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kPrimary, size: 38),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kNavy,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Entendido',
              style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRequest() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_effectiveClientId == null || _selectedAddress == null) {
      UiHelpers.showErrorToast(
        context,
        'Selecciona una dirección antes de enviar la solicitud.',
      );
      return;
    }

    setState(() => _submitting = true);
    var failedAttachments = 0;

    try {
      final selectedAddress = _selectedAddress!;
      final details = selectedAddress.details;
      final equipmentName = _equipmentNameController.text.trim();
      final equipmentModel = _equipmentModelController.text.trim();
      final serial = _serialController.text.trim();
      final photoCount = _attachments.where((item) => !item.isVideo).length;
      final videoCount = _attachments.where((item) => item.isVideo).length;

      final description = StringBuffer()
        ..writeln('=== INFORMACIÓN DEL EQUIPO ===')
        ..writeln('• Nombre: $equipmentName')
        ..writeln('• Modelo: $equipmentModel')
        ..writeln('• Marca: ${_brandController.text.trim()}')
        ..writeln(
          '• Número de serie: ${serial.isEmpty ? "No proporcionado" : serial}',
        )
        ..writeln('\n=== SOLICITUD ===')
        ..writeln('• Tipo: $_serviceLabel')
        ..writeln('• ¿El equipo enciende?: $_powerStatus');

      if (_ticketType == 'preventivo') {
        description.writeln(
          '• Mantenimiento preventivo anterior: $_previousMaintenance',
        );
        if (_previousMaintenance == 'Sí') {
          description.writeln(
            '• Fecha del último mantenimiento: ${_formatDate(_lastMaintenanceDate)}',
          );
        }
      } else if (_ticketType == 'correctivo') {
        if (_powerStatus == 'Sí') {
          description.writeln('• Frecuencia de la falla: $_failureFrequency');
        }
        description.writeln(
          '• ${_powerStatus == "No" ? "Dejó de encender" : "La falla comenzó"}: $_issueDuration',
        );
      } else if (_ticketType == 'reparacion') {
        description
          ..writeln('• Daños visibles: $_visibleDamage')
          ..writeln('• Reparado anteriormente: $_previousRepair');
      }

      final errorCode = _errorCodeController.text.trim();
      if (errorCode.isNotEmpty) {
        description.writeln('• Código de error: $errorCode');
      }

      description
        ..writeln('\n=== $_descriptionSectionTitle ===')
        ..writeln(_descriptionController.text.trim())
        ..writeln('\n=== CONTACTO Y LOGÍSTICA ===')
        ..writeln('• Responsable: ${_contactNameController.text.trim()}')
        ..writeln('• Teléfono: ${_contactPhoneController.text.trim()}')
        ..writeln('• Área o departamento: ${_areaController.text.trim()}')
        ..writeln('• Institución: ${_institutionController.text.trim()}')
        ..writeln('• Dirección: ${_addressSummary(selectedAddress)}')
        ..writeln(
          '• Evidencia: $photoCount fotografía(s) y $videoCount video(s)',
        );

      final ticket = await Supabase.instance.client
          .from('service_tickets')
          .insert({
            'client_id': _effectiveClientId,
            'equipment_unit_id': _selectedEquipmentId == 'otro'
                ? null
                : _selectedEquipmentId,
            'title': '$_serviceLabel: $equipmentName $equipmentModel'.trim(),
            'description': description.toString(),
            'type': _databaseTicketType,
            'priority': _urgency,
            'status': 'open',
            'requested_by': Supabase.instance.client.auth.currentUser?.id,
            'contact_name': _contactNameController.text.trim(),
            'contact_phone': _contactPhoneController.text.trim(),
            'contact_email': Supabase.instance.client.auth.currentUser?.email,
            'service_location': _addressSummary(selectedAddress),
            'service_address': details.streetAddress.isNotEmpty
                ? details.streetAddress
                : selectedAddress.address,
            'service_city': details.municipality.isNotEmpty
                ? details.municipality
                : selectedAddress.city,
            'service_state': selectedAddress.state,
            'service_region': details.neighborhood.isEmpty
                ? null
                : details.neighborhood,
            'error_code': errorCode.isEmpty ? null : errorCode,
          })
          .select('id')
          .single();

      final ticketId = ticket['id'] as String;
      for (final attachment in _attachments) {
        try {
          final reference = await TicketService.uploadTicketAttachment(
            ticketId: ticketId,
            fileName: attachment.name,
            bytes: attachment.bytes,
            contentType: attachment.contentType,
            isVideo: attachment.isVideo,
          );
          await TicketService.sendTicketMessage(
            ticketId,
            attachment.isVideo
                ? 'Video adjunto a la solicitud inicial'
                : 'Fotografía adjunta a la solicitud inicial',
            attachmentUrl: reference,
          );
        } catch (_) {
          failedAttachments++;
        }
      }

      if (!mounted) return;
      if (failedAttachments > 0) {
        UiHelpers.showWarningToast(
          context,
          'La solicitud se guardó, pero $failedAttachments archivo(s) no pudieron subirse.',
        );
      } else {
        UiHelpers.showFloatingSuccessToast(
          context,
          'Solicitud enviada correctamente.',
        );
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      UiHelpers.showErrorToast(
        context,
        UiHelpers.isNetworkError(error)
            ? 'No hay conexión. Revisa tu internet e intenta nuevamente.'
            : 'No se pudo enviar la solicitud. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Programar mantenimiento',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ColoredBox(
        color: Colors.white,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.zero,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (_accessNotice != null) _noticeBanner(_accessNotice!),
                    _introHeader(),
                    _equipmentSection(),
                    _diagnosticSection(),
                    _descriptionSection(),
                    _contactSection(),
                    _submitButton(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _introHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.engineering_outlined, color: kPrimary, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solicitud de servicio biomédico',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: kNavy,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Registra el equipo, su estado y los datos de contacto para solicitar la atención.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeBanner(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12.5,
          color: Color(0xFF92400E),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _equipmentSection() {
    return _formSection(
      title: 'Información del equipo',
      icon: Icons.medical_services_outlined,
      children: [
        if (_equipments.isNotEmpty) ...[
          _choiceField<String>(
            label: 'Equipo registrado',
            icon: Icons.devices_other_outlined,
            optional: true,
            value: _selectedEquipmentId ?? 'otro',
            options: [
              ..._equipments.map<_ChoiceOption<String>>((equipment) {
                final product = equipment['products'];
                final name = product is Map
                    ? (product['name'] ?? 'Equipo').toString()
                    : 'Equipo';
                final serial = (equipment['serial_number'] ?? '').toString();
                return _ChoiceOption(
                  value: equipment['id'] as String,
                  label: serial.trim().isEmpty ? name : '$name · $serial',
                );
              }),
              const _ChoiceOption(
                value: 'otro',
                label: 'Registrar datos manualmente',
              ),
            ],
            onChanged: _selectEquipment,
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _equipmentNameController,
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration(
            label: 'Nombre del equipo',
            icon: Icons.settings_outlined,
          ),
          validator: _requiredValidator('Ingresa el nombre del equipo'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _equipmentModelController,
          textCapitalization: TextCapitalization.characters,
          decoration: _inputDecoration(
            label: 'Modelo',
            icon: Icons.view_in_ar_outlined,
          ),
          validator: _requiredValidator('Ingresa el modelo'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _brandController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Marca',
            icon: Icons.sell_outlined,
          ),
          validator: _requiredValidator('Ingresa la marca'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _serialController,
          decoration: _inputDecoration(
            label: 'Número de serie',
            icon: Icons.tag_outlined,
            optional: true,
          ),
        ),
      ],
    );
  }

  Widget _diagnosticSection() {
    return _formSection(
      title: 'Estado y diagnóstico',
      icon: Icons.monitor_heart_outlined,
      children: [
        _choiceField<String>(
          label: 'Tipo de servicio',
          icon: Icons.engineering_outlined,
          value: _ticketType,
          options: const [
            _ChoiceOption(
              value: 'preventivo',
              label: 'Mantenimiento preventivo',
            ),
            _ChoiceOption(
              value: 'correctivo',
              label: 'Mantenimiento correctivo',
            ),
            _ChoiceOption(value: 'reparacion', label: 'Reparación'),
          ],
          onChanged: (value) => _changeTicketType(value),
        ),
        const SizedBox(height: 12),
        _powerDropdown(),
        if (_ticketType == 'preventivo') ..._preventiveFields(),
        if (_ticketType == 'correctivo') ..._correctiveFields(),
        if (_ticketType == 'reparacion') ..._repairFields(),
      ],
    );
  }

  List<Widget> _preventiveFields() {
    return [
      const SizedBox(height: 12),
      _choiceField<String>(
        key: const ValueKey('previous-maintenance'),
        label: '¿Ha recibido mantenimiento preventivo?',
        icon: Icons.event_repeat_outlined,
        value: _previousMaintenance,
        options: const [
          _ChoiceOption(value: 'Sí', label: 'Sí'),
          _ChoiceOption(value: 'No', label: 'No'),
        ],
        onChanged: (value) {
          setState(() {
            _previousMaintenance = value;
            if (_previousMaintenance == 'No') {
              _lastMaintenanceDate = null;
            }
          });
        },
      ),
      if (_previousMaintenance == 'Sí') ...[
        const SizedBox(height: 12),
        _dateSelector(
          label: 'Fecha del último mantenimiento',
          value: _lastMaintenanceDate,
          onTap: _pickLastMaintenanceDate,
        ),
      ],
    ];
  }

  List<Widget> _correctiveFields() {
    return [
      if (_powerStatus == 'Sí') ...[
        const SizedBox(height: 12),
        _choiceField<String>(
          key: const ValueKey('failure-frequency'),
          label: 'Frecuencia de la falla',
          icon: Icons.repeat_outlined,
          value: _failureFrequency,
          options: const [
            _ChoiceOption(value: 'Falla constante', label: 'Constante'),
            _ChoiceOption(
              value: 'Falla intermitente / aleatoria',
              label: 'Intermitente o aleatoria',
            ),
            _ChoiceOption(value: 'Falla ocasional', label: 'Ocasional'),
          ],
          onChanged: (value) => setState(() => _failureFrequency = value),
        ),
      ],
      const SizedBox(height: 12),
      _issueDurationDropdown(
        label: _powerStatus == 'No'
            ? '¿Desde cuándo dejó de encender?'
            : '¿Desde cuándo ocurre?',
      ),
      const SizedBox(height: 12),
      _errorCodeField(),
    ];
  }

  List<Widget> _repairFields() {
    return [
      const SizedBox(height: 12),
      _choiceField<String>(
        key: const ValueKey('visible-damage'),
        label: '¿Tiene daños visibles?',
        icon: Icons.build_outlined,
        value: _visibleDamage,
        options: const [
          _ChoiceOption(value: 'Sí', label: 'Sí'),
          _ChoiceOption(value: 'No', label: 'No'),
          _ChoiceOption(value: 'No lo sé', label: 'No lo sé'),
        ],
        onChanged: (value) => setState(() => _visibleDamage = value),
      ),
      const SizedBox(height: 12),
      _choiceField<String>(
        key: const ValueKey('previous-repair'),
        label: '¿Ha sido reparado anteriormente?',
        icon: Icons.history_outlined,
        value: _previousRepair,
        options: const [
          _ChoiceOption(value: 'Sí', label: 'Sí'),
          _ChoiceOption(value: 'No', label: 'No'),
          _ChoiceOption(value: 'No lo sé', label: 'No lo sé'),
        ],
        onChanged: (value) => setState(() => _previousRepair = value),
      ),
      const SizedBox(height: 12),
      _errorCodeField(),
    ];
  }

  Widget _powerDropdown() {
    return _choiceField<String>(
      key: ValueKey('power-$_ticketType-$_powerStatus'),
      label: '¿El equipo enciende?',
      icon: Icons.power_settings_new_outlined,
      value: _powerStatus,
      options: const [
        _ChoiceOption(value: 'Sí', label: 'Sí'),
        _ChoiceOption(value: 'No', label: 'No'),
      ],
      onChanged: (value) => setState(() => _powerStatus = value),
    );
  }

  Widget _issueDurationDropdown({required String label}) {
    return _choiceField<String>(
      key: ValueKey('issue-duration-$_powerStatus'),
      label: label,
      icon: Icons.schedule_outlined,
      value: _issueDuration,
      options: const [
        _ChoiceOption(value: 'Hoy', label: 'Hoy'),
        _ChoiceOption(value: 'Hace 2 a 7 días', label: 'Hace 2 a 7 días'),
        _ChoiceOption(
          value: 'Hace más de una semana',
          label: 'Hace más de una semana',
        ),
        _ChoiceOption(value: 'No lo sé', label: 'No lo sé'),
      ],
      onChanged: (value) => setState(() => _issueDuration = value),
    );
  }

  Widget _errorCodeField() {
    return TextFormField(
      controller: _errorCodeController,
      textCapitalization: TextCapitalization.characters,
      decoration: _inputDecoration(
        label: 'Código de error',
        icon: Icons.bug_report_outlined,
        optional: true,
      ),
    );
  }

  Widget _descriptionSection() {
    return _formSection(
      title: _descriptionSectionTitle,
      icon: Icons.description_outlined,
      children: [
        TextFormField(
          controller: _descriptionController,
          minLines: 4,
          maxLines: 7,
          maxLength: 1200,
          textCapitalization: TextCapitalization.sentences,
          decoration: _descriptionInputDecoration(_descriptionFieldLabel),
          validator: _requiredValidator('Describe la solicitud'),
        ),
        const SizedBox(height: 12),
        _attachmentPicker(),
      ],
    );
  }

  Widget _attachmentPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fotografías y video',
          style: TextStyle(
            color: kNavy,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hasta 5 fotografías y 1 video de máximo 1 minuto.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _attachments.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _addAttachmentTile();
              }
              return _attachmentTile(_attachments[index - 1], index - 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _addAttachmentTile() {
    return InkWell(
      onTap: _selectingMedia ? null : _showMediaOptions,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 104,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kPrimary, width: 1.3),
        ),
        child: _selectingMedia
            ? const Center(
                child: CircularProgressIndicator(
                  color: kPrimary,
                  strokeWidth: 2,
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_to_photos_outlined, color: kPrimary, size: 30),
                  SizedBox(height: 6),
                  Text(
                    'Agregar',
                    style: TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _attachmentTile(_PendingAttachment attachment, int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: attachment.isVideo
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.play_circle_outline,
                      color: kPrimary,
                      size: 38,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(attachment.duration),
                      style: const TextStyle(
                        color: kNavy,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Image.memory(attachment.bytes, fit: BoxFit.cover),
        ),
        Positioned(
          top: -5,
          right: -5,
          child: IconButton.filled(
            onPressed: _submitting
                ? null
                : () => setState(() => _attachments.removeAt(index)),
            icon: const Icon(Icons.close, size: 15),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              foregroundColor: Colors.white,
              minimumSize: const Size(28, 28),
              maximumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _contactSection() {
    return _formSection(
      title: 'Contacto y logística',
      icon: Icons.contact_phone_outlined,
      children: [
        TextFormField(
          controller: _contactNameController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Nombre del responsable',
            icon: Icons.person_outline,
          ),
          validator: _requiredValidator('Ingresa el nombre del responsable'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _contactPhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(13),
          ],
          decoration: _inputDecoration(
            label: 'Teléfono de contacto',
            icon: Icons.phone_outlined,
          ).copyWith(counterText: ''),
          validator: (value) {
            final phone = value?.trim() ?? '';
            if (phone.isEmpty) return 'Ingresa el teléfono';
            if (phone.length < 10) return 'Ingresa al menos 10 dígitos';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _areaController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Área o departamento',
            icon: Icons.meeting_room_outlined,
          ),
          validator: _requiredValidator('Ingresa el área o departamento'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _institutionController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Hospital, clínica o institución',
            icon: Icons.local_hospital_outlined,
          ),
          validator: _requiredValidator('Ingresa el nombre de la institución'),
        ),
        const SizedBox(height: 12),
        _addressSelector(),
      ],
    );
  }

  Widget _addressSelector() {
    return FormField<ClientAddress>(
      key: ValueKey(_selectedAddress?.id ?? 'no-address'),
      initialValue: _selectedAddress,
      validator: (value) =>
          value == null ? 'Selecciona o registra una dirección' : null,
      builder: (field) {
        final address = _selectedAddress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (address != null)
              InkWell(
                onTap: _openAddressPicker,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: field.hasError ? kRed : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: kPrimary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ubicación del servicio',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _addressSummary(address),
                              style: const TextStyle(
                                color: kNavy,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _openAddressPicker,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: field.hasError ? kRed : kPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text(
                  'Seleccionar o escribir dirección',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (field.hasError) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(color: kRed, fontSize: 12),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _submitButton() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _submitting || _selectingMedia ? null : _submitRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: kPrimary.withValues(alpha: 0.55),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          child: _submitting
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Enviando solicitud...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : const Text(
                  'Enviar solicitud',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }

  Widget _choiceField<T>({
    Key? key,
    required String label,
    required IconData icon,
    required T value,
    required List<_ChoiceOption<T>> options,
    required ValueChanged<T> onChanged,
    bool optional = false,
  }) {
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );

    return InkWell(
      key: key,
      onTap: () => _showChoiceSheet<T>(
        title: label,
        value: value,
        options: options,
        onChanged: onChanged,
      ),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: _inputDecoration(
          label: label,
          icon: icon,
          optional: optional,
        ).copyWith(suffixIcon: const Icon(Icons.keyboard_arrow_down)),
        child: Text(
          selected.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Future<void> _showChoiceSheet<T>({
    required String title,
    required T value,
    required List<_ChoiceOption<T>> options,
    required ValueChanged<T> onChanged,
  }) async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    color: kNavy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    itemBuilder: (_, index) {
                      final option = options[index];
                      final isSelected = option.value == value;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          option.label,
                          style: const TextStyle(
                            color: kNavy,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: kPrimary)
                            : null,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(option.value),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      onChanged(selected);
    }
  }

  Widget _dateSelector({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return FormField<DateTime>(
      key: ValueKey(value?.millisecondsSinceEpoch ?? 'no-date'),
      initialValue: value,
      validator: (_) => _previousMaintenance == 'Sí' && value == null
          ? 'Selecciona la fecha del último mantenimiento'
          : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration(
                label: label,
                icon: Icons.calendar_today_outlined,
              ).copyWith(errorText: field.errorText),
              child: Text(
                value == null ? 'Seleccionar fecha' : _formatDate(value),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                  color: value == null
                      ? const Color(0xFF64748B)
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 21, color: kPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _descriptionInputDecoration(String hint) {
    final base = _inputDecoration(
      label: '',
      icon: Icons.notes_outlined,
      alignLabelWithHint: true,
    );

    return base.copyWith(
      labelText: null,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      prefixIcon: const Padding(
        padding: EdgeInsets.only(top: 18),
        child: Align(
          alignment: Alignment.topCenter,
          widthFactor: 1,
          heightFactor: 1,
          child: Icon(Icons.notes_outlined, color: kPrimary, size: 21),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      contentPadding: const EdgeInsets.fromLTRB(4, 18, 14, 14),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    bool optional = false,
    bool alignLabelWithHint = false,
  }) {
    const borderColor = Color(0xFFCBD5E1);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: borderColor),
    );

    return InputDecoration(
      labelText: optional ? '$label (opcional)' : label,
      alignLabelWithHint: alignLabelWithHint,
      prefixIcon: Icon(icon, color: kPrimary, size: 21),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      floatingLabelStyle: const TextStyle(
        color: kPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kRed, width: 1.5),
      ),
      errorMaxLines: 2,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      isDense: true,
    );
  }

  FormFieldValidator<String> _requiredValidator(String message) {
    return (value) => value == null || value.trim().isEmpty ? message : null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'No indicada';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String _addressSummary(ClientAddress address) {
    final details = address.details;
    final parts = <String>[
      if (details.streetAddress.trim().isNotEmpty)
        details.streetAddress.trim()
      else
        address.address.split('\n').first.trim(),
      if (details.interior.trim().isNotEmpty)
        'Interior ${details.interior.trim()}',
      if (details.neighborhood.trim().isNotEmpty) details.neighborhood.trim(),
      if (details.locality.trim().isNotEmpty) details.locality.trim(),
      if (details.municipality.trim().isNotEmpty)
        details.municipality.trim()
      else if ((address.city ?? '').trim().isNotEmpty)
        address.city!.trim(),
      if ((address.state ?? '').trim().isNotEmpty) address.state!.trim(),
      if ((address.postalCode ?? '').trim().isNotEmpty)
        'CP ${address.postalCode!.trim()}',
    ];
    return parts.toSet().join(', ');
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'Video';
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _imageContentType(String fileName, String? mimeType) {
    if (mimeType?.startsWith('image/') == true) return mimeType!;
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _videoContentType(String fileName, String? mimeType) {
    if (mimeType?.startsWith('video/') == true) return mimeType!;
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.m4v')) return 'video/x-m4v';
    return 'video/mp4';
  }
}

class _ChoiceOption<T> {
  final T value;
  final String label;

  const _ChoiceOption({required this.value, required this.label});
}

class _PendingAttachment {
  final String name;
  final Uint8List bytes;
  final String contentType;
  final bool isVideo;
  final Duration? duration;

  const _PendingAttachment({
    required this.name,
    required this.bytes,
    required this.contentType,
    required this.isVideo,
    this.duration,
  });
}
