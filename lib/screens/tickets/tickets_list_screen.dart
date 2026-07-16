import 'package:flutter/material.dart';
import '../../models/service_ticket.dart';
import '../../services/ticket_service.dart';
import 'ticket_detail_screen.dart';
import '../home/widgets/staggered_fade_slide.dart';
import '../home/home_screen.dart';
import '../../widgets/load_error_state.dart';

const _kPrimary = Color(0xFF0D9488);

class TicketsListScreen extends StatefulWidget {
  const TicketsListScreen({super.key});
  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends State<TicketsListScreen>
    with SingleTickerProviderStateMixin {
  List<ServiceTicket> _tickets = [];
  bool _loading = true;
  String? _error;
  String _filterStatus = 'all';
  late final TabController _tabController;

  final _statusFilters = const [
    ('all', 'Todos'),
    ('open', 'Abiertos'),
    ('in_progress', 'En Progreso'),
    ('resolved', 'Resueltos'),
    ('closed', 'Cerrados'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusFilters.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _filterStatus = _statusFilters[_tabController.index].$1);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      if (_tickets.isEmpty) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final data = await TicketService.getMyTickets();
      if (mounted) {
        setState(() {
          _tickets = data;
          _loading = false;
        });
        for (final ticket in data) {
          TicketService.markMessagesAsDelivered(ticket.id);
        }
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

  List<ServiceTicket> get _filtered {
    if (_filterStatus == 'all') return _tickets;
    return _tickets.where((t) => t.status == _filterStatus).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return const Color(0xFF3B82F6);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'resolved':
        return const Color(0xFF16A34A);
      case 'closed':
        return Colors.grey;
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical':
        return const Color(0xFF7C3AED);
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Container(
            color: _kPrimary,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            } else {
                              HomeScreen.showTab(0); // Regresa al inicio
                            }
                          },
                        ),
                        const Icon(
                          Icons.support_agent,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Mis Tickets de Servicio',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              if (!_loading && _error == null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  "${_tickets.length} ticket${_tickets.length != 1 ? 's' : ''} encontrado${_tickets.length != 1 ? 's' : ''}",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicatorColor: Colors.white,
                      indicatorWeight: 2.5,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white.withValues(
                        alpha: 0.55,
                      ),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      tabAlignment: TabAlignment.start,
                      dividerColor:
                          Colors.transparent, // Quita la línea inferior
                      tabs: _statusFilters.map((f) => Tab(text: f.$2)).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kPrimary),
                  )
                : RefreshIndicator(
                    color: _kPrimary,
                    onRefresh: _load,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final isList = child.key.toString().contains('list');
                        if (isList) {
                          final offsetAnim = Tween<Offset>(
                            begin: const Offset(0.08, 0.0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offsetAnim,
                              child: child,
                            ),
                          );
                        }
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: _error != null
                          ? SingleChildScrollView(
                              key: const ValueKey('error'),
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: _buildError(),
                            )
                          : _filtered.isEmpty
                          ? SingleChildScrollView(
                              key: const ValueKey('empty'),
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.6,
                                child: _buildEmpty(),
                              ),
                            )
                          : ListView.builder(
                              key: ValueKey('list-$_filterStatus'),
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                20,
                              ),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) => StaggeredFadeSlide(
                                index: i,
                                child: _TicketCard(
                                  ticket: _filtered[i],
                                  color: _statusColor(_filtered[i].status),
                                  priorityColor: _priorityColor(
                                    _filtered[i].priority,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.assignment_outlined, size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        const Text(
          'Sin tickets en este estado',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Tus reportes de servicio aparecerán aquí.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _buildError() => LoadErrorState(
    error: _error,
    onRetry: _load,
    genericTitle: 'Error al cargar tickets',
    genericMessage: 'No pudimos obtener tus tickets por el momento.',
  );
}

class _TicketCard extends StatelessWidget {
  final ServiceTicket ticket;
  final Color color;
  final Color priorityColor;

  const _TicketCard({
    required this.ticket,
    required this.color,
    required this.priorityColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TicketDetailScreen(ticketId: ticket.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    ticket.ticketNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F),
                      fontSize: 13.5,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ticket.statusLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Badge circular translúcido de prioridad
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: priorityColor.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          ticket.priority == 'critical'
                              ? Icons.gavel_rounded
                              : ticket.priority == 'high'
                              ? Icons.warning_amber_rounded
                              : ticket.priority == 'medium'
                              ? Icons.flag_rounded
                              : Icons.info_outline_rounded,
                          color: priorityColor,
                          size: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ticket.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (ticket.description != null && ticket.description!.isNotEmpty)
                Text(
                  ticket.description!,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metaChip(
                    ticket.priority == 'critical'
                        ? Icons.gavel_rounded
                        : ticket.priority == 'high'
                        ? Icons.warning_amber_rounded
                        : ticket.priority == 'medium'
                        ? Icons.flag_rounded
                        : Icons.info_outline_rounded,
                    'Prioridad: ${ticket.priorityLabel}',
                    priorityColor,
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(ticket.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  String _formatDate(DateTime d) {
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
