import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/product_service.dart';
import 'profile_helpers.dart';

class QuoteRequestDetailScreen extends StatefulWidget {
  const QuoteRequestDetailScreen({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  State<QuoteRequestDetailScreen> createState() =>
      _QuoteRequestDetailScreenState();
}

class _QuoteRequestDetailScreenState extends State<QuoteRequestDetailScreen> {
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
          .from('quote_request_items')
          .select(
            '*, products(brand, product_media(${ProductService.publicMediaColumns}))',
          )
          .eq('quote_request_id', widget.request['id'])
          .order('created_at', ascending: true);

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
      case 'pending':
        return 'Pendiente';
      case 'reviewing':
        return 'En revisión';
      case 'quoted':
        return 'Cotizada';
      case 'closed':
        return 'Cerrada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'quoted':
        return const Color(0xFF0284C7);
      case 'closed':
        return kGreen;
      case 'cancelled':
        return kRed;
      case 'pending':
      case 'reviewing':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final date = DateTime.tryParse(request['created_at'] ?? '')?.toLocal();
    final dateStr = date != null
        ? '${date.day}/${date.month}/${date.year}'
        : '-';
    final status = (request['status'] as String?) ?? 'pending';
    final companyName = request['company_name'] as String?;
    final contactName = request['contact_name'] as String? ?? '-';
    final contactEmail = request['contact_email'] as String? ?? '-';
    final contactPhone = request['contact_phone'] as String?;
    final message = request['message'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          request['request_number'] ?? 'Solicitud de cotización',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SOLICITUD DE COTIZACIÓN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(status).toUpperCase(),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    request['request_number'] ?? 'RQ-N/A',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Fecha: $dateStr',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  if (companyName != null && companyName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Empresa: $companyName',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Contacto: $contactName',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Correo: $contactEmail',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  if (contactPhone != null && contactPhone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Teléfono: $contactPhone',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (message != null && message.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Productos solicitados',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(color: kPrimary),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'No pudimos cargar los productos de la solicitud.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Esta solicitud todavía no tiene productos visibles.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index] as Map<String, dynamic>;
                  final product = item['products'] as Map<String, dynamic>?;
                  final quantity = item['quantity'] as num? ?? 0;
                  final itemName =
                      item['item_name'] as String? ??
                      product?['name'] as String? ??
                      'Producto';
                  final sku = item['sku'] as String?;
                  final brand = product?['brand'] as String?;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: kNavy,
                          ),
                        ),
                        if (brand != null && brand.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            brand,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text(
                              'Cantidad: ${quantity.toInt()}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (sku != null && sku.isNotEmpty)
                              Text(
                                'SKU: $sku',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
