import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFEF4444);
const _kOrange = Color(0xFFF59E0B);

// Helper function to format prices
String _formatCurrency(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final buf = StringBuffer();
  for (int i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
    buf.write(parts[0][i]);
  }
  return '\$$buf.${parts[1]} MXN';
}

// ==========================================
// 1. MIS PEDIDOS SCREEN
// ==========================================
class OrdersScreen extends StatefulWidget {
  final String clientId;
  const OrdersScreen({super.key, required this.clientId});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Supabase.instance.client
          .from('orders')
          .select('*')
          .eq('client_id', widget.clientId)
          .order('created_at', ascending: false);
      if (mounted) setState(() { _orders = response as List; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft': return 'Borrador';
      case 'pending_review': return 'En Revisión';
      case 'pending_payment': return 'Pendiente de Pago';
      case 'paid': return 'Pagado';
      case 'processing': return 'Procesando';
      case 'shipped': return 'Enviado';
      case 'delivered': return 'Entregado';
      case 'canceled': return 'Cancelado';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
      case 'delivered': return _kGreen;
      case 'pending_payment':
      case 'pending_review': return _kOrange;
      case 'processing':
      case 'shipped': return Colors.blue;
      case 'canceled': return _kRed;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Mis Pedidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _orders.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _kPrimary,
                      onRefresh: _loadOrders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _orders.length,
                        itemBuilder: (context, i) {
                          final o = _orders[i];
                          final total = (o['total'] as num?)?.toDouble() ?? 0.0;
                          final date = DateTime.tryParse(o['created_at'] ?? '')?.toLocal();
                          final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => OrderDetailScreen(order: o)),
                                );
                              },
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(o['order_number'] ?? 'Pedido', style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: _statusColor(o['status']).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                    child: Text(_statusLabel(o['status'] ?? ''), style: TextStyle(color: _statusColor(o['status'] ?? ''), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Text('Fecha: $dateStr', style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text('Total: ${_formatCurrency(total)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                                ],
                              ),
                              leading: CircleAvatar(
                                backgroundColor: _kPrimary.withOpacity(0.08),
                                child: const Icon(Icons.receipt_long, color: _kPrimary),
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
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No tienes pedidos aún', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy)),
          const SizedBox(height: 4),
          Text('Tus compras y órdenes aparecerán aquí.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

// ==========================================
// 2. COTIZACIONES SCREEN
// ==========================================
class QuotesScreen extends StatefulWidget {
  final String clientId;
  const QuotesScreen({super.key, required this.clientId});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  List<dynamic> _quotes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Supabase.instance.client
          .from('quotes')
          .select('*')
          .eq('client_id', widget.clientId)
          .order('created_at', ascending: false);
      if (mounted) setState(() { _quotes = response as List; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft': return 'Borrador';
      case 'sent': return 'Enviado';
      case 'approved': return 'Aprobado';
      case 'rejected': return 'Rechazado';
      case 'expired': return 'Vencido';
      case 'converted': return 'Convertido';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
      case 'converted': return _kGreen;
      case 'sent': return Colors.blue;
      case 'draft': return Colors.grey;
      case 'rejected':
      case 'expired': return _kRed;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Cotizaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _quotes.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _kPrimary,
                      onRefresh: _loadQuotes,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _quotes.length,
                        itemBuilder: (context, i) {
                          final q = _quotes[i];
                          final total = (q['total'] as num?)?.toDouble() ?? 0.0;
                          final date = DateTime.tryParse(q['created_at'] ?? '')?.toLocal();
                          final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => QuoteDetailScreen(quote: q)),
                                );
                              },
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(q['quote_number'] ?? 'Cotización', style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: _statusColor(q['status']).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                    child: Text(_statusLabel(q['status'] ?? ''), style: TextStyle(color: _statusColor(q['status'] ?? ''), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Text('Fecha: $dateStr', style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text('Importe total: ${_formatCurrency(total)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                                ],
                              ),
                              leading: CircleAvatar(
                                backgroundColor: _kPrimary.withOpacity(0.08),
                                child: const Icon(Icons.request_quote, color: _kPrimary),
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
          Icon(Icons.request_quote_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('Sin cotizaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy)),
          const SizedBox(height: 4),
          Text('Tus cotizaciones y presupuestos aparecerán aquí.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

// ==========================================
// 3. MIS EQUIPOS SCREEN
// ==========================================
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
      case 'available': return _kGreen;
      case 'maintenance':
      case 'reserved': return _kOrange;
      case 'out_of_service': return _kRed;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Mis Equipos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _equipment.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _kPrimary,
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
                                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: _statusColor(eq['status']).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
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
                                  backgroundColor: _kPrimary.withOpacity(0.08),
                                  child: const Icon(Icons.medical_services, color: _kPrimary),
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
          const Text('Sin equipos vinculados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy)),
          const SizedBox(height: 4),
          Text('Los equipos que hayas adquirido aparecerán aquí.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

// ==========================================
// 3B. DETALLE DE EQUIPO SCREEN
// ==========================================
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
      case 'available': return _kGreen;
      case 'maintenance':
      case 'reserved': return _kOrange;
      case 'out_of_service': return _kRed;
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
              colors: [_kNavy, _kPrimary],
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
                      backgroundColor: _kPrimary.withOpacity(0.08),
                      child: const Icon(Icons.medical_services, color: _kPrimary, size: 30),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kNavy),
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
                              color: _statusColor(status).withOpacity(0.12),
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
                              icon: const Icon(Icons.copy_rounded, size: 18, color: _kPrimary),
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
                                  color: (isWarActive ? _kGreen : _kRed).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isWarActive ? 'Vigente' : 'Expirada',
                                  style: TextStyle(
                                    color: isWarActive ? _kGreen : _kRed,
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
                        Icon(Icons.description_outlined, size: 20, color: _kNavy),
                        SizedBox(width: 8),
                        Text(
                          'Descripción de Fábrica',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy),
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
                color: Colors.amber.shade50.withOpacity(0.4),
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
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kNavy, letterSpacing: 0.5),
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
        Icon(icon, size: 20, color: _kNavy.withOpacity(0.7)),
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
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}

// ==========================================
// 4. FACTURACIÓN SCREEN
// ==========================================
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

  bool _loading = true;
  bool _saving = false;

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
    super.dispose();
  }

  Future<void> _loadBillingData() async {
    try {
      final data = await Supabase.instance.client
          .from('clients')
          .select('business_name, trade_name, rfc, billing_email, billing_address')
          .eq('id', widget.clientId)
          .maybeSingle();

      if (data != null && mounted) {
        _businessNameController.text = data['business_name'] ?? '';
        _tradeNameController.text = data['trade_name'] ?? '';
        _rfcController.text = data['rfc'] ?? '';
        _emailController.text = data['billing_email'] ?? '';
        _addressController.text = data['billing_address'] ?? '';
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
          })
          .eq('id', widget.clientId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos fiscales guardados con éxito'), backgroundColor: _kPrimary),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: _kRed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Datos Fiscales / Facturación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Configura tus datos de facturación para tus próximas compras y servicios.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _businessNameController,
                    decoration: InputDecoration(labelText: 'Razón Social *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa la Razón Social' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _tradeNameController,
                    decoration: InputDecoration(labelText: 'Nombre Comercial', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _rfcController,
                    decoration: InputDecoration(labelText: 'RFC *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresa el RFC';
                      if (v.trim().length < 12 || v.trim().length > 13) return 'El RFC debe tener 12 o 13 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: 'Correo de Facturación *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el correo' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: 'Dirección Fiscal', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Guardar Datos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ==========================================
// 5. MANTENIMIENTOS SCREEN
// ==========================================
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
  
  // New Controllers
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _areaController = TextEditingController();
  final _errorCodeController = TextEditingController();

  String _ticketType = 'preventivo';
  String _priority = 'medium';
  String? _selectedEquipmentId;
  List<dynamic> _equipments = [];
  bool _loading = true;
  bool _submitting = false;

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
    super.dispose();
  }

  Future<void> _loadEquipments() async {
    try {
      final response = await Supabase.instance.client
          .from('equipment_units')
          .select('*, products(name)')
          .eq('current_client_id', widget.clientId);
      if (mounted) {
        setState(() {
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
    setState(() => _submitting = true);

    try {
      String eqName = 'Equipo general';
      String? eqUnitId = _selectedEquipmentId;

      if (_selectedEquipmentId == 'otro' || _equipments.isEmpty) {
        eqName = _customEquipmentController.text.trim();
        eqUnitId = null;
      } else if (_selectedEquipmentId != null) {
        final eq = _equipments.firstWhere((e) => e['id'] == _selectedEquipmentId);
        eqName = eq['products']?['name'] ?? 'Equipo';
      }

      final descriptionText = StringBuffer();
      descriptionText.writeln('=== DETALLES DE LA SOLICITUD ===');
      descriptionText.writeln('Equipo: $eqName');
      if (_selectedEquipmentId == 'otro' || _equipments.isEmpty) {
        descriptionText.writeln('S/N: ${_customSerialController.text.trim()}');
      }
      descriptionText.writeln('Responsable: ${_contactNameController.text.trim()}');
      descriptionText.writeln('Teléfono: ${_contactPhoneController.text.trim()}');
      descriptionText.writeln('Área/Depto: ${_areaController.text.trim()}');
      descriptionText.writeln('Fecha/Hora: Coordinar con Administración');
      if (_errorCodeController.text.trim().isNotEmpty) {
        descriptionText.writeln('Código de Error: ${_errorCodeController.text.trim()}');
      }
      descriptionText.writeln('\n=== DESCRIPCIÓN DE LA FALLA ===');
      descriptionText.writeln(_descController.text.trim());

      // Crear un ticket de servicio para el mantenimiento
      await Supabase.instance.client.from('service_tickets').insert({
        'client_id': widget.clientId,
        'equipment_unit_id': eqUnitId,
        'title': 'Solicitud Mantenimiento: $eqName',
        'description': descriptionText.toString(),
        'type': _ticketType,
        'priority': _priority,
        'status': 'open',
        'requested_by': Supabase.instance.client.auth.currentUser?.id,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud de mantenimiento enviada con éxito'), backgroundColor: _kPrimary),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar solicitud: $e'), backgroundColor: _kRed),
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
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Form header card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Solicitud de Servicio Biomédico',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy),
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

                  // Section: Technical Info
                  _sectionHeader('INFORMACIÓN TÉCNICA'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDropdown) ...[
                            DropdownButtonFormField<String>(
                              value: _selectedEquipmentId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Selecciona tu Equipo *',
                                prefixIcon: const Icon(Icons.medical_services_outlined, color: _kPrimary),
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
                                  child: Text('Otro (Ingresar manualmente)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kPrimary)),
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
                                prefixIcon: const Icon(Icons.settings, color: _kPrimary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el nombre del equipo' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _customSerialController,
                              decoration: InputDecoration(
                                labelText: 'Número de Serie (opcional)',
                                prefixIcon: const Icon(Icons.tag, color: _kPrimary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          DropdownButtonFormField<String>(
                            value: _ticketType,
                            decoration: InputDecoration(
                              labelText: 'Tipo de Servicio *',
                              prefixIcon: const Icon(Icons.engineering_outlined, color: _kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'preventivo', child: Text('Mantenimiento Preventivo')),
                              DropdownMenuItem(value: 'correctivo', child: Text('Mantenimiento Correctivo')),
                              DropdownMenuItem(value: 'garantia', child: Text('Servicio de Garantía')),
                              DropdownMenuItem(value: 'instalacion', child: Text('Instalación y Puesta en Marcha')),
                              DropdownMenuItem(value: 'revision', child: Text('Revisión / Diagnóstico')),
                              DropdownMenuItem(value: 'otro', child: Text('Otro Servicio Técnico')),
                            ],
                            onChanged: (v) => setState(() => _ticketType = v ?? 'preventivo'),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _priority,
                            decoration: InputDecoration(
                              labelText: 'Prioridad del Reporte *',
                              prefixIcon: const Icon(Icons.warning_amber_rounded, color: _kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'low', child: Text('Baja - Rutinario')),
                              DropdownMenuItem(value: 'medium', child: Text('Media - Normal')),
                              DropdownMenuItem(value: 'high', child: Text('Alta - Urgente')),
                              DropdownMenuItem(value: 'urgent', child: Text('Crítica - Equipo fuera de servicio')),
                            ],
                            onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _errorCodeController,
                            decoration: InputDecoration(
                              labelText: 'Código de Error (opcional)',
                              hintText: 'Ej. Err 03, E-102',
                              prefixIcon: const Icon(Icons.bug_report_outlined, color: _kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Section: Contact & Logistics
                  _sectionHeader('CONTACTO Y LOGÍSTICA'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _contactNameController,
                            decoration: InputDecoration(
                              labelText: 'Nombre del Responsable *',
                              prefixIcon: const Icon(Icons.person_outline, color: _kPrimary),
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
                              prefixIcon: const Icon(Icons.phone_outlined, color: _kPrimary),
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
                              prefixIcon: const Icon(Icons.meeting_room_outlined, color: _kPrimary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el área del equipo' : null,
                          ),

                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Section: Failure details
                  _sectionHeader('DESCRIPCIÓN DE LA FALLA'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextFormField(
                        controller: _descController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Detalla el síntoma, falla o requerimiento *',
                          hintText: 'Por favor describe lo más detallado posible el comportamiento del equipo.',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Describe los detalles de la falla o requerimiento' : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
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
                  const SizedBox(height: 20),
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

// ==========================================
// 6. EDITAR PERFIL SCREEN
// ==========================================
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        _nameController.text = user.userMetadata?['full_name'] as String? ?? '';
        _phoneController.text = user.phone ?? '';
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone')
          .eq('id', user?.id ?? '')
          .maybeSingle();

      if (profile != null && mounted) {
        if (profile['full_name'] != null && profile['full_name'].toString().isNotEmpty) {
          _nameController.text = profile['full_name'];
        }
        if (profile['phone'] != null && profile['phone'].toString().isNotEmpty) {
          _phoneController.text = profile['phone'];
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
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      // Actualizar tabla profiles
      await Supabase.instance.client.from('profiles').update({
        'full_name': name,
        'phone': phone,
      }).eq('id', userId ?? '');

      // Actualizar metadatos de auth del usuario
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'full_name': name}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado con éxito'), backgroundColor: _kPrimary),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: _kRed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Editar Perfil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: 'Nombre Completo *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa tu nombre' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Guardar Cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ==========================================
// 7. NOTIFICACIONES SCREEN
// ==========================================
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _whatsapp = true;
  bool _email = true;
  bool _orderUpdates = true;
  bool _security = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _whatsapp = prefs.getBool('notif_whatsapp') ?? true;
        _email = prefs.getBool('notif_email') ?? true;
        _orderUpdates = prefs.getBool('notif_orders') ?? true;
        _security = prefs.getBool('notif_security') ?? true;
        _loading = false;
      });
    }
  }

  Future<void> _savePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Notificaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                SwitchListTile(
                  title: const Text('Alertas por WhatsApp', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Recibe actualizaciones de tus tickets y cotizaciones vía WhatsApp.', style: TextStyle(fontSize: 11)),
                  value: _whatsapp,
                  activeColor: _kPrimary,
                  onChanged: (v) {
                    setState(() => _whatsapp = v);
                    _savePref('notif_whatsapp', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Notificaciones por Correo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Recibe presupuestos y comprobantes de compra en tu email.', style: TextStyle(fontSize: 11)),
                  value: _email,
                  activeColor: _kPrimary,
                  onChanged: (v) {
                    setState(() => _email = v);
                    _savePref('notif_email', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Seguimiento de Pedidos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Notificaciones en tiempo real del estado de tus órdenes.', style: TextStyle(fontSize: 11)),
                  value: _orderUpdates,
                  activeColor: _kPrimary,
                  onChanged: (v) {
                    setState(() => _orderUpdates = v);
                    _savePref('notif_orders', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Seguridad y Acceso', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Notificaciones sobre inicios de sesión y cambios de contraseña.', style: TextStyle(fontSize: 11)),
                  value: _security,
                  activeColor: _kPrimary,
                  onChanged: (v) {
                    setState(() => _security = v);
                    _savePref('notif_security', v);
                  },
                ),
              ],
            ),
    );
  }
}

// ==========================================
// 8. NOTIFICATIONS LIST SCREEN
// ==========================================
class NotificationsListScreen extends StatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() => _NotificationsListScreenState();
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() { _loading = true; _error = null; });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('No autenticado');

      final response = await Supabase.instance.client
          .from('notifications')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notifications = response as List;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
      _loadNotifications();
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      _loadNotifications();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Notificaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_notifications.any((n) => n['is_read'] == false))
            IconButton(
              icon: const Icon(Icons.mark_chat_read, size: 20),
              tooltip: 'Marcar todas como leídas',
              onPressed: _markAllAsRead,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _notifications.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _kPrimary,
                      onRefresh: _loadNotifications,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _notifications.length,
                        itemBuilder: (context, i) {
                          final n = _notifications[i];
                          final isRead = n['is_read'] as bool? ?? false;
                          final date = DateTime.tryParse(n['created_at'] ?? '')?.toLocal();
                          final dateStr = date != null ? '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}' : '-';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                            color: isRead ? Colors.white : const Color(0xFFF0FDF4),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              title: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isRead)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6, right: 6),
                                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _kPrimary, shape: BoxShape.circle)),
                                    ),
                                  Expanded(
                                    child: Text(
                                      n['title'] ?? 'Notificación',
                                      style: TextStyle(fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, color: _kNavy),
                                    ),
                                  ),
                                  Text(dateStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  n['body'] ?? '',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3),
                                ),
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isRead ? Colors.grey.shade100 : _kPrimary.withOpacity(0.08),
                                child: Icon(
                                  isRead ? Icons.notifications_none : Icons.notifications_active,
                                  color: isRead ? Colors.grey.shade500 : _kPrimary,
                                ),
                              ),
                              onTap: isRead ? null : () => _markAsRead(n['id'] as String),
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
          Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No tienes notificaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy)),
          const SizedBox(height: 4),
          Text('Te mantendremos al tanto de tus compras y servicios.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

// ==========================================
// ORDER DETAIL SCREEN
// ==========================================
class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final response = await Supabase.instance.client
          .from('order_items')
          .select('*, products(brand, product_media(*))')
          .eq('order_id', widget.order['id']);
      if (mounted) {
        setState(() {
          _items = response as List;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft': return 'Borrador';
      case 'pending_review': return 'En Revisión';
      case 'pending_payment': return 'Pendiente de Pago';
      case 'paid': return 'Pagado';
      case 'processing': return 'Procesando';
      case 'shipped': return 'Enviado';
      case 'delivered': return 'Entregado';
      case 'canceled': return 'Cancelado';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
      case 'delivered': return _kGreen;
      case 'pending_payment':
      case 'pending_review': return _kOrange;
      case 'processing':
      case 'shipped': return Colors.blue;
      case 'canceled': return _kRed;
      default: return Colors.grey;
    }
  }

  Widget _buildOrderPhases(String status) {
    if (status == 'canceled') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kRed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kRed.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel, color: _kRed, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Pedido Cancelado',
              style: TextStyle(color: _kRed, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );
    }

    int currentStep = 0;
    if (status == 'shipped') {
      currentStep = 1;
    } else if (status == 'delivered') {
      currentStep = 2;
    }

    final steps = [
      {'label': 'En bodega', 'desc': 'Preparando envío'},
      {'label': 'En proceso', 'desc': 'En camino'},
      {'label': 'Entregado', 'desc': '¡Entregado!'},
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seguimiento del envío',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kNavy),
          ),
          const SizedBox(height: 20),
          
          // Progress Dots & Line Row
          Stack(
            alignment: Alignment.center,
            children: [
              // Background line
              Positioned(
                left: 30,
                right: 30,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Active progress line
              Positioned(
                left: 30,
                right: 30,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    double progressPercent = 0.0;
                    if (currentStep == 1) progressPercent = 0.5;
                    if (currentStep == 2) progressPercent = 1.0;
                    
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: totalWidth * progressPercent,
                        height: 3,
                        decoration: BoxDecoration(
                          color: _kGreen,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Dots Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(steps.length, (index) {
                  final isCompleted = index <= currentStep;
                  final isActive = index == currentStep;
                  
                  return Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? Colors.white : (isCompleted ? _kGreen : Colors.white),
                      border: Border.all(
                        color: isCompleted ? _kGreen : Colors.grey.shade300,
                        width: isActive ? 6 : 2,
                      ),
                      boxShadow: isActive ? [
                        BoxShadow(color: _kGreen.withOpacity(0.3), blurRadius: 6, spreadRadius: 1)
                      ] : null,
                    ),
                    child: isCompleted && !isActive
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  );
                }),
              ),
            ],
          ),
          
          const SizedBox(height: 10),
          
          // Text labels Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(steps.length, (index) {
              final isCompleted = index <= currentStep;
              final isActive = index == currentStep;
              
              Alignment align = Alignment.center;
              if (index == 0) align = Alignment.centerLeft;
              if (index == steps.length - 1) align = Alignment.centerRight;

              return Expanded(
                child: Align(
                  alignment: align,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: index == 0 
                        ? CrossAxisAlignment.start 
                        : (index == steps.length - 1 ? CrossAxisAlignment.end : CrossAxisAlignment.center),
                    children: [
                      Text(
                        steps[index]['label']!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                          color: isCompleted ? _kNavy : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        steps[index]['desc']!,
                        style: TextStyle(
                          fontSize: 9,
                          color: isActive ? _kGreen : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final total = (o['total'] as num?)?.toDouble() ?? 0.0;
    final subtotal = (o['subtotal'] as num?)?.toDouble() ?? 0.0;
    final tax = (o['tax'] as num?)?.toDouble() ?? 0.0;
    final date = DateTime.tryParse(o['created_at'] ?? '')?.toLocal();
    final dateStr = date != null ? '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}' : '-';
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(o['order_number'] ?? 'Detalle de Pedido', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Date banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Estado del Pedido', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(o['status'] ?? '').withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(o['status'] ?? '').toUpperCase(),
                          style: TextStyle(
                            color: _statusColor(o['status'] ?? ''),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Fecha de Creación: $dateStr', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                ],
              ),
            ),
            _buildOrderPhases(o['status'] ?? ''),
            const SizedBox(height: 4),

            // Delivery and Payment Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.local_shipping_outlined, color: _kNavy, size: 20),
                          SizedBox(width: 8),
                          Text('Dirección de Envío', style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        o['shipping_address'] ?? 'Entrega e instalación a convenir.',
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      const Divider(height: 24),
                      const Row(
                        children: [
                          Icon(Icons.notes_outlined, color: _kNavy, size: 20),
                          SizedBox(width: 8),
                          Text('Notas / Instrucciones', style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        o['notes'] != null && o['notes'].toString().trim().isNotEmpty
                            ? o['notes']
                            : 'Sin instrucciones adicionales.',
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Products list title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('PRODUCTOS EN EL PEDIDO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8)),
            ),

            // Items List
            _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: _kPrimary)))
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error al cargar productos: $_error')))
                    : _items.isEmpty
                        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No hay productos vinculados.')))
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _items.length,
                            itemBuilder: (ctx, i) {
                              final item = _items[i];
                              final p = item['products'] as Map?;
                              String? img;
                              if (p != null) {
                                final media = p['product_media'] as List?;
                                if (media != null && media.isNotEmpty) {
                                  final primary = media.firstWhere(
                                    (m) => m['is_primary'] == true,
                                    orElse: () => media.first,
                                  );
                                  img = primary['file_path'] as String?;
                                }
                              }
                              final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                              final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                              final subtotalLine = (item['total_line_price'] as num?)?.toDouble() ?? (qty * price);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      if (img != null)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(img, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 50, height: 50, color: Colors.grey.shade100, child: const Icon(Icons.broken_image, size: 20))),
                                        )
                                      else
                                        Container(width: 50, height: 50, decoration: BoxDecoration(color: _kPrimary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.medical_services, color: _kPrimary, size: 20)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['product_name_snapshot'] ?? 'Producto biomédico', style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 4),
                                            Text('Cantidad: $qty x ${_formatCurrency(price)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_formatCurrency(subtotalLine), style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
            const SizedBox(height: 12),

            // Financial Summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Resumen de Pago', style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14)),
                      const SizedBox(height: 12),
                      _summaryRow('Subtotal', _formatCurrency(subtotal)),
                      const SizedBox(height: 6),
                      _summaryRow('IVA (16%)', _formatCurrency(tax)),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                      _summaryRow('Total', _formatCurrency(total), bold: true, size: 16),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, double size = 13}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: size, color: bold ? _kNavy : Colors.grey.shade600, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: size, color: bold ? _kPrimary : _kNavy, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }
}

// ==========================================
// QUOTE DETAIL SCREEN
// ==========================================
class QuoteDetailScreen extends StatefulWidget {
  final Map<String, dynamic> quote;
  const QuoteDetailScreen({super.key, required this.quote});

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final response = await Supabase.instance.client
          .from('quote_items')
          .select('*, products(brand, product_media(*))')
          .eq('quote_id', widget.quote['id']);
      if (mounted) {
        setState(() {
          _items = response as List;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft': return 'Borrador';
      case 'sent': return 'Enviado';
      case 'approved': return 'Aprobado';
      case 'rejected': return 'Rechazado';
      case 'expired': return 'Vencido';
      case 'converted': return 'Convertido';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
      case 'converted': return _kGreen;
      case 'sent': return Colors.blue;
      case 'draft': return Colors.grey;
      case 'rejected':
      case 'expired': return _kRed;
      default: return Colors.grey;
    }
  }



  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    final total = (q['total'] as num?)?.toDouble() ?? 0.0;
    final subtotal = (q['subtotal'] as num?)?.toDouble() ?? 0.0;
    final tax = (q['tax'] as num?)?.toDouble() ?? 0.0;
    final date = DateTime.tryParse(q['created_at'] ?? '')?.toLocal();
    final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
    
    final validDate = DateTime.tryParse(q['valid_until'] ?? '')?.toLocal();
    final validStr = validDate != null ? '${validDate.day}/${validDate.month}/${validDate.year}' : '15 días a partir de la creación';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(q['quote_number'] ?? 'Detalle de Cotización', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Estado de la Cotización', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(q['status'] ?? '').withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(q['status'] ?? '').toUpperCase(),
                          style: TextStyle(
                            color: _statusColor(q['status'] ?? ''),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Fecha de Emisión: $dateStr', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text('Válida hasta: $validStr', style: TextStyle(fontSize: 13, color: _kRed, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Actions or Notes Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notes_outlined, color: _kNavy, size: 20),
                          SizedBox(width: 8),
                          Text('Notas / Instrucciones del Cliente', style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        q['notes'] != null && q['notes'].toString().trim().isNotEmpty
                            ? q['notes']
                            : 'Sin observaciones adicionales.',
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Products list title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('EQUIPOS COTIZADOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8)),
            ),

            // Items List
            _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: _kPrimary)))
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error al cargar productos: $_error')))
                    : _items.isEmpty
                        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No hay productos vinculados.')))
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _items.length,
                            itemBuilder: (ctx, i) {
                              final item = _items[i];
                              final p = item['products'] as Map?;
                              String? img;
                              if (p != null) {
                                final media = p['product_media'] as List?;
                                if (media != null && media.isNotEmpty) {
                                  final primary = media.firstWhere(
                                    (m) => m['is_primary'] == true,
                                    orElse: () => media.first,
                                  );
                                  img = primary['file_path'] as String?;
                                }
                              }
                              final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                              final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                              final subtotalLine = (item['total_line_price'] as num?)?.toDouble() ?? (qty * price);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      if (img != null)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(img, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 50, height: 50, color: Colors.grey.shade100, child: const Icon(Icons.broken_image, size: 20))),
                                        )
                                      else
                                        Container(width: 50, height: 50, decoration: BoxDecoration(color: _kPrimary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.medical_services, color: _kPrimary, size: 20)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['product_name_snapshot'] ?? 'Producto biomédico', style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 4),
                                            Text('Cantidad: $qty x ${_formatCurrency(price)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_formatCurrency(subtotalLine), style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
            const SizedBox(height: 12),

            // Financial Summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Resumen Económico', style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14)),
                      const SizedBox(height: 12),
                      _summaryRow('Subtotal', _formatCurrency(subtotal)),
                      const SizedBox(height: 6),
                      _summaryRow('IVA (16%)', _formatCurrency(tax)),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                      _summaryRow('Total Cotizado', _formatCurrency(total), bold: true, size: 16),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, double size = 13}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: size, color: bold ? _kNavy : Colors.grey.shade600, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: size, color: bold ? _kPrimary : _kNavy, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }
}

