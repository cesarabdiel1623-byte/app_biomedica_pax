import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_helpers.dart';
import 'quotes_screen.dart';
import 'quote_detail_screen.dart';
import 'quote_request_detail_screen.dart';
import 'orders_screen.dart';
import 'order_detail_screen.dart';
import '../product/all_questions_screen.dart';
import '../product/single_question_screen.dart';
import '../tickets/ticket_detail_screen.dart';
import '../tickets/tickets_list_screen.dart';
import '../../services/auth_identity_service.dart';
import '../../services/notification_service.dart';
import '../../services/product_service.dart';
import '../../services/question_service.dart';
import '../../utils/notification_presentation.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _whatsapp = true;
  bool _email = true;
  bool _orderUpdates = true;
  bool _security = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _whatsapp = prefs.getBool('notif_whatsapp') ?? true;
        _email = prefs.getBool('notif_email') ?? true;
        _orderUpdates = prefs.getBool('notif_orders') ?? true;
        _security = prefs.getBool('notif_security') ?? true;
        _loading = false;
      });
    }
  }

  Future<void> _savePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Notificaciones',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const _NotificationsLoadingBody()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                SwitchListTile(
                  title: const Text(
                    'Alertas por WhatsApp',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Recibe actualizaciones de tus tickets y cotizaciones vía WhatsApp.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _whatsapp,
                  activeThumbColor: kPrimary,
                  onChanged: (v) {
                    setState(() => _whatsapp = v);
                    _savePref('notif_whatsapp', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                    'Notificaciones por Correo',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Recibe presupuestos y comprobantes de compra en tu email.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _email,
                  activeThumbColor: kPrimary,
                  onChanged: (v) {
                    setState(() => _email = v);
                    _savePref('notif_email', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                    'Seguimiento de Pedidos',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Notificaciones en tiempo real del estado de tus órdenes.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _orderUpdates,
                  activeThumbColor: kPrimary,
                  onChanged: (v) {
                    setState(() => _orderUpdates = v);
                    _savePref('notif_orders', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                    'Seguridad y Acceso',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Notificaciones sobre inicios de sesión y cambios de contraseña.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _security,
                  activeThumbColor: kPrimary,
                  onChanged: (v) {
                    setState(() => _security = v);
                    _savePref('notif_security', v);
                  },
                ),
              ],
            ),
    );
  }
}

class NotificationsListScreen extends StatefulWidget {
  const NotificationsListScreen({super.key, this.initialNotificationId});

  final String? initialNotificationId;

  @override
  State<NotificationsListScreen> createState() =>
      _NotificationsListScreenState();
}

class _NotificationDestinationLoadingScreen extends StatelessWidget {
  const _NotificationDestinationLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: const _NotificationsLoadingBody(),
    );
  }
}

