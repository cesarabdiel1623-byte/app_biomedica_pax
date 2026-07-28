import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_identity_service.dart';
import 'profile_helpers.dart';
import 'quote_detail_screen.dart';
import 'quote_request_detail_screen.dart';
import '../../widgets/load_error_state.dart';

class QuotesScreen extends StatefulWidget {
  final String clientId;
  const QuotesScreen({super.key, required this.clientId});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  List<Map<String, dynamic>> _quotes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final effectiveClientId =
          await AuthIdentityService.getEffectiveClientId() ?? widget.clientId;

      final quotesResponse = await Supabase.instance.client
          .from('quotes')
          .select('*')
          .eq('client_id', effectiveClientId)
          .order('created_at', ascending: false);

      List<dynamic> quoteRequestsResponse = [];
      if (userId != null) {
        quoteRequestsResponse = await Supabase.instance.client
            .from('quote_requests')
            .select('*')
            .eq('profile_id', userId)
            .order('created_at', ascending: false);
      }

      final combined = <Map<String, dynamic>>[
        ...(quotesResponse as List).map(
          (quote) => {
            ...(quote as Map<String, dynamic>),
            '_entry_type': 'quote',
            '_display_number': quote['quote_number'] as String? ?? 'Cotización',
            '_display_status': quote['status'] as String? ?? 'draft',
            '_display_total': (quote['total'] as num?)?.toDouble() ?? 0.0,
          },
        ),
        ...quoteRequestsResponse.map(
          (request) => {
            ...(request as Map<String, dynamic>),
            '_entry_type': 'quote_request',
            '_display_number':
                request['request_number'] as String? ??
                'Solicitud de cotización',
            '_display_status': request['status'] as String? ?? 'pending',
            '_display_total': null,
          },
        ),
      ];

      combined.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      if (mounted) {
        setState(() {
          _quotes = combined;
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
      case 'sent':
        return 'Enviado';
      case 'approved':
        return 'Aprobado';
      case 'rejected':
        return 'Rechazado';
      case 'expired':
        return 'Vencido';
      case 'converted':
        return 'Convertido';
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
      case 'approved':
      case 'converted':
        return kGreen;
      case 'sent':
        return const Color(0xFF0284C7);
      case 'draft':
        return Colors.grey;
      case 'rejected':
      case 'expired':
      case 'cancelled':
        return kRed;
      case 'pending':
      case 'reviewing':
        return Colors.orange;
      case 'quoted':
        return const Color(0xFF0284C7);
      case 'closed':
        return kGreen;
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
          'Cotizaciones',
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
              onRetry: _loadQuotes,
              genericTitle: 'Error al cargar cotizaciones',
              genericMessage:
                  'No pudimos cargar tus cotizaciones por el momento.',
            )
          : _quotes.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: kPrimary,
              onRefresh: _loadQuotes,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _quotes.length,
                itemBuilder: (context, i) {
                  final q = _quotes[i];
                  final total = q['_display_total'] as double?;
                  final date = DateTime.tryParse(
                    q['created_at'] ?? '',
                  )?.toLocal();
                  final dateStr = date != null
                      ? '${date.day}/${date.month}/${date.year}'
                      : '-';
                  final isQuoteRequest = q['_entry_type'] == 'quote_request';
                  final effectiveStatus = isQuoteRequest
                      ? (q['_display_status'] as String? ?? 'pending')
                      : getEffectiveStatus(q);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => isQuoteRequest
                                    ? QuoteRequestDetailScreen(request: q)
                                    : QuoteDetailScreen(quote: q),
                              ),
                            )
                            .then((val) {
                              if (val == true) {
                                _loadQuotes();
                              }
                            });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: kPrimary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.request_quote_outlined,
                                color: kPrimary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          q['_display_number'] as String? ??
                                              'Cotización',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: kNavy,
                                            fontSize: 14.5,
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
                                            effectiveStatus,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          _statusLabel(
                                            effectiveStatus,
                                          ).toUpperCase(),
                                          style: TextStyle(
                                            color: _statusColor(
                                              effectiveStatus,
                                            ),
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_outlined,
                                        size: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Fecha: $dateStr',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    total != null
                                        ? 'Importe total: ${formatCurrency(total)}'
                                        : 'Solicitud recibida y en seguimiento',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.grey,
                              size: 22,
                            ),
                          ],
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
            Icons.request_quote_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'Sin cotizaciones',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tus cotizaciones y presupuestos aparecerán aquí.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
