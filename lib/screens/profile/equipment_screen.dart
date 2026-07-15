import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_helpers.dart';

class EquipmentScreen extends StatefulWidget {
  final String clientId;
  const EquipmentScreen({super.key, required this.clientId});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  List<dynamic> _equipment = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Supabase.instance.client
          .from('equipment_units')
          .select('*, products(name, brand, model, sku, category, subcategory, description, warranty_text, included_accessories)')
          .eq('current_client_id', widget.clientId)
          .order('created_at', ascending: false);
      if (mounted) setState(() { _equipment = response as List; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'available': return 'Disponible';
      case 'reserved': return 'Reservado';
      case 'sold': return 'Vendido';
      case 'installed': return 'Instalado';
      case 'maintenance': return 'En Mantenimiento';
      case 'out_of_service': return 'Fuera de Servicio';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'installed':
      case 'available': return kGreen;
      case 'maintenance':
      case 'reserved': return kOrange;
      case 'out_of_service': return kRed;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Mis Equipos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _equipment.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: kPrimary,
                      onRefresh: _loadEquipment,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _equipment.length,
                        itemBuilder: (context, i) {
                          final eq = _equipment[i];
                          final product = eq['products'] as Map?;
                          final name = product?['name'] ?? 'Equipo Médico';
                          final brand = product?['brand'] ?? '-';
                          final model = product?['model'] ?? '-';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EquipmentDetailScreen(equipment: eq),
                                  ),
                                );
                              },
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: kNavy), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: _statusColor(eq['status']).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                      child: Text(_statusLabel(eq['status'] ?? ''), style: TextStyle(color: _statusColor(eq['status'] ?? ''), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    Text('S/N: ${eq['serial_number'] ?? "-"}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                    Text('Marca/Modelo: $brand / $model', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ],
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: kPrimary.withValues(alpha: 0.08),
                                  child: const Icon(Icons.medical_services, color: kPrimary),
                                ),
                                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.medical_services_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('Sin equipos vinculados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          Text('Los equipos que hayas adquirido aparecerán aquí.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

class EquipmentDetailScreen extends StatelessWidget {
  final Map<String, dynamic> equipment;
  const EquipmentDetailScreen({super.key, required this.equipment});

  String _statusLabel(String status) {
    switch (status) {
      case 'available': return 'Disponible';
      case 'reserved': return 'Reservado';
      case 'sold': return 'Vendido';
      case 'installed': return 'Instalado';
      case 'maintenance': return 'En Mantenimiento';
      case 'out_of_service': return 'Fuera de Servicio';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'installed':
      case 'available': return kGreen;
      case 'maintenance':
      case 'reserved': return kOrange;
      case 'out_of_service': return kRed;
      default: return Colors.grey;
    }
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '-';
    final dateStr = dateVal.toString();
    if (dateStr.isEmpty) return '-';
    final date = DateTime.tryParse(dateStr)?.toLocal();
    if (date == null) return dateStr;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  bool _isWarrantyActive(dynamic endVal) {
    if (endVal == null) return false;
    final endStr = endVal.toString();
    if (endStr.isEmpty) return false;
    final date = DateTime.tryParse(endStr);
    if (date == null) return false;
    return date.isAfter(DateTime.now());
  }

  Future<void> _launchWhatsApp(BuildContext context, Map<String, dynamic> equipment) async {
    final product = equipment['products'] as Map?;
    final name = product?['name'] ?? 'Equipo Médico';
    final sku = product?['sku'] ?? 'N/A';
    final orderId = (equipment['order_id'] ?? equipment['id'] ?? '').toString();
    final shortOrderId = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;

    final message = 'Hola, necesito soporte técnico o mantenimiento para mi equipo:\n\n'
        '• Equipo: $name\n'
        '• SKU/Modelo: $sku\n'
        '• Folio de compra: #$shortOrderId';

    final encodedMessage = Uri.encodeComponent(message);
    final url = 'https://wa.me/529995266748?text=$encodedMessage';
    final uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'No se pudo lanzar la URL';
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir WhatsApp. Por favor contacta al soporte al 529995266748.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = equipment['products'] as Map?;
    final name = product?['name'] ?? 'Equipo Médico';
    final brand = product?['brand'] ?? 'No especificada';
    final model = product?['model'] ?? 'No especificado';
    final serialNumber = equipment['serial_number'] ?? '';
    final internalCode = equipment['internal_code'] ?? '';
    final status = equipment['status'] ?? '';
    final location = equipment['location'] ?? '';
    final notes = equipment['notes'] ?? '';
    
    // Dates
    final installDate = equipment['installation_date'];
    final mfgDate = equipment['manufacture_date'];
    final saleDate = equipment['sale_date'];
    final warStart = equipment['warranty_start'];
    final warEnd = equipment['warranty_end'];

    // Product Specifications
    final sku = product?['sku'] ?? '';
    final category = product?['category'] ?? '';
    final subcategory = product?['subcategory'] ?? '';
    final description = product?['description'] ?? '';
    final warrantyText = product?['warranty_text'] ?? '';
    final accessories = product?['included_accessories'] ?? '';

    final hasWarranty = warStart != null || warEnd != null || (warrantyText is String && warrantyText.isNotEmpty);
    final isWarActive = _isWarrantyActive(warEnd);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Detalle del Equipo',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kNavy, kPrimary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER CARD ────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: kPrimary.withValues(alpha: 0.08),
                      child: const Icon(Icons.medical_services, color: kPrimary, size: 30),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kNavy),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Marca/Modelo: $brand / $model',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _statusLabel(status).toUpperCase(),
                              style: TextStyle(
                                color: _statusColor(status),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── TECHNICAL DATA ─────────────────────
            _buildSectionTitle('Datos Técnicos'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow(
                      label: 'Número de Serie (S/N)',
                      value: serialNumber.toString().isNotEmpty ? serialNumber.toString() : 'No registrado',
                      icon: Icons.qr_code_rounded,
                      trailing: serialNumber.toString().isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 18, color: kPrimary),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: serialNumber.toString()));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Número de serie copiado al portapapeles'),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              tooltip: 'Copiar S/N',
                            )
                          : null,
                    ),
                    const Divider(height: 24),
                    _buildDetailRow(
                      label: 'Código Interno',
                      value: internalCode.toString().isNotEmpty ? internalCode.toString() : 'No asignado',
                      icon: Icons.tag,
                    ),
                    if (location.toString().isNotEmpty) ...[
                      const Divider(height: 24),
                      _buildDetailRow(
                        label: 'Ubicación / Área',
                        value: location.toString(),
                        icon: Icons.location_on_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── CHRONOLOGY & WARRANTY ──────────────
            _buildSectionTitle('Instalación y Garantía'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow(
                      label: 'Fecha de Instalación',
                      value: _formatDate(installDate),
                      icon: Icons.calendar_today_outlined,
                    ),
                    if (hasWarranty) ...[
                      const Divider(height: 24),
                      _buildDetailRow(
                        label: 'Vigencia de Garantía',
                        value: warStart != null || warEnd != null
                            ? '${_formatDate(warStart)} - ${_formatDate(warEnd)}'
                            : 'Registrado en contrato',
                        icon: Icons.verified_user_outlined,
                        trailing: warEnd != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isWarActive ? kGreen : kRed).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isWarActive ? 'Vigente' : 'Expirada',
                                  style: TextStyle(
                                    color: isWarActive ? kGreen : kRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      if (warrantyText is String && warrantyText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            warrantyText,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ],
                    if (mfgDate != null) ...[
                      const Divider(height: 24),
                      _buildDetailRow(
                        label: 'Fecha de Fabricación',
                        value: _formatDate(mfgDate),
                        icon: Icons.precision_manufacturing_outlined,
                      ),
                    ],
                    if (saleDate != null) ...[
                      const Divider(height: 24),
                      _buildDetailRow(
                        label: 'Fecha de Adquisición',
                        value: _formatDate(saleDate),
                        icon: Icons.shopping_bag_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── PRODUCT INFO ───────────────────────
            _buildSectionTitle('Especificaciones del Catálogo'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sku.toString().isNotEmpty) ...[
                      _buildDetailRow(
                        label: 'SKU / Modelo de Referencia',
                        value: sku.toString(),
                        icon: Icons.fingerprint,
                      ),
                      const Divider(height: 24),
                    ],
                    if (category.toString().isNotEmpty || subcategory.toString().isNotEmpty) ...[
                      _buildDetailRow(
                        label: 'Categoría',
                        value: [
                          if (category.toString().isNotEmpty) category.toString(),
                          if (subcategory.toString().isNotEmpty) subcategory.toString()
                        ].join(' › '),
                        icon: Icons.category_outlined,
                      ),
                      const Divider(height: 24),
                    ],
                    if (accessories.toString().isNotEmpty) ...[
                      _buildDetailRow(
                        label: 'Accesorios Incluidos',
                        value: accessories.toString(),
                        icon: Icons.plumbing_outlined,
                      ),
                      const Divider(height: 24),
                    ],
                    Row(
                      children: const [
                        Icon(Icons.description_outlined, size: 20, color: kNavy),
                        SizedBox(width: 8),
                        Text(
                          'Descripción de Fábrica',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kNavy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description.toString().isNotEmpty ? description.toString() : 'Sin descripción detallada disponible en el catálogo.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            
            // ── NOTES ──────────────────────────────
            if (notes.toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionTitle('Notas / Historial Interno'),
              Card(
                elevation: 0,
                color: Colors.amber.shade50.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.amber.shade200, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.note_alt_outlined, color: Colors.amber.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          notes.toString(),
                          style: TextStyle(fontSize: 13, color: Colors.amber.shade900, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4)),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => _launchWhatsApp(context, equipment),
            icon: const Icon(Icons.chat),
            label: const Text(
              'Solicitar Soporte vía WhatsApp',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kNavy, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required IconData icon,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kNavy.withValues(alpha: 0.7)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kNavy),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