class _NotificationsLoadingBody extends StatelessWidget {
  const _NotificationsLoadingBody();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(child: CircularProgressIndicator(color: kPrimary)),
    );
  }
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  bool _initialNotificationHandled = false;

  Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> source) {
    return source.map((key, value) {
      final normalizedValue = value is Map
          ? _stringKeyedMap(value)
          : value is List
          ? value
                .map((item) => item is Map ? _stringKeyedMap(item) : item)
                .toList()
          : value;
      return MapEntry(key.toString(), normalizedValue);
    });
  }

  List<Map<String, dynamic>> _stringKeyedNotificationList(dynamic response) {
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((item) => _stringKeyedMap(item))
        .toList();
  }

  Future<List<String>> _notificationOwnerIds() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');
    final ids = <String>{userId};
    try {
      final clientId = await AuthIdentityService.getEffectiveClientId();
      if (clientId != null && clientId.trim().isNotEmpty) {
        ids.add(clientId.trim());
      }
    } catch (_) {
      // Some historical notification rows are keyed by auth user id; keep that
      // path working even if the business client relation cannot be resolved.
    }
    return ids.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications({
    bool forceLoading = false,
    bool showSpinner = true,
  }) async {
    final shouldShowLoading =
        showSpinner && (forceLoading || _notifications.isEmpty);
    if (mounted) {
      setState(() {
        _loading = shouldShowLoading;
        _error = null;
      });
    }
    try {
      final ownerIds = await _notificationOwnerIds();

      final results = await Future.wait([
        Supabase.instance.client
            .from('notifications')
            .select('*')
            .inFilter('user_id', ownerIds)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 30)),
        if (shouldShowLoading) Future.delayed(const Duration(seconds: 2)),
      ]);

      if (mounted) {
        setState(() {
          _notifications = _stringKeyedNotificationList(results[0]);
          _loading = false;
          _error = null;
        });
        _openInitialNotificationIfNeeded();
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

  Future<void> _refreshNotifications() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
    });
    try {
      await _loadNotifications(showSpinner: false);
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  void _openInitialNotificationIfNeeded() {
    final id = widget.initialNotificationId;
    if (_initialNotificationHandled || id == null || id.isEmpty) return;
    final index = _notifications.indexWhere(
      (item) => item['id']?.toString() == id,
    );
    if (index == -1) return;
    _initialNotificationHandled = true;
    final notification = Map<String, dynamic>.from(_notifications[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleNotificationTap(notification);
    });
  }

  Future<void> _markAllAsRead() async {
    final unreadCount = _notifications
        .where((item) => item['is_read'] == false)
        .length;
    if (unreadCount == 0) return;
    setState(() {
      _notifications = _notifications
          .map((item) => {...item, 'is_read': true})
          .toList();
    });
    NotificationService.instance.unreadCountNotifier.value = 0;
    try {
      final ownerIds = await _notificationOwnerIds();
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .inFilter('user_id', ownerIds)
          .eq('is_read', false);
    } catch (_) {
      await _loadNotifications();
    }
  }

  Future<bool> _markAsRead(String id) async {
    try {
      final ownerIds = await _notificationOwnerIds();
      final updated = await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id)
          .inFilter('user_id', ownerIds)
          .select('id')
          .limit(1)
          .maybeSingle();
      return updated != null;
    } catch (error) {
      debugPrint('No se pudo marcar la notificación como leída: $error');
      return false;
    }
  }

  ({IconData icon, Color color, Color bg}) _notifStyle(
    String title,
    String body, {
    bool isServiceNotification = false,
  }) {
    final t = title.toLowerCase();
    final b = body.toLowerCase();
    if (isServiceNotification ||
        t.contains('ticket') ||
        b.contains('tck-') ||
        t.contains('soporte')) {
      return (
        icon: Icons.build_circle_rounded,
        color: const Color(0xFF024C8B),
        bg: const Color(0xFFEBF3FA),
      );
    } else if (t.contains('cotiza') ||
        b.contains('cot-') ||
        b.contains('rq-')) {
      return (
        icon: Icons.request_quote_rounded,
        color: const Color(0xFF024C8B),
        bg: const Color(0xFFEBF3FA),
      );
    } else if (t.contains('pedido') ||
        t.contains('orden') ||
        b.contains('ord-')) {
      return (
        icon: Icons.local_shipping_rounded,
        color: const Color(0xFF7C3AED),
        bg: const Color(0xFFF3EEFF),
      );
    } else if (t.contains('pago') || t.contains('factura')) {
      return (
        icon: Icons.payments_rounded,
        color: const Color(0xFF16A34A),
        bg: const Color(0xFFECFDF5),
      );
    } else if (t.contains('bienvenid')) {
      return (
        icon: Icons.celebration_rounded,
        color: const Color(0xFFF59E0B),
        bg: const Color(0xFFFFFBEB),
      );
    } else if (t.contains('pregunta') || b.contains('pregunta')) {
      return (
        icon: Icons.question_answer_rounded,
        color: const Color(0xFF21AF97),
        bg: const Color(0xFFE6F7F5),
      );
    } else {
      return (
        icon: Icons.notifications_rounded,
        color: const Color(0xFF64748B),
        bg: const Color(0xFFF1F5F9),
      );
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notification) async {
    final String id = notification['id']?.toString() ?? '';
    final bool isRead = notification['is_read'] as bool? ?? false;
    final presentation = notificationPresentation(notification);
    final String body = presentation.body;
    final String title = presentation.title;

    if (!isRead && id.isNotEmpty) {
      if (mounted) {
        setState(() {
          final idx = _notifications.indexWhere(
            (n) => n['id']?.toString() == id,
          );
          if (idx != -1) {
            _notifications[idx] = {..._notifications[idx], 'is_read': true};
          }
        });
      }
      final currentCount =
          NotificationService.instance.unreadCountNotifier.value;
      if (currentCount > 0) {
        NotificationService.instance.unreadCountNotifier.value =
            currentCount - 1;
      }
      final persisted = await _markAsRead(id);
      if (!persisted && mounted) {
        await _loadNotifications(showSpinner: false);
      }
    }

    await Future<void>.delayed(Duration.zero);

    final bool isQuestionNotif =
        title.toLowerCase().contains('pregunta') ||
        body.toLowerCase().contains('pregunta');
    final combinedText = '$title $body';
    final notificationType =
        _notificationValue(notification, const [
          'type',
          'notification_type',
          'entity_type',
          'target_type',
        ])?.toLowerCase() ??
        '';
    final resourceType =
        _notificationValue(notification, const [
          'resource_type',
          'resourceType',
        ])?.toLowerCase() ??
        '';
    final isTicketNotification =
        presentation.isServiceNotification ||
        resourceType == 'service_ticket' ||
        title.toLowerCase().contains('ticket') ||
        body.toLowerCase().contains('ticket') ||
        combinedText.toLowerCase().contains('tck-') ||
        notificationType.contains('ticket');

    if (isQuestionNotif) {
      final nameMatch = RegExp(r'sobre\s+"([^"]+)"').firstMatch(body);
      final answerMatch = RegExp(r'respondida:\s+"([^"]+)"').firstMatch(body);

      final String? productName =
          _notificationValue(notification, const [
            'product_name',
            'productName',
          ]) ??
          nameMatch?.group(1);
      final String? answerText = answerMatch?.group(1);

      if (productName != null) {
        await _navigateToProductQuestions(productName, answerHint: answerText);
        return;
      }
    }

    final ticketReference =
        _notificationValue(notification, const [
          'ticket_id',
          'ticketId',
          'service_ticket_id',
          'serviceTicketId',
        ]) ??
        (resourceType == 'service_ticket'
            ? _notificationValue(notification, const [
                'resource_id',
                'resourceId',
              ])
            : null);
    final targetReference = isTicketNotification
        ? _notificationValue(notification, const [
            'target_id',
            'targetId',
            'entity_id',
            'entityId',
            'reference_id',
            'referenceId',
          ])
        : null;
    final directTicketReference = ticketReference ?? targetReference;
    final ticketNumber =
        _notificationValue(notification, const [
          'ticket_number',
          'ticketNumber',
        ]) ??
        (directTicketReference?.toUpperCase().startsWith('TCK-') == true
            ? directTicketReference
            : null) ??
        RegExp(
          r'TCK-\d{8}-[A-Za-z0-9]+',
          caseSensitive: false,
        ).firstMatch(combinedText)?.group(0);
    final ticketId = _isUuid(directTicketReference)
        ? directTicketReference!.trim()
        : null;

    if (ticketId != null) {
      await _navigateToTicket(ticketId: ticketId);
      return;
    }
    if (ticketNumber != null) {
      await _navigateToTicket(ticketNumber: ticketNumber.toUpperCase());
      return;
    }

    if (isTicketNotification) {
      await _navigateToTicketsList();
      return;
    }

    final isOrderNotification =
        title.toLowerCase().contains('pedido') ||
        title.toLowerCase().contains('orden') ||
        title.toLowerCase().contains('pago') ||
        title.toLowerCase().contains('envío') ||
        title.toLowerCase().contains('envio') ||
        body.toLowerCase().contains('pedido') ||
        body.toLowerCase().contains('orden') ||
        combinedText.toLowerCase().contains('ord-') ||
        notificationType.contains('order') ||
        notificationType.contains('payment') ||
        notificationType.contains('shipment');
    final orderReference =
        _notificationValue(notification, const [
          'order_id',
          'orderId',
          'order_number',
          'orderNumber',
        ]) ??
        (isOrderNotification
            ? _notificationValue(notification, const [
                'target_id',
                'targetId',
                'entity_id',
                'entityId',
                'reference_id',
                'referenceId',
              ])
            : null) ??
        RegExp(
          r'ORD-\d{8}-[A-Za-z0-9]+',
          caseSensitive: false,
        ).firstMatch(combinedText)?.group(0);

    if (orderReference != null) {
      await _navigateToOrder(orderReference);
      return;
    }
    if (isOrderNotification) {
      await _navigateToOrdersList();
      return;
    }

    final quoteReference =
        _notificationValue(notification, const [
          'quote_id',
          'quoteId',
          'quote_request_id',
          'quoteRequestId',
          'request_id',
          'requestId',
          'quote_number',
          'request_number',
          'reference_number',
        ]) ??
        RegExp(
          r'(?:COT|RQ)-\d{8}-[A-Za-z0-9]+',
          caseSensitive: false,
        ).firstMatch(body)?.group(0);
    if (quoteReference != null) {
      await _navigateToQuote(quoteReference.toUpperCase());
      return;
    }

    if (title.toLowerCase().contains('cotiza') ||
        body.toLowerCase().contains('cotiza')) {
      await _navigateToQuotesList();
      return;
    }

    if (mounted && !isRead) {
      UiHelpers.showFloatingSuccessToast(
        context,
        'Notificación marcada como leída.',
        bottomMargin: 12,
      );
    }
  }

  bool _isUuid(String? value) {
    if (value == null) return false;
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  Future<void> _navigateToTicket({
    String? ticketId,
    String? ticketNumber,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TicketDetailScreen(ticketId: ticketId, ticketNumber: ticketNumber),
      ),
    );
  }

  Future<void> _navigateToTicketsList() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TicketsListScreen()));
  }

  Future<void> _navigateToOrder(String reference) async {
    if (!mounted) return;
    final loadingRoute = _showDestinationLoading();
    try {
      final normalizedReference = reference.trim();
      final query = Supabase.instance.client.from('orders').select('*');
      final Map<String, dynamic>? order = _isUuid(normalizedReference)
          ? await query.eq('id', normalizedReference).limit(1).maybeSingle()
          : await query
                .eq('order_number', normalizedReference.toUpperCase())
                .limit(1)
                .maybeSingle();

      if (!mounted || !loadingRoute.isCurrent) return;
      if (order != null && order['id'] != null) {
        _replaceDestinationLoading(
          loadingRoute,
          OrderDetailScreen(order: order),
        );
        return;
      }
    } catch (_) {
      // If a historical notification cannot resolve its exact order, the
      // authenticated order list remains a safe and useful destination.
    }
    await _openOrdersListFromLoading(loadingRoute);
  }

  Future<void> _navigateToOrdersList() async {
    if (!mounted) return;
    final loadingRoute = _showDestinationLoading();
    await _openOrdersListFromLoading(loadingRoute);
  }

  Future<void> _openOrdersListFromLoading(Route<void> loadingRoute) async {
    try {
      final clientId = await AuthIdentityService.getEffectiveClientId();
      if (!mounted || !loadingRoute.isCurrent) return;
      if (clientId == null) {
        _closeDestinationLoading(loadingRoute);
        return;
      }
      _replaceDestinationLoading(
        loadingRoute,
        OrdersScreen(clientId: clientId),
      );
    } catch (error) {
      _closeDestinationLoading(loadingRoute);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible abrir el pedido: $error'),
          backgroundColor: kRed,
        ),
      );
    }
  }

  String? _notificationValue(
    Map<String, dynamic> notification,
    List<String> keys,
  ) {
    final sources = <Map<String, dynamic>>[notification];
    for (final containerKey in const ['data', 'metadata', 'payload']) {
      final value = notification[containerKey];
      if (value is Map) {
        sources.add(_stringKeyedMap(value));
      }
    }
    for (final source in sources) {
      for (final key in keys) {
        final value = source[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Route<void> _showDestinationLoading() {
    final route = PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const _NotificationDestinationLoadingScreen(),
    );
    Navigator.of(context).push(route);
    return route;
  }

  void _replaceDestinationLoading(
    Route<void> loadingRoute,
    Widget destination,
  ) {
    if (!mounted || !loadingRoute.isCurrent) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => destination,
      ),
    );
  }

  void _closeDestinationLoading(Route<void> loadingRoute) {
    if (!mounted || !loadingRoute.isActive) return;
    Navigator.of(context).removeRoute(loadingRoute);
  }

  /// Navigates to [AllProductQuestionsScreen] for the given product name.
  ///
  /// [answerHint] is the answer text extracted from the notification body.
  /// It is currently used for logging/future highlight functionality;
  /// the screen already shows all questions+answers for the product.
  Future<void> _navigateToProductQuestions(
    String productName, {
    String? answerHint,
  }) async {
    if (!mounted) return;
    final loadingRoute = _showDestinationLoading();

    try {
      // ── Try exact match first ────────────────────────────────────────────
      Map<String, dynamic>? product = await Supabase.instance.client
          .from('products')
          .select('id, name')
          .ilike('name', productName)
          .limit(1)
          .maybeSingle();

      // ── Fall back to partial match ───────────────────────────────────────
      product ??= await Supabase.instance.client
          .from('products')
          .select('id, name')
          .ilike('name', '%$productName%')
          .limit(1)
          .maybeSingle();

      if (!mounted || !loadingRoute.isCurrent) return;

      if (product != null && product['id'] != null) {
        final productId = product['id'] as String;
        final actualName = product['name'] as String;

        // Try to find the specific question for this product asked by this user
        final userId = Supabase.instance.client.auth.currentUser?.id;
        final effectiveClientId =
            await AuthIdentityService.getEffectiveClientId();
        List<dynamic> questionsData = [];

        if (userId != null && effectiveClientId != null) {
          final res = await Supabase.instance.client
              .from('product_questions')
              .select(
                '*, product_answers(*), products(${ProductService.publicProductSelect})',
              )
              .eq('product_id', productId)
              .eq('client_id', effectiveClientId)
              .order('created_at', ascending: false);
          questionsData = res as List;
        }

        if (questionsData.isNotEmpty) {
          final List<ProductQuestion> parsedQuestions = questionsData
              .map((e) => ProductQuestion.fromJson(e as Map<String, dynamic>))
              .toList();

          ProductQuestion selectedQuestion = parsedQuestions.first;
          if (answerHint != null && answerHint.isNotEmpty) {
            // Find the question matching the answer text snippet
            for (final q in parsedQuestions) {
              final match = q.answers.any(
                (a) => a.answerText.toLowerCase().contains(
                  answerHint.toLowerCase(),
                ),
              );
              if (match) {
                selectedQuestion = q;
                break;
              }
            }
          }

          if (mounted && loadingRoute.isCurrent) {
            _replaceDestinationLoading(
              loadingRoute,
              SingleQuestionScreen(question: selectedQuestion),
            );
            return;
          }
        }

        // Fallback: If no single question could be resolved, show all questions
        if (mounted && loadingRoute.isCurrent) {
          _replaceDestinationLoading(
            loadingRoute,
            AllProductQuestionsScreen(
              productId: productId,
              productName: actualName,
            ),
          );
        }
      } else {
        _closeDestinationLoading(loadingRoute);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el producto de esta notificación.'),
            backgroundColor: kRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _closeDestinationLoading(loadingRoute);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir la pregunta: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  Future<void> _navigateToQuote(String referenceNumber) async {
    if (!mounted) return;
    final loadingRoute = _showDestinationLoading();
    try {
      final client = Supabase.instance.client;
      Map<String, dynamic>? quote;
      Map<String, dynamic>? request;

      if (_isUuid(referenceNumber)) {
        quote = await client
            .from('quotes')
            .select('*')
            .eq('id', referenceNumber)
            .limit(1)
            .maybeSingle();
        request ??= await client
            .from('quote_requests')
            .select('*')
            .eq('id', referenceNumber)
            .limit(1)
            .maybeSingle();
      } else if (referenceNumber.startsWith('RQ-')) {
        request = await client
            .from('quote_requests')
            .select('*')
            .eq('request_number', referenceNumber)
            .maybeSingle();
      } else {
        quote = await client
            .from('quotes')
            .select('*')
            .eq('quote_number', referenceNumber)
            .maybeSingle();
      }

      if (!mounted || !loadingRoute.isCurrent) return;

      if (request != null && request['id'] != null) {
        _replaceDestinationLoading(
          loadingRoute,
          QuoteRequestDetailScreen(request: request),
        );
        return;
      }

      if (quote != null && quote['id'] != null) {
        _replaceDestinationLoading(
          loadingRoute,
          QuoteDetailScreen(quote: quote),
        );
        return;
      }
    } catch (_) {
      // La lista combinada sigue siendo un destino seguro si el detalle no
      // puede resolverse por cambios de esquema o conectividad.
    }

    await _openQuotesListFromLoading(loadingRoute);
  }

  Future<void> _navigateToQuotesList() async {
    if (!mounted) return;
    final loadingRoute = _showDestinationLoading();
    await _openQuotesListFromLoading(loadingRoute);
  }

  Future<void> _openQuotesListFromLoading(Route<void> loadingRoute) async {
    try {
      final clientId = await AuthIdentityService.getEffectiveClientId();
      if (!mounted || !loadingRoute.isCurrent) return;
      if (clientId == null) {
        _closeDestinationLoading(loadingRoute);
        return;
      }
      _replaceDestinationLoading(
        loadingRoute,
        QuotesScreen(clientId: clientId),
      );
    } catch (error) {
      _closeDestinationLoading(loadingRoute);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible abrir la cotización: $error'),
          backgroundColor: kRed,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => n['is_read'] == false);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Notificaciones',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (hasUnread)
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(
                Icons.done_all_rounded,
                color: Colors.white,
                size: 18,
              ),
              label: const Text(
                'Marcar todas',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const _NotificationsLoadingBody()
          : _error != null
          ? _buildError()
          : _notifications.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: kPrimary,
              backgroundColor: Colors.white,
              displacement: 42,
              triggerMode: RefreshIndicatorTriggerMode.onEdge,
              onRefresh: _refreshNotifications,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                physics: UiHelpers.refreshScrollPhysics,
                itemCount: _notifications.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFEEEEEE),
                ),
                itemBuilder: (context, i) {
                  final notification = _notifications[i];
                  return KeyedSubtree(
                    key: ValueKey(notification['id']?.toString() ?? i),
                    child: _buildNotifCard(notification),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildNotifCard(Map<String, dynamic> n) {
    final bool isRead = n['is_read'] as bool? ?? false;
    final presentation = notificationPresentation(n);
    final String title = presentation.title;
    final String body = presentation.body;
    final date = DateTime.tryParse(n['created_at'] ?? '')?.toLocal();
    final dateStr = date != null ? _formatDate(date) : '';
    final style = _notifStyle(
      title,
      body,
      isServiceNotification: presentation.isServiceNotification,
    );
    final String? imageUrl = UiHelpers.sanitizeTrustedRemoteUrl(
      n['image_url'] as String?,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Tappable row ────────────────────────────────────────────────────
        InkWell(
          onTap: () => _handleNotificationTap(n),
          splashColor: Colors.grey.shade100,
          highlightColor: Colors.grey.shade50,
          child: Container(
            // 100% white, no border, no rounded corners, no shadow
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── LEFT: square icon / image box ─────────────────────────
                SizedBox(
                  width: 50,
                  height: 50,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _iconBox(style),
                          )
                        : _iconBox(style),
                  ),
                ),
                const SizedBox(width: 12),
                // ── RIGHT: title + date + subtitle ────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + date on the same row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Date/time – top right, gray, small
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Subtitle snippet – gray, 2 lines max
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // ── Unread indicator dot (top-right corner) ───────────────
                if (!isRead)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF024C8B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ── Separator ───────────────────────────────────────────────────────
        Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
      ],
    );
  }

  /// Renders a colored icon box as fallback when no image URL is available.
  /// Uses a subtle tinted background — NO green cards, NO rounded outer borders.
  Widget _iconBox(({IconData icon, Color color, Color bg}) style) {
    return Container(
      width: 50,
      height: 50,
      color: style.bg,
      child: Icon(style.icon, color: style.color, size: 24),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: kPrimary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sin notificaciones',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Te avisaremos sobre tus tickets,\ncotizaciones y pedidos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return LoadErrorState(
      error: _error,
      onRetry: _loadNotifications,
      genericTitle: 'Error al cargar notificaciones',
      genericMessage: 'No pudimos cargar tus notificaciones por el momento.',
    );
  }
}
