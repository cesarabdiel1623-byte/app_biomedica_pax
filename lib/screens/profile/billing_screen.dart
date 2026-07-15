import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_helpers.dart';

class BillingScreen extends StatefulWidget {
  final String clientId;
  const BillingScreen({super.key, required this.clientId});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _tradeNameController = TextEditingController();
  final _rfcController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _postalCodeController = TextEditingController();

  String? _selectedTaxRegime;
  String? _selectedCfdiUse;

  bool _loading = true;
  bool _saving = false;

  static const Map<String, String> _taxRegimes = {
    '601': '601 - General de Ley Personas Morales',
    '603': '603 - Personas Morales con Fines no Lucrativos',
    '605': '605 - Sueldos y Salarios e Ingresos Asimilados a Salarios',
    '606': '606 - Arrendamiento',
    '612': '612 - Personas Físicas con Actividades Empresariales y Profesionales',
    '621': '621 - Incorporación Fiscal',
    '626': '626 - Régimen Simplificado de Confianza (RESICO)',
  };

  static const Map<String, String> _cfdiUses = {
    'G01': 'G01 - Adquisición de mercancías',
    'G03': 'G03 - Gastos en general',
    'I01': 'I01 - Construcciones',
    'I02': 'I02 - Mobiliario y equipo de oficina por inversiones',
    'I03': 'I03 - Equipo de transporte',
    'I04': 'I04 - Equipo de cómputo y accesorios',
    'I08': 'I08 - Otra maquinaria y equipo',
    'D01': 'D01 - Honorarios médicos, dentales y gastos hospitalarios',
    'D02': 'D02 - Gastos médicos por incapacidad o discapacidad',
    'S01': 'S01 - Sin efectos fiscales',
    'CP01': 'CP01 - Pagos',
  };

  @override
  void initState() {
    super.initState();
    _loadBillingData();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _tradeNameController.dispose();
    _rfcController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadBillingData() async {
    try {
      final data = await Supabase.instance.client
          .from('clients')
          .select('business_name, trade_name, rfc, billing_email, billing_address, tax_regime, postal_code, cfdi_use')
          .eq('id', widget.clientId)
          .maybeSingle();

      if (data != null && mounted) {
        _businessNameController.text = data['business_name'] ?? '';
        _tradeNameController.text = data['trade_name'] ?? '';
        _rfcController.text = data['rfc'] ?? '';
        _emailController.text = data['billing_email'] ?? '';
        _addressController.text = data['billing_address'] ?? '';
        _postalCodeController.text = data['postal_code'] ?? '';
        
        final reg = data['tax_regime']?.toString();
        if (reg != null && _taxRegimes.containsKey(reg)) {
          _selectedTaxRegime = reg;
        }
        
        final use = data['cfdi_use']?.toString();
        if (use != null && _cfdiUses.containsKey(use)) {
          _selectedCfdiUse = use;
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await Supabase.instance.client
          .from('clients')
          .update({
            'business_name': _businessNameController.text.trim(),
            'trade_name': _tradeNameController.text.trim(),
            'rfc': _rfcController.text.toUpperCase().trim(),
            'billing_email': _emailController.text.trim(),
            'billing_address': _addressController.text.trim(),
            'tax_regime': _selectedTaxRegime,
            'postal_code': _postalCodeController.text.trim(),
            'cfdi_use': _selectedCfdiUse,
          })
          .eq('id', widget.clientId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos fiscales guardados con éxito'), backgroundColor: kPrimary),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: kRed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Datos Fiscales / Facturación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                            'Configuración de CFDI 4.0',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Configura tus datos de facturación para tus próximas compras y servicios de acuerdo con los requerimientos del SAT.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _sectionHeader('INFORMACIÓN DEL CONTRIBUYENTE'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _businessNameController,
                            decoration: InputDecoration(
                              labelText: 'Razón Social *',
                              hintText: 'Como aparece en la Constancia de Situación Fiscal',
                              prefixIcon: const Icon(Icons.business_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa la Razón Social' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _tradeNameController,
                            decoration: InputDecoration(
                              labelText: 'Nombre Comercial (opcional)',
                              prefixIcon: const Icon(Icons.store_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _rfcController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'RFC *',
                              hintText: '12 o 13 caracteres sin guiones',
                              prefixIcon: const Icon(Icons.badge_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Ingresa el RFC';
                              final cleanRfc = v.trim().toUpperCase();
                              if (cleanRfc.length < 12 || cleanRfc.length > 13) {
                                  return 'El RFC debe tener 12 o 13 caracteres';
                              }
                              final rfcRegExp = RegExp(r'^[A-Z&Ñ]{3,4}\d{6}[A-Z0-9]{3}$');
                              if (!rfcRegExp.hasMatch(cleanRfc)) {
                                return 'Formato de RFC inválido';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _sectionHeader('DATOS FISCALES Y SAT (CFDI 4.0)'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _postalCodeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Código Postal Fiscal *',
                              hintText: '5 dígitos del domicilio fiscal',
                              prefixIcon: const Icon(Icons.pin_drop_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Ingresa el Código Postal';
                              if (v.trim().length != 5 || int.tryParse(v.trim()) == null) {
                                return 'El Código Postal debe ser de 5 dígitos numéricos';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedTaxRegime,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Régimen Fiscal *',
                              prefixIcon: const Icon(Icons.gavel_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: _taxRegimes.entries.map((entry) {
                              return DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _selectedTaxRegime = v),
                            validator: (v) => v == null ? 'Selecciona el Régimen Fiscal' : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCfdiUse,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Uso de CFDI *',
                              prefixIcon: const Icon(Icons.description_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: _cfdiUses.entries.map((entry) {
                              return DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _selectedCfdiUse = v),
                            validator: (v) => v == null ? 'Selecciona el Uso de CFDI' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _sectionHeader('CONTACTO Y ENVÍO DE COMPROBANTES'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Correo de Facturación *',
                              hintText: 'Para recibir tus facturas XML y PDF',
                              prefixIcon: const Icon(Icons.email_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Ingresa el correo';
                              final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                              if (!emailRegExp.hasMatch(v.trim())) {
                                return 'Ingresa un correo electrónico válido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _addressController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'Dirección Fiscal (opcional)',
                              hintText: 'Calle, No., Colonia, Municipio, Estado',
                              prefixIcon: const Icon(Icons.home_outlined, color: kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Guardar Datos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8),
      ),
    );
  }
}
