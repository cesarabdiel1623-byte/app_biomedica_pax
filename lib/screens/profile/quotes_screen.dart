import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_identity_service.dart';
import '../../utils/ui_helpers.dart';
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

  Future<void> _loadQuotes({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final effectiveClientId =
          await AuthIdentityService.getEffectiveClientId() ?? widget.clientId;

      final quotesFuture = Supabase.instance.client
          .from('quotes')
          .select('*')
          .eq('client_id', effectiveClientId)
          .isFilter('service_ticket_id', null)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 30));

      final quoteRequestsFuture = userId != null
          ? Supabase.instance.client
                .from('quote_requests')
                .select('*')
                .eq('profile_id', userId)
                .order('created_at', ascending: false)
                .timeout(const Duration(seconds: 30))
          : Future.value(<dynamic>[]);

      final results = await Future.wait([
        quotesFuture,
        quoteRequestsFuture,
        if (showSpinner) Future.delayed(const Duration(seconds: 2)),
      ]);

      final quotesResponse = results[0] as List;
      final quoteRequestsResponse = results[1] as List;

      final combined = <Map<String, dynamic>>[
        ...quotesResponse.map(
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
          ? RefreshIndicator(
              color: kPrimary,
              backgroundColor: Colors.white,
              displacement: 42,
              triggerMode: RefreshIndicatorTriggerMode.onEdge,
              onRefresh: () => _loadQuotes(showSpinner: false),
              child: ListView(
                physics: UiHelpers.refreshScrollPhysics,
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height - 200,
                    child: LoadErrorState(
                      error: _error,
                      onRetry: _loadQuotes,
                      genericTitle: 'Error al cargar cotizaciones',
                      genericMessage:
                          'No pudimos cargar tus cotizaciones por el momento.',
                    ),
                  ),
                ],
              ),
            )
          : _quotes.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: kPrimary,
              backgroundColor: Colors.white,
              displacement: 42,
              triggerMode: RefreshIndicatorTriggerMode.onEdge,
              onRefresh: () => _loadQuotes(showSpinner: false),
              child: ListView.builder(
                physics: UiHelpers.refreshScrollPhysics,
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
                                      Icons.request_quote_outlined,
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
                                        Text(
                                          isQuoteRequest
                                              ? 'SOLICITUD'
                                              : 'COTIZACIÓN',
                                          style: const TextStyle(
                                            color: kPrimary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          q['_display_number'] as String? ??
                                              'Cotización',
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
                                        effectiveStatus,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _statusLabel(effectiveStatus),
                                      style: TextStyle(
                                        color: _statusColor(effectiveStatus),
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
                                        Text(
                                          total != null
                                              ? 'Importe'
                                              : 'Seguimiento',
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          total != null
                                              ? formatCurrency(total)
                                              : 'En proceso',
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
