import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_helpers.dart';
import 'order_detail_screen.dart';
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

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client
          .from('orders')
          .select('*')
          .eq('client_id', widget.clientId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _orders = response as List;
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
          ? LoadErrorState(
              error: _error,
              onRetry: _loadOrders,
              genericTitle: 'Error al cargar pedidos',
              genericMessage: 'No pudimos cargar tus pedidos por el momento.',
            )
          : _orders.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: kPrimary,
              onRefresh: _loadOrders,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _orders.length,
                itemBuilder: (context, i) {
                  final o = _orders[i];
                  final total = (o['total'] as num?)?.toDouble() ?? 0.0;
                  final date = DateTime.tryParse(
                    o['created_at'] ?? '',
                  )?.toLocal();
                  final dateStr = date != null
                      ? '${date.day}/${date.month}/${date.year}'
                      : '-';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderDetailScreen(order: o),
                          ),
                        );
                      },
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              o['order_number'] ?? 'Pedido',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: kNavy,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                o['status'],
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _statusLabel(o['status'] ?? ''),
                              style: TextStyle(
                                color: _statusColor(o['status'] ?? ''),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text(
                            'Fecha: $dateStr',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total: ${formatCurrency(total)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      leading: CircleAvatar(
                        backgroundColor: kPrimary.withValues(alpha: 0.08),
                        child: const Icon(Icons.receipt_long, color: kPrimary),
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
