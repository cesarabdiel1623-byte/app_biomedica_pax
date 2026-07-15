import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_helpers.dart';
import 'quotes_screen.dart';
import 'quote_detail_screen.dart';
import '../product/all_questions_screen.dart';
import '../product/single_question_screen.dart';
import '../tickets/ticket_detail_screen.dart';
import '../../services/question_service.dart';
import '../../utils/ui_helpers.dart';

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
        title: const Text('Notificaciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                SwitchListTile(
                  title: const Text('Alertas por WhatsApp', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Recibe actualizaciones de tus tickets y cotizaciones vía WhatsApp.', style: TextStyle(fontSize: 11)),
                  value: _whatsapp,
                  activeThumbColor: kPrimary,
                  onChanged: (v) {
                    setState(() => _whatsapp = v);
                    _savePref('notif_whatsapp', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Notificaciones por Correo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Recibe presupuestos y comprobantes de compra en tu email.', style: TextStyle(fontSize: 11)),
                  value: _email,
                  activeThumbColor: kPrimary,
                  onChanged: (v) {
                    setState(() => _email = v);
                    _savePref('notif_email', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Seguimiento de Pedidos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Notificaciones en tiempo real del estado de tus órdenes.', style: TextStyle(fontSize: 11)),
                  value: _orderUpdates,
                  activeThumbColor: kPrimary,
                  onChanged: (v) {
                    setState(() => _orderUpdates = v);
                    _savePref('notif_orders', v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Seguridad y Acceso', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Notificaciones sobre inicios de sesión y cambios de contraseña.', style: TextStyle(fontSize: 11)),
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
  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() => _NotificationsListScreenState();
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() { _loading = true; _error = null; });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('No autenticado');

      final response = await Supabase.instance.client
          .from('notifications')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notifications = response as List;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      _loadNotifications();
    } catch (_) {}
  }

  Future<void> _markAsRead(String id) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (_) {}
  }

  ({IconData icon, Color color, Color bg}) _notifStyle(String title, String body) {
    final t = title.toLowerCase();
    final b = body.toLowerCase();
    if (t.contains('ticket') || b.contains('tck-') || t.contains('soporte')) {
      return (icon: Icons.build_circle_rounded, color: const Color(0xFF0D9488), bg: const Color(0xFFE6F7F6));
    } else if (t.contains('cotiza') || b.contains('cot-')) {
      return (icon: Icons.request_quote_rounded, color: const Color(0xFF1E3A5F), bg: const Color(0xFFE8EEF7));
    } else if (t.contains('pedido') || t.contains('orden') || b.contains('ord-')) {
      return (icon: Icons.local_shipping_rounded, color: const Color(0xFF7C3AED), bg: const Color(0xFFF3EEFF));
    } else if (t.contains('pago') || t.contains('factura')) {
      return (icon: Icons.payments_rounded, color: const Color(0xFF16A34A), bg: const Color(0xFFECFDF5));
    } else if (t.contains('bienvenid')) {
      return (icon: Icons.celebration_rounded, color: const Color(0xFFF59E0B), bg: const Color(0xFFFFFBEB));
    } else if (t.contains('pregunta') || b.contains('pregunta')) {
      return (icon: Icons.question_answer_rounded, color: const Color(0xFF0D9488), bg: const Color(0xFFE0F2F1));
    } else {
      return (icon: Icons.notifications_rounded, color: const Color(0xFF64748B), bg: const Color(0xFFF1F5F9));
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notification) async {
    final String id = notification['id'] as String;
    final bool isRead = notification['is_read'] as bool? ?? false;
    final String body = notification['body'] ?? '';
    final String title = notification['title'] ?? '';

    // ── 1. Mark as read immediately (optimistic UI update) ────────────────
    if (!isRead) {
      _markAsRead(id); // fire-and-forget in background
      setState(() {
        final idx = _notifications.indexWhere((n) => n['id'] == id);
        if (idx != -1) _notifications[idx] = {..._notifications[idx], 'is_read': true};
      });
    }

    // ── 2. Detect question/answer notification ────────────────────────────
    // Title pattern: "Pregunta respondida"
    // Body pattern:  Tu pregunta sobre "ProductName" fue respondida: "answerText"
    final bool isQuestionNotif =
        title.toLowerCase().contains('pregunta') ||
        body.toLowerCase().contains('pregunta');

    if (isQuestionNotif) {
      // Extract product name from body: sobre "X"
      final nameMatch = RegExp(r'sobre\s+"([^"]+)"').firstMatch(body);
      // Extract the answer text from body: respondida: "Y"
      final answerMatch = RegExp(r'respondida:\s+"([^"]+)"').firstMatch(body);

      final String? productName = nameMatch?.group(1);
      final String? answerText = answerMatch?.group(1);

      if (productName != null) {
        await _navigateToProductQuestions(productName, answerHint: answerText);
      }
      return;
    }

    // ── 3. Detect ticket notification (TCK-XXXXXXXX-XXXXXXXX) ─────────────
    final ticketMatch = RegExp(r'TCK-\d{8}-[A-Za-z0-9]+').firstMatch(body);
    if (ticketMatch != null) {
      final ticketNumber = ticketMatch.group(0)!;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TicketDetailScreen(ticketNumber: ticketNumber),
        ),
      );
      return;
    }

    // ── 4. Detect quote notification (COT-XXXXXXXX-XXXXXXXX) ──────────────
    final quoteMatch = RegExp(r'COT-\d{8}-[A-Za-z0-9]+').firstMatch(body);
    if (quoteMatch != null) {
      await _navigateToQuote(quoteMatch.group(0)!);
      return;
    }
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
    // Show a non-blocking overlay while we resolve the product ID
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => const Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: kPrimary),
          ),
        ),
      ),
    );

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

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading overlay

      if (product != null && product['id'] != null) {
        final productId = product['id'] as String;
        final actualName = product['name'] as String;

        // Try to find the specific question for this product asked by this user
        final userId = Supabase.instance.client.auth.currentUser?.id;
        List<dynamic> questionsData = [];

        if (userId != null) {
          final res = await Supabase.instance.client
              .from('product_questions')
              .select('*, product_answers(*), products(*, product_media(*), product_specs(*), product_inventory(*), active_product_promotions(*))')
              .eq('product_id', productId)
              .eq('client_id', userId)
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
              final match = q.answers.any((a) => a.answerText.toLowerCase().contains(answerHint.toLowerCase()));
              if (match) {
                selectedQuestion = q;
                break;
              }
            }
          }

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SingleQuestionScreen(question: selectedQuestion),
              ),
            );
            return;
          }
        }

        // Fallback: If no single question could be resolved, show all questions
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AllProductQuestionsScreen(
                productId: productId,
                productName: actualName,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el producto de esta notificación.'),
            backgroundColor: kRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir la pregunta: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  Future<void> _navigateToQuote(String quoteNumber) async {
    final response = await Supabase.instance.client
        .from('quotes')
        .select('*')
        .eq('quote_number', quoteNumber)
        .maybeSingle();

    if (!mounted) return;

    if (response != null && response['id'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuoteDetailScreen(quote: response),
        ),
      );
    } else {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final profileRes = await Supabase.instance.client
          .from('profiles').select('client_id').eq('id', userId).maybeSingle();
      final clientId = profileRes?['client_id'] as String? ?? userId;
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => QuotesScreen(clientId: clientId)),
        );
      }
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
      body: Column(
        children: [
          Container(
            color: kPrimary,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Notificaciones',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (hasUnread)
                      TextButton.icon(
                        onPressed: _markAllAsRead,
                        icon: const Icon(Icons.done_all_rounded, color: Colors.white, size: 18),
                        label: const Text(
                          'Marcar todas',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : _error != null
                    ? _buildError()
                    : _notifications.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: kPrimary,
                            onRefresh: _loadNotifications,
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              itemCount: _notifications.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                              itemBuilder: (context, i) => _buildNotifCard(_notifications[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifCard(Map<String, dynamic> n) {
    final bool isRead = n['is_read'] as bool? ?? false;
    final String title = n['title'] ?? 'Notificación';
    final String body = n['body'] ?? '';
    final date = DateTime.tryParse(n['created_at'] ?? '')?.toLocal();
    final dateStr = date != null ? _formatDate(date) : '';
    final style = _notifStyle(title, body);
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
                        color: Color(0xFF0D9488),
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
            child: const Icon(Icons.notifications_none_rounded, size: 56, color: kPrimary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sin notificaciones',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kNavy),
          ),
          const SizedBox(height: 8),
          Text(
            'Te avisaremos sobre tus tickets,\ncotizaciones y pedidos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Error al cargar: $_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadNotifications,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
