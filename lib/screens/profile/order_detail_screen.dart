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
      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('order_items')
            .select(
              '*, products(brand, product_media(${ProductService.publicMediaColumns}))',
            )
            .eq('order_id', orderId)
            .timeout(const Duration(seconds: 30)),
        ReviewService.getClientReviews().timeout(const Duration(seconds: 30)),
        TrackingService.getShipmentForOrder(
          orderId,
        ).timeout(const Duration(seconds: 30)),
        Future.delayed(const Duration(seconds: 2)),
      ]);

      final response = results[0] as List;
      final clientReviews = results[1] as List<ProductReview>;
      final shipment = results[2] as OrderShipment?;

      if (mounted) {
        setState(() {
          _items = response;
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

  Widget _buildShipmentTracking(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString();
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

    final shipment = _shipment;
    if (shipment == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: _trackingCardDecoration(),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seguimiento del envío',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: kNavy,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Estamos preparando la información de envío.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
      );
    }

    final events = _eventsNewestFirst(shipment.events);
    final lastUpdate =
        (events.isNotEmpty ? events.first.eventAt : null) ??
        shipment.updatedAt ??
        shipment.createdAt;
    final trackingNumber = shipment.trackingNumber?.trim();
    final trackingUrl = shipment.trackingUrl?.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: _trackingCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seguimiento del envío',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            shipment.statusLabel,
            style: TextStyle(
              color: shipment.statusColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (lastUpdate != null) ...[
            const SizedBox(height: 3),
            Text(
              _formatCompactDate(lastUpdate),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            shipmentCompactStatusMessage(shipment.shippingStatus) ??
                'Se registró una actualización del envío.',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 13,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
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
                      _carrierServiceLabel(shipment),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paquetería',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildShipmentProgress(shipment),
          if (trackingNumber != null && trackingNumber.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTrackingNumberRow(trackingNumber),
          ],
          if (trackingUrl != null && trackingUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(trackingUrl);
                  if (uri == null) return;
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {
                    if (context.mounted) {
                      UiHelpers.showFloatingSuccessToast(
                        context,
                        'Enlace de rastreo: $trackingUrl',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 16, color: kPrimary),
                label: const Text(
                  'Rastrear con la paquetería',
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
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration _trackingCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildShipmentProgress(OrderShipment shipment) {
    final currentIndex = _shipmentProgressIndexFromShipment(shipment);
    final events = _eventsNewestFirst(shipment.events);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.alt_route_rounded, size: 18, color: kNavy),
              SizedBox(width: 8),
              Text(
                'Movimientos del envío',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            children: List.generate(kSkyDropXProcesses.length, (index) {
              final stepLabel = kSkyDropXProcesses[index];
              final isCompleted = currentIndex >= index;
              final isCurrent = currentIndex == index;
              final isLast = index == kSkyDropXProcesses.length - 1;

              final matchingEvent = _findEventForStep(events, index);
              final eventDate = matchingEvent != null
                  ? _formatTimelineDate(matchingEvent.eventAt)
                  : null;
              final usefulDescription = matchingEvent != null
                  ? _eventUsefulDescription(matchingEvent)
                  : null;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          if (!isLast)
                            Positioned(
                              top: 14,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: currentIndex > index
                                    ? shipment.statusColor
                                    : Colors.grey.shade200,
                              ),
                            ),
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? shipment.statusColor
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isCompleted
                                    ? shipment.statusColor
                                    : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    stepLabel,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isCompleted
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: isCompleted
                                          ? kNavy
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                                if (eventDate != null)
                                  Text(
                                    eventDate,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isCurrent
                                          ? shipment.statusColor
                                          : Colors.grey.shade600,
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                              ],
                            ),
                            if (usefulDescription != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                usefulDescription,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  height: 1.25,
                                ),
                              ),
                            ],
                            if (matchingEvent != null &&
                                matchingEvent.hasLocation) ...[
                              const SizedBox(height: 3),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    color: kPrimary,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      matchingEvent.location!.trim(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  ShipmentEvent? _findEventForStep(List<ShipmentEvent> events, int stepIndex) {
    for (final event in events) {
      if (shipmentProgressStepIndex(event.status) == stepIndex ||
          shipmentProgressStepIndex(event.description) == stepIndex) {
        return event;
      }
    }
    return null;
  }

  int _shipmentProgressIndexFromShipment(OrderShipment shipment) {
    final current = shipmentProgressStepIndex(shipment.shippingStatus);
    if (current >= 0) return current;

    return shipment.events.fold<int>(-1, (max, event) {
      final index = shipmentProgressStepIndex(event.status);
      return index > max ? index : max;
    });
  }

  String? _eventUsefulDescription(ShipmentEvent event) {
    final description = event.description?.trim();
    if (description == null || description.isEmpty) return null;
    if (shipmentStatusLabel(description) != null) return null;
    if (description.toLowerCase() == event.status.trim().toLowerCase()) {
      return null;
    }
    return description;
  }

  Widget _buildTrackingNumberRow(String trackingNumber) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number_outlined, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guía',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Text(
                  trackingNumber,
                  style: const TextStyle(
                    fontSize: 13,
                    color: kNavy,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar guía',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: trackingNumber));
              UiHelpers.showFloatingSuccessToast(
                context,
                '¡Número de guía copiado!',
              );
            },
            icon: const Icon(Icons.copy_rounded, color: kPrimary, size: 18),
          ),
        ],
      ),
    );
  }

  List<ShipmentEvent> _eventsNewestFirst(List<ShipmentEvent> events) {
    return [...events]..sort((a, b) => b.eventAt.compareTo(a.eventAt));
  }

  String _carrierServiceLabel(OrderShipment shipment) {
    final serviceName = shipment.serviceName?.trim();
    if (serviceName == null || serviceName.isEmpty) {
      return shipment.carrierDisplayName;
    }
    return '${shipment.carrierDisplayName} · $serviceName';
  }

  String _formatTimelineDate(DateTime value) {
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
    final month = months[value.month - 1];
    return '${value.day.toString().padLeft(2, '0')} $month · '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String _formatCompactDate(DateTime value) {
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.day} de ${months[value.month - 1]} · $hour:$minute';
  }

  Widget _detailCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: kPrimary, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: kNavy,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  List<String> _splitDetailLines(dynamic value) {
    final text = value?.toString().replaceAll('\r\n', '\n').trim();
    if (text == null || text.isEmpty) return const [];
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Widget _detailLine(String rawLine) {
    final separatorIndex = rawLine.indexOf(':');
    final hasLabel = separatorIndex > 0 && separatorIndex < 32;
    final label = hasLabel ? rawLine.substring(0, separatorIndex).trim() : null;
    final value = hasLabel
        ? rawLine.substring(separatorIndex + 1).trim()
        : rawLine.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              value.isEmpty ? rawLine : value,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryInfoCard(Map<String, dynamic> order) {
    final addressLines = _splitDetailLines(order['shipping_address']);
    final notes = order['notes']?.toString().trim();
    final hasNotes = notes != null && notes.isNotEmpty;

    return _detailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.local_shipping_outlined, 'Dirección de Envío'),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: addressLines.isEmpty
                ? const Text(
                    'Entrega e instalación a convenir.',
                    style: TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 13,
                      height: 1.25,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: addressLines.map(_detailLine).toList(),
                  ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kNavy.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notes_outlined, color: kNavy, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Notas / Instrucciones',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  hasNotes ? notes : 'Sin instrucciones adicionales.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1F2937),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummaryCard(OrderPaymentBreakdown paymentBreakdown) {
    return _detailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.receipt_long_outlined, 'Resumen de Pago'),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _summaryRow(
                  'Productos',
                  formatCurrency(paymentBreakdown.products),
                ),
                const SizedBox(height: 10),
                _summaryRow(
                  'Envío',
                  paymentBreakdown.shipping == 0
                      ? 'Gratis'
                      : formatCurrency(paymentBreakdown.shipping),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                ),
                _summaryRow(
                  'Total',
                  formatCurrency(paymentBreakdown.total),
                  bold: true,
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Los precios incluyen IVA.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
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
    final paymentBreakdown = buildIncludedVatOrderPaymentBreakdown(
      subtotal: subtotal,
      total: total,
      storedTax: tax,
      customerShippingAmount: (o['customer_shipping_amount'] as num?)
          ?.toDouble(),
    );
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
                  Text(
                    o['order_number'] ?? 'Pedido',
                    style: const TextStyle(
                      fontSize: 18,
                      color: kNavy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.event_note_outlined,
                        size: 15,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Realizado el $dateStr',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildPaymentStatusBanner(o),
                ],
              ),
            ),
            _buildShipmentTracking(o),
            const SizedBox(height: 8),
            _buildDeliveryInfoCard(o),
            const SizedBox(height: 16),

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
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0xFFE8EEF4)),
                        ),
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (img != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        img,
                                        width: 62,
                                        height: 62,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 62,
                                          height: 62,
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
                                      width: 62,
                                      height: 62,
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
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
                                            fontWeight: FontWeight.w800,
                                            color: kNavy,
                                            fontSize: 14,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Cantidad: $qty x ${formatCurrency(price)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Text(
                                              'Total producto',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade500,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              formatCurrency(subtotalLine),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: kNavy,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
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

            _buildPaymentSummaryCard(paymentBreakdown),
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
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: size,
              color: bold ? kNavy : Colors.grey.shade600,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 12),
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

  Widget _buildPaymentStatusBanner(Map<String, dynamic> order) {
    final status = order['payment_status']?.toString();
    final color = _paymentStatusColor(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(_paymentStatusIcon(status), color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _paymentStatusLabel(status),
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _paymentStatusLabel(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'approved':
        return 'Pago aprobado';
      case 'pending':
      case 'created':
        return 'Pago pendiente';
      case 'rejected':
      case 'error':
        return 'Pago rechazado';
      case 'refunded':
        return 'Reembolsado';
      case 'cancelled':
      case 'canceled':
        return 'Pago cancelado';
      case 'charged_back':
        return 'Contracargo';
      default:
        return 'Estado de pago por confirmar';
    }
  }

  Color _paymentStatusColor(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'approved':
        return kGreen;
      case 'pending':
      case 'created':
        return kOrange;
      case 'rejected':
      case 'error':
      case 'cancelled':
      case 'canceled':
      case 'charged_back':
        return kRed;
      case 'refunded':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _paymentStatusIcon(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'approved':
        return Icons.check_circle_outline;
      case 'rejected':
      case 'error':
      case 'cancelled':
      case 'canceled':
      case 'charged_back':
        return Icons.error_outline;
      case 'refunded':
        return Icons.undo_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }
}
