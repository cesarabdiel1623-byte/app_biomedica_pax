import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/product_service.dart';
import 'profile_helpers.dart';
import 'order_detail_screen.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';

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

  Future<void> _loadOrders({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('orders')
            .select('''
              *,
              order_items(
                *,
                products(
                  *,
                  product_media(${ProductService.publicMediaColumns})
                )
              )
            ''')
            .eq('client_id', widget.clientId)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 30)),
        if (showSpinner) Future.delayed(const Duration(seconds: 2)),
      ]);
      if (mounted) {
        setState(() {
          _orders = results[0] as List;
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
      case 'draft':
        return 'Borrador';
      case 'pending_review':
        return 'En Revisión';
      case 'pending_payment':
        return 'Pendiente de Pago';
      case 'paid':
        return 'Pagado';
      case 'processing':
        return 'Procesando';
      case 'shipped':
        return 'Enviado';
      case 'delivered':
        return 'Entregado';
      case 'canceled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
      case 'delivered':
        return kGreen;
      case 'pending_payment':
      case 'pending_review':
        return kOrange;
      case 'processing':
      case 'shipped':
        return Colors.blue;
      case 'canceled':
        return kRed;
      default:
        return Colors.grey;
    }
  }

  String? _primaryProductImage(Map<String, dynamic> order) {
    final rawItems = order['order_items'];
    if (rawItems is! List) return null;

    for (final rawItem in rawItems.whereType<Map>()) {
      final product = rawItem['products'];
      if (product is! Map) continue;
      final rawMedia = product['product_media'];
      if (rawMedia is! List || rawMedia.isEmpty) continue;

      final media = rawMedia.whereType<Map>().toList();
      if (media.isEmpty) continue;
      final primary = media.firstWhere(
        (item) => item['is_primary'] == true,
        orElse: () => media.first,
      );
      final imageUrl = primary['file_path']?.toString().trim();
      if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;
    }
    return null;
  }

  String _primaryProductName(Map<String, dynamic> order) {
    final rawItems = order['order_items'];
    if (rawItems is! List || rawItems.isEmpty) {
      return order['order_number']?.toString() ?? 'Pedido';
    }

    for (final rawItem in rawItems.whereType<Map>()) {
      final nameSnapshot = rawItem['product_name_snapshot']?.toString().trim();
      if (nameSnapshot != null && nameSnapshot.isNotEmpty) return nameSnapshot;

      final product = rawItem['products'];
      if (product is Map) {
        final prodName = product['name']?.toString().trim();
        if (prodName != null && prodName.isNotEmpty) return prodName;
      }
    }
    return order['order_number']?.toString() ?? 'Pedido';
  }

  int _itemsCount(Map<String, dynamic> order) {
    final rawItems = order['order_items'];
    if (rawItems is! List) return 1;
    int count = 0;
    for (final rawItem in rawItems.whereType<Map>()) {
      final qty = (rawItem['quantity'] as num?)?.toInt() ?? 1;
      count += qty;
    }
    return count > 0 ? count : rawItems.length;
  }

  String _formatPurchaseDate(DateTime? date) {
    if (date == null) return '-';
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final month = months[date.month - 1];
    return 'Comprado el ${date.day} de $month.';
  }

  Widget _buildOrderImage(String? imageUrl) {
    const double imageSize = 72;
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        width: imageSize,
        height: imageSize,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Icon(Icons.image_outlined, color: Color(0xFFCBD5E1), size: 32),
        ),
      );
    }

    return Container(
      width: imageSize,
      height: imageSize,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: UiHelpers.networkImage(
          imageUrl,
          width: imageSize,
          height: imageSize,
          fit: BoxFit.contain,
          iconSize: 28,
          cacheWidth: 216,
          cacheHeight: 216,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Compras',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _error != null
          ? RefreshIndicator(
              color: kPrimary,
              backgroundColor: Colors.white,
              displacement: 42,
              triggerMode: RefreshIndicatorTriggerMode.onEdge,
              onRefresh: () => _loadOrders(showSpinner: false),
              child: ListView(
                physics: UiHelpers.refreshScrollPhysics,
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height - 200,
                    child: LoadErrorState(
                      error: _error,
                      onRetry: _loadOrders,
                      genericTitle: 'Error al cargar compras',
                      genericMessage:
                          'No pudimos cargar tus compras por el momento.',
                    ),
                  ),
                ],
              ),
            )
          : _orders.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: kPrimary,
              backgroundColor: Colors.white,
              displacement: 42,
              triggerMode: RefreshIndicatorTriggerMode.onEdge,
              onRefresh: () => _loadOrders(showSpinner: false),
              child: ListView.builder(
                physics: UiHelpers.refreshScrollPhysics,
                padding: const EdgeInsets.all(12),
                itemCount: _orders.length,
                itemBuilder: (context, i) {
                  final o = _orders[i];
                  final order = Map<String, dynamic>.from(o as Map);
                  final status = o['status']?.toString() ?? '';
                  final productImage = _primaryProductImage(order);
                  final productName = _primaryProductName(order);
                  final itemsCount = _itemsCount(order);
                  final total = (o['total'] as num?)?.toDouble() ?? 0.0;
                  final date = DateTime.tryParse(
                    o['created_at'] ?? '',
                  )?.toLocal();
                  final purchaseDateStr = _formatPurchaseDate(date);
                  final orderNumber = o['order_number']?.toString() ?? 'Pedido';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OrderDetailScreen(order: order),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left: Product Image / Placeholder
                              _buildOrderImage(productImage),
                              const SizedBox(width: 12),
                              // Middle: Product & Order Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      productName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: kNavy,
                                        fontSize: 14,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: purchaseDateStr,
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          TextSpan(
                                            text: '  |  ',
                                            style: TextStyle(
                                              color: Colors.grey.shade400,
                                              fontSize: 12,
                                            ),
                                          ),
                                          TextSpan(
                                            text: formatCurrency(total),
                                            style: const TextStyle(
                                              color: Color(0xFF0F172A),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  orderNumber,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF64748B),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              if (itemsCount > 1) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFF1F5F9,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '+${itemsCount - 1}',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF475569),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _statusColor(
                                              status,
                                            ).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                          child: Text(
                                            _statusLabel(status),
                                            style: TextStyle(
                                              color: _statusColor(status),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Padding(
                                padding: EdgeInsets.only(top: 24),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ),
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
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              size: 36,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No tienes compras aún',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tus compras y pedidos realizados aparecerán aquí.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
