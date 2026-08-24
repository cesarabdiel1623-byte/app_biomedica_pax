import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
            .select('*')
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Mis Pedidos',
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
                      genericTitle: 'Error al cargar pedidos',
                      genericMessage:
                          'No pudimos cargar tus pedidos por el momento.',
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
                  final status = o['status']?.toString() ?? '';
                  final total = (o['total'] as num?)?.toDouble() ?? 0.0;
                  final date = DateTime.tryParse(
                    o['created_at'] ?? '',
                  )?.toLocal();
                  final dateStr = date != null
                      ? '${date.day}/${date.month}/${date.year}'
                      : '-';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
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
                              builder: (_) => OrderDetailScreen(order: o),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: kPrimary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.receipt_long_outlined,
                                      color: kPrimary,
                                      size: 23,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'PEDIDO',
                                          style: TextStyle(
                                            color: kPrimary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          o['order_number']?.toString() ??
                                              'Pedido',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: kNavy,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _statusColor(
                                        status,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _statusLabel(status),
                                      style: TextStyle(
                                        color: _statusColor(status),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(
                                  height: 1,
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Fecha',
                                          style: TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateStr,
                                          style: const TextStyle(
                                            color: Color(0xFF334155),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 6,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'Total',
                                          style: TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formatCurrency(total),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF111827),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 22,
                                  ),
                                ],
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
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'No tienes pedidos aún',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tus compras y órdenes aparecerán aquí.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
