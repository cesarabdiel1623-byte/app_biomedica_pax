import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/product_service.dart';
import '../../services/cart_service.dart';
import '../../services/review_service.dart';
import '../../services/tracking_service.dart';
import '../../models/product.dart';
import '../../models/tracking_info.dart';
import '../../utils/ui_helpers.dart';
import '../product/write_review_screen.dart';
import 'profile_helpers.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  List<dynamic> _items = [];
  Map<String, ProductReview> _reviewsByProductId = {};
  OrderShipment? _shipment;
  bool _expandedEvents = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final orderId = widget.order['id'] as String;
      final response = await Supabase.instance.client
          .from('order_items')
          .select(
            '*, products(brand, product_media(${ProductService.publicMediaColumns}))',
          )
          .eq('order_id', orderId);

      final clientReviews = await ReviewService.getClientReviews();
      final shipment = await TrackingService.getShipmentForOrder(orderId);

      if (mounted) {
        setState(() {
          _items = response as List;
          _reviewsByProductId = {for (var r in clientReviews) r.productId: r};
          _shipment = shipment;
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

  Widget _buildOrderPhases(String status) {
    if (status == 'canceled') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kRed.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel, color: kRed, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Pedido Cancelado',
              style: TextStyle(
                color: kRed,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    int currentStep = 0;
    final shippingStatus = _shipment?.shippingStatus.toLowerCase();

    if (shippingStatus != null) {
      if (shippingStatus == 'pending' || shippingStatus == 'label_created') {
        currentStep = 0;
      } else if (shippingStatus == 'ready_to_ship' ||
          shippingStatus == 'picked_up' ||
          shippingStatus == 'in_transit' ||
          shippingStatus == 'out_for_delivery') {
        currentStep = 1;
      } else if (shippingStatus == 'delivered') {
        currentStep = 2;
      }
    } else {
      if (status == 'shipped') {
        currentStep = 1;
      } else if (status == 'delivered') {
        currentStep = 2;
      }
    }

    final steps = [
      {
        'label': _shipment != null ? 'Guía lista' : 'En bodega',
        'desc': _shipment != null ? _shipment!.statusLabel : 'Preparando envío',
      },
      {'label': 'En proceso', 'desc': 'En camino'},
      {'label': 'Entregado', 'desc': '¡Entregado!'},
    ];

    final hasTrackingInfo =
        _shipment != null &&
        (_shipment!.trackingNumber != null || _shipment!.carrier != null);
    final events = _shipment?.events ?? [];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Seguimiento del envío',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: kNavy,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_shipment != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _shipment!.statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _shipment!.statusLabel,
                    style: TextStyle(
                      color: _shipment!.statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          Stack(
            alignment: Alignment.center,
            children: [
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
                          color: kGreen,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  },
                ),
              ),
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
                      color: isActive
                          ? Colors.white
                          : (isCompleted ? kGreen : Colors.white),
                      border: Border.all(
                        color: isCompleted ? kGreen : Colors.grey.shade300,
                        width: isActive ? 6 : 2,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: kGreen.withValues(alpha: 0.3),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
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
                        : (index == steps.length - 1
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.center),
                    children: [
                      Text(
                        steps[index]['label']!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isCompleted
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCompleted ? kNavy : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        steps[index]['desc']!,
                        style: TextStyle(
                          fontSize: 9,
                          color: isActive ? kGreen : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),

          if (hasTrackingInfo) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    color: kPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_shipment!.carrierDisplayName}${_shipment!.serviceName != null ? ' - ${_shipment!.serviceName}' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kNavy,
                          fontSize: 13,
                        ),
                      ),
                      if (_shipment!.trackingNumber != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Guía: ${_shipment!.trackingNumber}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text: _shipment!.trackingNumber!,
                                  ),
                                );
                                UiHelpers.showFloatingSuccessToast(
                                  context,
                                  '¡Número de guía copiado!',
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: kPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_shipment!.estimatedDelivery != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Entrega estimada: ${_shipment!.estimatedDelivery!.day}/${_shipment!.estimatedDelivery!.month}/${_shipment!.estimatedDelivery!.year}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: kGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_shipment!.trackingUrl != null &&
                _shipment!.trackingUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = _shipment!.trackingUrl;
                    if (url != null && url.isNotEmpty) {
                      final uri = Uri.tryParse(url);
                      if (uri != null) {
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {
                          if (context.mounted) {
                            UiHelpers.showFloatingSuccessToast(
                              context,
                              'Enlace de rastreo: $url',
                            );
                          }
                        }
                      }
                    }
                  },
                  icon: const Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: kPrimary,
                  ),
                  label: const Text(
                    'Rastrear envío en paquetería',
                    style: TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kPrimary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ],

          if (events.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                setState(() => _expandedEvents = !_expandedEvents);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Historial de eventos (${events.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                    ),
                    Icon(
                      _expandedEvents
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_expandedEvents)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: events.length,
                itemBuilder: (ctx, idx) {
                  final ev = events[idx];
                  final evDate =
                      '${ev.eventAt.day}/${ev.eventAt.month} ${ev.eventAt.hour.toString().padLeft(2, '0')}:${ev.eventAt.minute.toString().padLeft(2, '0')}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.radio_button_checked,
                          size: 14,
                          color: kPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ev.description ?? ev.status,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              if (ev.location != null)
                                Text(
                                  ev.location!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          evDate,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
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
    final dateStr = date != null
        ? '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : '-';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          o['order_number'] ?? 'Detalle de Pedido',
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
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estado del Pedido',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(
                            o['status'] ?? '',
                          ).withValues(alpha: 0.12),
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
                  Text(
                    'Fecha de Creación: $dateStr',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
            _buildOrderPhases(o['status'] ?? ''),
            const SizedBox(height: 4),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            color: kNavy,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Dirección de Envío',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kNavy,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        o['shipping_address'] ??
                            'Entrega e instalación a convenir.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const Divider(height: 24),
                      const Row(
                        children: [
                          Icon(Icons.notes_outlined, color: kNavy, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Notas / Instrucciones',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kNavy,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        o['notes'] != null &&
                                o['notes'].toString().trim().isNotEmpty
                            ? o['notes']
                            : 'Sin instrucciones adicionales.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'PRODUCTOS EN EL PEDIDO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.8,
                ),
              ),
            ),

            _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: kPrimary),
                    ),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error al cargar productos: $_error'),
                    ),
                  )
                : _items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No hay productos vinculados.'),
                    ),
                  )
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
                      final price =
                          (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final subtotalLine =
                          (item['total_line_price'] as num?)?.toDouble() ??
                          (qty * price);

                      final ProductReview? review = p != null
                          ? _reviewsByProductId[p['id']]
                          : null;
                      final bool hasReviewed = review != null;
                      final String productId = p?['id'] as String? ?? '';
                      final bool canReview =
                          o['status'] != 'draft' && o['status'] != 'canceled';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (img != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        img,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 50,
                                          height: 50,
                                          color: Colors.grey.shade100,
                                          child: const Icon(
                                            Icons.broken_image,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.medical_services,
                                        color: kPrimary,
                                        size: 20,
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['product_name_snapshot'] ??
                                              'Producto biomédico',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: kNavy,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Cantidad: $qty x ${formatCurrency(price)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatCurrency(subtotalLine),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kNavy,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20, thickness: 0.5),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                runSpacing: 4,
                                children: [
                                  TextButton.icon(
                                    onPressed: () async {
                                      if (productId.isNotEmpty) {
                                        try {
                                          await CartService.addToCart(
                                            productId,
                                            quantity: 1,
                                          );
                                          if (mounted) {
                                            UiHelpers.showFloatingSuccessToast(
                                              context,
                                              '¡Producto agregado al carrito!',
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            UiHelpers.showFloatingDeleteToast(
                                              context,
                                              'Error al agregar al carrito: $e',
                                            );
                                          }
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.shopping_bag_outlined,
                                      size: 16,
                                      color: kPrimary,
                                    ),
                                    label: const Text(
                                      'Volver a comprar',
                                      style: TextStyle(
                                        color: kPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 30),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  if (canReview &&
                                      productId.isNotEmpty &&
                                      p != null)
                                    hasReviewed
                                        ? GestureDetector(
                                            onTap: () {
                                              final prod = Product.fromJson(
                                                p as Map<String, dynamic>,
                                              );
                                              Navigator.of(context)
                                                  .push(
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          WriteReviewScreen(
                                                            product: prod,
                                                            existingReview:
                                                                review,
                                                          ),
                                                    ),
                                                  )
                                                  .then((_) => _loadItems());
                                            },
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Row(
                                                  children: List.generate(5, (
                                                    starIdx,
                                                  ) {
                                                    return Icon(
                                                      starIdx < review.rating
                                                          ? Icons.star_rounded
                                                          : Icons
                                                                .star_border_rounded,
                                                      color: const Color(
                                                        0xFFFBBF24,
                                                      ),
                                                      size: 16,
                                                    );
                                                  }),
                                                ),
                                                const SizedBox(width: 4),
                                                const Text(
                                                  'Editar opinión',
                                                  style: TextStyle(
                                                    color: kPrimary,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : TextButton.icon(
                                            onPressed: () {
                                              final prod = Product.fromJson(
                                                p as Map<String, dynamic>,
                                              );
                                              Navigator.of(context)
                                                  .push(
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          WriteReviewScreen(
                                                            product: prod,
                                                          ),
                                                    ),
                                                  )
                                                  .then((_) => _loadItems());
                                            },
                                            icon: const Icon(
                                              Icons.star_outline_rounded,
                                              size: 16,
                                              color: kPrimary,
                                            ),
                                            label: const Text(
                                              'Opinar del producto',
                                              style: TextStyle(
                                                color: kPrimary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(0, 30),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resumen de Pago',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kNavy,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _summaryRow('Subtotal', formatCurrency(subtotal)),
                      const SizedBox(height: 6),
                      _summaryRow('IVA (16%)', formatCurrency(tax)),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(),
                      ),
                      _summaryRow(
                        'Total',
                        formatCurrency(total),
                        bold: true,
                        size: 16,
                      ),
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

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    double size = 13,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: size,
            color: bold ? kNavy : Colors.grey.shade600,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: size,
            color: bold ? kPrimary : kNavy,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
