import 'package:flutter/material.dart';
import '../../models/service_ticket.dart';
import '../../services/ticket_service.dart';
import '../../services/auth_identity_service.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/service_ticket_card_presentation.dart';
import '../profile/maintenance_screen.dart';
import 'ticket_detail_screen.dart';
import '../home/widgets/staggered_fade_slide.dart';
import '../home/home_screen.dart';
import '../../widgets/load_error_state.dart';
import '../../widgets/standard_section_header.dart';

const _kPrimary = Color(0xFF024C8B);

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
    ('assigned', 'Asignados'),
    ('in_progress', 'En progreso'),
    ('resolved', 'Servicio realizado'),
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

  Future<void> _load({bool showSpinner = true}) async {
    if (!mounted) return;
    setState(() {
      if (showSpinner) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final results = await Future.wait([
        TicketService.getMyTickets().timeout(const Duration(seconds: 30)),
        if (showSpinner) Future.delayed(const Duration(seconds: 2)),
      ]);
      final data = results[0] as List<ServiceTicket>;
      if (mounted) {
        setState(() {
          _tickets = data;
          _loading = false;
          _error = null;
        });
        for (final ticket in data) {
          TicketService.markMessagesAsDelivered(ticket.id);
        }
      }
    } catch (e) {
      debugPrint('TicketsListScreen load failed: ${e.runtimeType}: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCreateService() async {
    try {
      final clientId = await AuthIdentityService.requireLinkedClientId();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MaintenanceScreen(clientId: clientId),
        ),
      );
      if (mounted) {
        _load(showSpinner: false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al abrir solicitud: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<ServiceTicket> get _filtered {
    if (_filterStatus == 'all') return _tickets;
    return _tickets
        .where((t) => t.status.toLowerCase() == _filterStatus)
        .toList();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return const Color(0xFF3B82F6);
      case 'assigned':
        return const Color(0xFF0284C7);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'resolved':
        return const Color(0xFF16A34A);
      case 'closed':
        return const Color(0xFF64748B);
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
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
      backgroundColor: const Color(0xFFF7F9FC),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateService,
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
      body: Column(
        children: [
          StandardSectionHeader(
            title: 'Servicios',
            subtitle: !_loading && _error == null
                ? '${_tickets.length} servicio${_tickets.length != 1 ? 's' : ''} registrado${_tickets.length != 1 ? 's' : ''}'
                : null,
            backgroundColor: _kPrimary,
            onBack: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                HomeScreen.showTab(0);
              }
            },
          ),
          ColoredBox(
            color: _kPrimary,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.white,
              indicatorWeight: 2.5,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              tabs: _statusFilters.map((f) => Tab(text: f.$2)).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kPrimary),
                  )
                : RefreshIndicator(
                    color: _kPrimary,
                    backgroundColor: Colors.white,
                    displacement: 42,
                    triggerMode: RefreshIndicatorTriggerMode.onEdge,
                    onRefresh: () => _load(showSpinner: false),
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
                              physics: UiHelpers.refreshScrollPhysics,
                              child: _buildError(),
                            )
                          : _filtered.isEmpty
                          ? SingleChildScrollView(
                              key: const ValueKey('empty'),
                              physics: UiHelpers.refreshScrollPhysics,
                              child: SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.6,
                                child: _buildEmpty(),
                              ),
                            )
                          : ListView.builder(
                              key: ValueKey('list-$_filterStatus'),
                              physics: UiHelpers.refreshScrollPhysics,
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                80,
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
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.build_circle_outlined,
            size: 56,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 14),
          const Text(
            'Sin servicios en este estado',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Tus reportes y solicitudes de servicio aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _openCreateService,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            child: const Text(
              'Solicitar Servicio',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildError() => LoadErrorState(
    error: _error,
    onRetry: _load,
    genericTitle: 'Error al cargar servicios',
    genericMessage: 'No pudimos obtener tus servicios por el momento.',
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
    final title = serviceTicketCardTitle(ticket);
    final preview = serviceTicketCardPreview(ticket);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
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
                builder: (_) => TicketDetailScreen(ticketId: ticket.id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                        color: Color(0xFF024C8B),
                        fontSize: 13.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        ticket.statusLabel,
                        style: TextStyle(
                          color: color,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                    color: Color(0xFF0F172A),
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    preview,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
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
                      'Urgencia: ${ticket.priorityLabel}',
                      priorityColor,
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(ticket.createdAt),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
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
    final local = d.toLocal();
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
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
