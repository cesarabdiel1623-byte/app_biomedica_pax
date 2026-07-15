import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_helpers.dart';
import 'quote_detail_screen.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Cotizaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: kPrimary, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _error != null
              ? Center(child: Text('Error: $_error'))
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
                          final total = (q['total'] as num?)?.toDouble() ?? 0.0;
                          final date = DateTime.tryParse(q['created_at'] ?? '')?.toLocal();
                          final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '-';
                          final effectiveStatus = getEffectiveStatus(q);

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
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => QuoteDetailScreen(quote: q)),
                                ).then((val) {
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
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  q['quote_number'] ?? 'Cotización',
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
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: _statusColor(effectiveStatus).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  _statusLabel(effectiveStatus).toUpperCase(),
                                                  style: TextStyle(
                                                    color: _statusColor(effectiveStatus),
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
                                            'Importe total: ${formatCurrency(total)}',
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
          Icon(Icons.request_quote_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('Sin cotizaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          Text('Tus cotizaciones y presupuestos aparecerán aquí.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}
