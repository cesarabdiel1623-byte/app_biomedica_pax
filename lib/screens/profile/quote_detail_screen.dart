import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_helpers.dart';

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
  bool _requestingFollowUp = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _requestQuoteFollowUp() async {
    setState(() => _requestingFollowUp = true);
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seguimiento de cotización'),
          content: const Text(
            'Por seguridad, la aprobación final y generación del pedido se confirma con un asesor. Puedes dar seguimiento a esta cotización desde Soporte o esperar la confirmación de tu ejecutivo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _requestingFollowUp = false);
      }
    }
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
      case 'converted': return kGreen;
      case 'sent': return const Color(0xFF0284C7);
      case 'draft': return Colors.grey;
      case 'rejected':
      case 'expired': return kRed;
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
    final effectiveStatus = getEffectiveStatus(q);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(q['quote_number'] ?? 'Detalle de Cotización', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FOLIO DE COTIZACIÓN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(effectiveStatus).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(effectiveStatus).toUpperCase(),
                          style: TextStyle(
                            color: _statusColor(effectiveStatus),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q['quote_number'] ?? 'COT-N/A',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            'Fecha de Emisión: $dateStr',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy_outlined, size: 14, color: kRed.withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Text(
                            'Válida hasta: $validStr',
                            style: TextStyle(fontSize: 12.5, color: kRed, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (effectiveStatus == 'expired') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Esta cotización venció el día $validStr y ya no se encuentra vigente para su aprobación.',
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notes_outlined, color: kNavy, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Notas / Instrucciones del Cliente',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      q['notes'] != null && q['notes'].toString().trim().isNotEmpty
                          ? q['notes']
                          : 'Sin observaciones adicionales.',
                      style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Text(
                'EQUIPOS COTIZADOS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.8,
                ),
              ),
            ),

            _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: kPrimary)))
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error al cargar productos: $_error')))
                    : _items.isEmpty
                        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No hay productos vinculados.')))
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200, width: 1),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: img != null
                                          ? Image.network(
                                              img,
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => Container(width: 60, height: 60, color: Colors.grey.shade100, child: const Icon(Icons.broken_image, size: 24, color: Colors.grey)),
                                            )
                                          : Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                                              child: const Icon(Icons.medical_services, color: kPrimary, size: 24),
                                            ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['product_name_snapshot'] ?? 'Producto biomédico', style: const TextStyle(fontWeight: FontWeight.bold, color: kNavy, fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Text('Cantidad: $qty x ${formatCurrency(price)}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(formatCurrency(subtotalLine), style: const TextStyle(fontWeight: FontWeight.bold, color: kNavy, fontSize: 14)),
                                  ],
                                ),
                              );
                            },
                          ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resumen de Totales', style: TextStyle(fontWeight: FontWeight.bold, color: kNavy, fontSize: 14)),
                    const SizedBox(height: 12),
                    _summaryRow('Subtotal', formatCurrency(subtotal)),
                    const SizedBox(height: 8),
                    _summaryRow('IVA (16%)', formatCurrency(tax)),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, thickness: 1)),
                    _summaryRow('Total Cotizado', formatCurrency(total), bold: true, size: 16.5),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TÉRMINOS Y CONDICIONES',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• Los precios expresados están en pesos mexicanos (MXN) e incluyen IVA del 16%.\n'
                    '• Este presupuesto tiene una vigencia limitada según la fecha de vencimiento indicada.\n'
                    '• Para aclaraciones o soporte técnico, comuníquese con el departamento de ventas de Biomédica Pax.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: effectiveStatus == 'sent'
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -4)),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _requestingFollowUp ? null : _requestQuoteFollowUp,
                  child: _requestingFollowUp
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white), strokeWidth: 2),
                        )
                      : const Text(
                          'Solicitar Seguimiento',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, double size = 13}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: size, color: bold ? kNavy : Colors.grey.shade600, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: size, color: bold ? kPrimary : kNavy, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }
}
