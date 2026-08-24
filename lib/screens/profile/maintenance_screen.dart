import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/address_service.dart';
import '../../services/ticket_service.dart';
import '../../utils/service_ticket_intake.dart';
import '../../utils/service_ticket_type.dart';
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

  String _ticketType = ServiceTicketType.preventivo;
  String _urgency = 'low';
  String? _powerStatus;
  String? _previousMaintenance;
  String? _failureFrequency;
  String? _issueDuration;
  String? _visibleDamage;
  String? _previousRepair;
  String? _showsErrorCode;
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
  final _scrollController = ScrollController();
  final _submitButtonKey = GlobalKey();

  String get _serviceLabel => ServiceTicketType.label(_ticketType);

  String get _normalizedTicketType => ServiceTicketType.normalize(_ticketType);

  String get _databaseTicketType => _normalizedTicketType;

  String get _descriptionSectionTitle {
    switch (_normalizedTicketType) {
      case ServiceTicketType.correctivo:
        return 'Descripción de la falla';
      case ServiceTicketType.diagnostico:
        return 'Descripción del problema';
      default:
        return 'Descripción';
    }
  }

  String get _descriptionFieldLabel {
    switch (_normalizedTicketType) {
      case ServiceTicketType.correctivo:
        return 'Explica qué ocurrió y qué mostró el equipo';
      case ServiceTicketType.diagnostico:
        return 'Describe el problema o comportamiento observado';
      default:
        return 'Indica observaciones o detalles del servicio';
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
    _scrollController.dispose();
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
      final results = await Future.wait([
        Future(() async {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('client_id')
              .eq('id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 30));
          final resolvedClientId =
              (profile?['client_id'] as String?) ?? user.id;

          List<dynamic> equipments = [];
          try {
            final response = await Supabase.instance.client
                .from('equipment_units')
                .select('*, products(name, brand, model)')
                .eq('current_client_id', resolvedClientId)
                .timeout(const Duration(seconds: 30));
            equipments = response as List;
          } catch (_) {
            final fallback = await Supabase.instance.client
                .from('equipment_units')
                .select('*, products(name)')
                .eq('current_client_id', resolvedClientId)
                .timeout(const Duration(seconds: 30));
            equipments = fallback as List;
          }

          ClientAddress? address;
          try {
            address = await AddressService.getDefaultAddress().timeout(
              const Duration(seconds: 10),
            );
          } catch (_) {
            address = null;
          }

          return (
            resolvedClientId: resolvedClientId,
            equipments: equipments,
            address: address,
          );
        }),
        Future.delayed(const Duration(seconds: 2)),
      ]);

      final data =
          results[0]
              as ({
                ClientAddress? address,
                List<dynamic> equipments,
                String resolvedClientId,
              });

      if (!mounted) return;
      setState(() {
        _effectiveClientId = data.resolvedClientId;
        _accessNotice = widget.clientId != data.resolvedClientId
            ? 'Se validó el cliente activo para proteger el acceso a tus equipos.'
            : null;
        _equipments = data.equipments;
        _selectedAddress = data.address;
        _selectedEquipmentId = data.equipments.isEmpty
            ? 'otro'
            : data.equipments.first['id'] as String?;
        _loading = false;
      });

      if (data.equipments.isNotEmpty) {
        _fillEquipmentFrom(data.equipments.first);
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
    }
  }

  void _changeTicketType(String? value) {
    final type = ServiceTicketType.normalize(value);
    setState(() {
      _ticketType = type.isEmpty ? ServiceTicketType.preventivo : type;
      _urgency = _ticketType == ServiceTicketType.preventivo ? 'low' : 'medium';
      _powerStatus = null;
      _previousMaintenance = null;
      _failureFrequency = null;
      _issueDuration = null;
      _visibleDamage = null;
      _previousRepair = null;
      _showsErrorCode = null;
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

  Future<void> _pickPhoto() async {
    if (_attachments.length >= _maxPhotos) {
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
    double? initialButtonY;
    final buttonContext = _submitButtonKey.currentContext;
    if (buttonContext != null) {
      final box = buttonContext.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        initialButtonY = box.localToGlobal(Offset.zero).dy;
      }
    }

    final isValid = _formKey.currentState!.validate();

    if (initialButtonY != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final currentContext = _submitButtonKey.currentContext;
        if (currentContext != null) {
          final box = currentContext.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            final newButtonY = box.localToGlobal(Offset.zero).dy;
            final dyDiff = newButtonY - initialButtonY!;
            if (dyDiff.abs() > 0.5) {
              final newOffset = (_scrollController.offset + dyDiff).clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              );
              _scrollController.jumpTo(newOffset);
            }
          }
        }
      });
    }

    if (!isValid || _selectedAddress == null) {
      UiHelpers.showWarningToast(context, 'Hay campos sin completar');
      return;
    }
    if (_effectiveClientId == null) {
      UiHelpers.showErrorToast(
        context,
        'No se pudo determinar tu cuenta. Intenta de nuevo.',
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
      final equipmentBrand = _brandController.text.trim();
      final serial = _serialController.text.trim();
      final errorCode = _errorCodeController.text.trim();
      final failureDescription = _descriptionController.text.trim();
      final intakeDetails = buildServiceTicketIntakeDetails(
        type: _normalizedTicketType,
        previousMaintenance: _previousMaintenance,
        lastMaintenanceDate: _lastMaintenanceDate,
        issueDuration: _issueDuration,
        visibleDamage: _visibleDamage,
        previousRepair: _previousRepair,
        showsErrorCode: _showsErrorCode,
      );

      final ticket = await Supabase.instance.client
          .from('service_tickets')
          .insert({
            'client_id': _effectiveClientId,
            'equipment_unit_id': _selectedEquipmentId == 'otro'
                ? null
                : _selectedEquipmentId,
            'title': '$_serviceLabel: $equipmentName $equipmentModel'.trim(),
            'description': failureDescription,
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
            'equipment_name': equipmentName,
            'equipment_brand': equipmentBrand,
            'equipment_model': equipmentModel,
            'serial_number': serial.isEmpty ? null : serial,
            'institution': _institutionController.text.trim(),
            'department': _areaController.text.trim(),
            'equipment_operating': _powerStatus == null
                ? null
                : _powerStatus == 'Sí',
            'failure_description': failureDescription,
            'intake_details': intakeDetails,
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
            isVideo: false,
          );
          await TicketService.sendTicketMessage(
            ticketId,
            'Fotografía adjunta a la solicitud inicial',
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
          'Programar servicio',
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
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
      title: 'Datos del servicio',
      icon: Icons.monitor_heart_outlined,
      children: [
        _choiceField<String>(
          label: 'Tipo de servicio',
          icon: Icons.engineering_outlined,
          value: _ticketType,
          options: const [
            _ChoiceOption(
              value: ServiceTicketType.preventivo,
              label: 'Mantenimiento preventivo',
            ),
            _ChoiceOption(
              value: ServiceTicketType.correctivo,
              label: 'Mantenimiento correctivo',
            ),
            _ChoiceOption(
              value: ServiceTicketType.diagnostico,
              label: 'Diagnóstico',
            ),
          ],
          onChanged: (value) => _changeTicketType(value),
        ),
        const SizedBox(height: 12),
        _powerDropdown(),
        if (_normalizedTicketType == ServiceTicketType.preventivo)
          ..._preventiveFields(),
        if (_normalizedTicketType == ServiceTicketType.correctivo)
          ..._correctiveFields(),
        if (_normalizedTicketType == ServiceTicketType.diagnostico)
          ..._diagnosisFields(),
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
        placeholder: 'Selecciona una opción',
        requiredMessage: 'Selecciona si ha recibido mantenimiento preventivo',
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
      const SizedBox(height: 12),
      _issueDurationDropdown(label: '¿Desde cuándo ocurre?'),
      const SizedBox(height: 12),
      _visibleDamageDropdown(),
      const SizedBox(height: 12),
      _choiceField<String>(
        key: ValueKey('previous-repair-$_previousRepair'),
        label: '¿Ha sido reparado anteriormente?',
        icon: Icons.history_outlined,
        value: _previousRepair,
        placeholder: 'Selecciona una opción',
        requiredMessage: 'Indica si ha sido reparado anteriormente',
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

  List<Widget> _diagnosisFields() {
    return [
      const SizedBox(height: 12),
      _issueDurationDropdown(label: '¿Desde cuándo presenta el problema?'),
      const SizedBox(height: 12),
      _choiceField<String>(
        key: ValueKey('has-error-code-$_showsErrorCode'),
        label: '¿Muestra código de error?',
        icon: Icons.bug_report_outlined,
        value: _showsErrorCode,
        placeholder: 'Selecciona una opción',
        requiredMessage: 'Indica si muestra código de error',
        options: const [
          _ChoiceOption(value: 'Sí', label: 'Sí'),
          _ChoiceOption(value: 'No', label: 'No'),
        ],
        onChanged: (value) {
          setState(() {
            _showsErrorCode = value;
            if (value == 'No') {
              _errorCodeController.clear();
            }
          });
        },
      ),
      if (_showsErrorCode == 'Sí') ...[
        const SizedBox(height: 12),
        _errorCodeField(),
      ],
      const SizedBox(height: 12),
      _visibleDamageDropdown(),
    ];
  }

  Widget _visibleDamageDropdown() {
    return _choiceField<String>(
      key: ValueKey('visible-damage-$_visibleDamage'),
      label: '¿Tiene daños visibles?',
      icon: Icons.build_outlined,
      value: _visibleDamage,
      placeholder: 'Selecciona una opción',
      requiredMessage: 'Indica si tiene daños visibles',
      options: const [
        _ChoiceOption(value: 'Sí', label: 'Sí'),
        _ChoiceOption(value: 'No', label: 'No'),
        _ChoiceOption(value: 'No lo sé', label: 'No lo sé'),
      ],
      onChanged: (value) => setState(() => _visibleDamage = value),
    );
  }

  Widget _powerDropdown() {
    return _choiceField<String>(
      key: ValueKey('power-$_ticketType-$_powerStatus'),
      label: '¿El equipo está operando actualmente?',
      icon: Icons.power_settings_new_outlined,
      value: _powerStatus,
      placeholder: 'Selecciona una opción',
      requiredMessage: 'Indica si el equipo está operando actualmente',
      options: const [
        _ChoiceOption(value: 'Sí', label: 'Sí'),
        _ChoiceOption(value: 'No', label: 'No'),
      ],
      onChanged: (value) => setState(() => _powerStatus = value),
    );
  }

  Widget _issueDurationDropdown({required String label}) {
    return _choiceField<String>(
      key: ValueKey('issue-duration-$_powerStatus-$_issueDuration'),
      label: label,
      icon: Icons.schedule_outlined,
      value: _issueDuration,
      placeholder: 'Selecciona una opción',
      requiredMessage: 'Indica desde cuándo ocurre',
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
          'Fotografías de evidencia',
          style: TextStyle(
            color: kNavy,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hasta 5 fotografías de evidencia.',
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
      onTap: _selectingMedia ? null : _pickPhoto,
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
                  Icon(Icons.add_a_photo_outlined, color: kPrimary, size: 30),
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
          child: Image.memory(attachment.bytes, fit: BoxFit.cover),
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
            InkWell(
              onTap: _openAddressPicker,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                isEmpty: false,
                decoration:
                    _inputDecoration(
                      label: 'Ubicación del servicio',
                      icon: Icons.location_on_outlined,
                    ).copyWith(
                      errorText: field.errorText,
                      suffixIcon: const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF94A3B8),
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                    ),
                child: Text(
                  address == null
                      ? 'Seleccionar o escribir dirección'
                      : _addressSummary(address),
                  maxLines: address == null ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: address == null ? const Color(0xFF64748B) : kNavy,
                    fontSize: 14,
                    fontWeight: address == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _submitButton() {
    return Padding(
      key: _submitButtonKey,
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
    required T? value,
    required List<_ChoiceOption<T>> options,
    required ValueChanged<T> onChanged,
    bool optional = false,
    String? placeholder,
    String? requiredMessage,
  }) {
    final selected = value == null
        ? null
        : options.firstWhere(
            (o) => o.value == value,
            orElse: () => options.first,
          );

    return _AnchoredChoiceField<T>(
      key: key,
      value: value,
      options: options,
      onChanged: onChanged,
      decoration: _inputDecoration(
        label: label,
        icon: icon,
        optional: optional,
      ),
      selectedLabel: selected?.label,
      placeholder: placeholder ?? 'Selecciona',
      requiredMessage: requiredMessage,
    );
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

  InputDecoration _descriptionInputDecoration(String label) {
    const borderColor = Color(0xFFCBD5E1);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: borderColor),
    );

    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      prefixIcon: const Padding(
        padding: EdgeInsets.only(top: 17, left: 12, right: 8),
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: Icon(Icons.notes_outlined, color: kPrimary, size: 21),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      floatingLabelStyle: const TextStyle(
        color: kPrimary,
        fontSize: 12,
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
      prefixIcon: alignLabelWithHint
          ? Padding(
              padding: const EdgeInsets.only(top: 14, left: 12, right: 8),
              child: Align(
                alignment: Alignment.topLeft,
                widthFactor: 1.0,
                heightFactor: 1.0,
                child: Icon(icon, color: kPrimary, size: 21),
              ),
            )
          : Icon(icon, color: kPrimary, size: 21),
      prefixIconConstraints: alignLabelWithHint
          ? const BoxConstraints(minWidth: 42, minHeight: 42)
          : null,
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
}

class _ChoiceOption<T> {
  final T value;
  final String label;

  const _ChoiceOption({required this.value, required this.label});
}

class _AnchoredChoiceField<T> extends StatefulWidget {
  final T? value;
  final List<_ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;
  final InputDecoration decoration;
  final String? selectedLabel;
  final String placeholder;
  final String? requiredMessage;

  const _AnchoredChoiceField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.decoration,
    required this.selectedLabel,
    required this.placeholder,
    this.requiredMessage,
  });

  @override
  State<_AnchoredChoiceField<T>> createState() =>
      _AnchoredChoiceFieldState<T>();
}

class _AnchoredChoiceFieldState<T> extends State<_AnchoredChoiceField<T>> {
  // GlobalKey ensures the FormField keeps its state (incl. error text)
  // across rebuilds triggered by overlay open/close setState calls.
  final _innerKey = GlobalKey<FormFieldState<T>>();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _menuEntry;

  bool get _isOpen => _menuEntry != null;

  @override
  void didUpdateWidget(_AnchoredChoiceField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync FormField value when parent state changes — do it post-frame
    // so we are not inside a build call.
    if (oldWidget.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _innerKey.currentState?.didChange(widget.value);
      });
    }
  }

  @override
  void dispose() {
    _menuEntry?.remove();
    _menuEntry = null;
    super.dispose();
  }

  void _toggleMenu() {
    FocusScope.of(context).unfocus();
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    if (fieldBox == null || !fieldBox.hasSize) return;

    final fieldSize = fieldBox.size;
    _menuEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            child: Material(
              color: Colors.transparent,
              elevation: 10,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: fieldSize.width,
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: widget.options.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  itemBuilder: (_, index) {
                    final option = widget.options[index];
                    final isSelected = option.value == widget.value;
                    return InkWell(
                      onTap: () {
                        _closeMenu();
                        widget.onChanged(option.value);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.label,
                                style: TextStyle(
                                  color: kNavy,
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check,
                                color: kPrimary,
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
    );

    overlay.insert(_menuEntry!);
    setState(() {});
  }

  void _closeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null;
    return FormField<T>(
      key: _innerKey, // stable key → state (incl. errorText) survives rebuilds
      initialValue: widget.value,
      validator: widget.requiredMessage != null
          ? (v) => (v == null) ? widget.requiredMessage : null
          : null,
      builder: (field) {
        // NO addPostFrameCallback here — value sync happens in didUpdateWidget.
        final effectiveDecoration = widget.decoration.copyWith(
          suffixIcon: AnimatedRotation(
            turns: _isOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: Icon(
              Icons.keyboard_arrow_down,
              color: field.hasError ? const Color(0xFFDC2626) : null,
            ),
          ),
          errorText: field.errorText,
          enabledBorder: field.hasError
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDC2626)),
                )
              : null,
        );
        return CompositedTransformTarget(
          link: _layerLink,
          child: InkWell(
            key: _fieldKey,
            onTap: _toggleMenu,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: effectiveDecoration,
              child: Text(
                hasValue ? widget.selectedLabel! : widget.placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF94A3B8),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PendingAttachment {
  final String name;
  final Uint8List bytes;
  final String contentType;

  const _PendingAttachment({
    required this.name,
    required this.bytes,
    required this.contentType,
  });
}
