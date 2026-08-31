import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../profile/orders_screen.dart';
import '../../profile/quotes_screen.dart';
import '../../profile/coupons_screen.dart';
import '../../profile/edit_profile_screen.dart';
import '../../profile/notifications_screen.dart';
import '../../tickets/tickets_list_screen.dart';
import '../../product/favorites_screen.dart';
import '../../product/recently_viewed_screen.dart';
import '../../quotes/questions_screen.dart';
import '../../quotes/reviews_screen.dart';

const _kPrimary = Color(0xFF024C8B);

class ProfileTab extends StatefulWidget {
  final VoidCallback onSignOut;
  const ProfileTab({super.key, required this.onSignOut});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const _supportEmail = 'contacto@gomedical.mx';
  static const _supportPhonePrimary = '529993352872';
  static const _supportPhoneSecondary = '529992660702';

  String? _clientId;
  bool _loadingClient = true;

  @override
  void initState() {
    super.initState();
    _loadClientData();
  }

  Future<void> _loadClientData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      _clientId = userId;
    }
    try {
      if (userId == null) {
        setState(() => _loadingClient = false);
        return;
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('client_id')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _clientId = (profile?['client_id'] as String?) ?? userId;
          _loadingClient = false;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar datos del cliente: $e');
      if (mounted) setState(() => _loadingClient = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['full_name'] as String? ?? 'Usuario';
    final email = user?.email ?? '';
    final initials = name
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: _kPrimary,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        child: Text(
                          initials.isNotEmpty ? initials : 'U',
                          style: const TextStyle(
                            fontSize: 30,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Mi Cuenta'),
                ProfileStaggeredSlide(
                  index: 0,
                  child: _menuTile(
                    Icons.shopping_bag_outlined,
                    'Compras',
                    'Historial de tus compras y pedidos',
                    const Color(0xFF10B981),
                    () {
                      if (_clientId != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrdersScreen(clientId: _clientId!),
                          ),
                        );
                      }
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 1,
                  child: _menuTile(
                    Icons.request_quote_outlined,
                    'Mis Cotizaciones',
                    'Tus solicitudes de cotización',
                    _kPrimary,
                    () {
                      if (_clientId != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => QuotesScreen(clientId: _clientId!),
                          ),
                        );
                      }
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 2,
                  child: _menuTile(
                    Icons.confirmation_number_outlined,
                    'Cupones',
                    'Descuentos disponibles para ti',
                    const Color(0xFFF59E0B),
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CouponsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 3,
                  child: _menuTile(
                    Icons.favorite_outline,
                    'Favoritos',
                    'Tus equipos guardados',
                    const Color(0xFFF43F5E),
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FavoritesScreen(),
                        ),
                      );
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 4,
                  child: _menuTile(
                    Icons.history_outlined,
                    'Historial',
                    'Equipos vistos recientemente',
                    const Color(0xFF0F172A),
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RecentlyViewedScreen(),
                        ),
                      );
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 5,
                  child: _menuTile(
                    Icons.question_answer_outlined,
                    'Preguntas',
                    'Tus consultas sobre equipos',
                    _kPrimary,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QuestionsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 6,
                  child: _menuTile(
                    Icons.star_outline,
                    'Opiniones',
                    'Tus valoraciones escritas',
                    const Color(0xFF10B981),
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReviewsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                _divider(),
                _sectionLabel('Soporte'),
                ProfileStaggeredSlide(
                  index: 7,
                  child: _menuTile(
                    Icons.build_circle_outlined,
                    'Servicios',
                    'Servicios programados',
                    const Color(0xFF10B981),
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TicketsListScreen(),
                        ),
                      );
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 8,
                  child: _menuTile(
                    Icons.support_agent_outlined,
                    'Ayuda y Soporte',
                    'Contacta a nuestro equipo',
                    const Color(0xFFF43F5E),
                    () => _showHelpBottomSheet(),
                  ),
                ),
                _divider(),
                _sectionLabel('Configuración'),
                ProfileStaggeredSlide(
                  index: 9,
                  child: _menuTile(
                    Icons.person_outline,
                    'Editar Perfil',
                    'Actualiza tus datos',
                    const Color(0xFF0F172A),
                    () async {
                      final updated = await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      );
                      if (updated == true) {
                        _loadClientData();
                        setState(() {});
                      }
                    },
                  ),
                ),
                ProfileStaggeredSlide(
                  index: 10,
                  child: _menuTile(
                    Icons.notifications_outlined,
                    'Notificaciones',
                    'Preferencias de alertas',
                    const Color(0xFF0F172A),
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: widget.onSignOut,
                      icon: const Icon(
                        Icons.logout,
                        size: 18,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'Cerrar Sesión',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ayuda y Soporte',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '¿Necesitas ayuda con algún producto, pedido o servicio técnico?',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF25D366),
                child: Icon(Icons.chat, color: Colors.white),
              ),
              title: const Text('WhatsApp Soporte'),
              subtitle: const Text('+52 999 335 2872'),
              onTap: () async {
                Navigator.pop(ctx);
                await _openWhatsApp(
                  _supportPhonePrimary,
                  fallbackMessage: 'No se pudo abrir WhatsApp.',
                );
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF25D366),
                child: Icon(Icons.chat, color: Colors.white),
              ),
              title: const Text('WhatsApp Soporte'),
              subtitle: const Text('+52 999 266 0702'),
              onTap: () async {
                Navigator.pop(ctx);
                await _openWhatsApp(
                  _supportPhoneSecondary,
                  fallbackMessage: 'No se pudo abrir WhatsApp.',
                );
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: _kPrimary,
                child: Icon(Icons.email, color: Colors.white),
              ),
              title: const Text('Correo Electrónico'),
              subtitle: const Text(_supportEmail),
              onTap: () async {
                Navigator.pop(ctx);
                await _openExternalUri(
                  Uri(scheme: 'mailto', path: _supportEmail),
                  fallbackMessage: 'No se pudo abrir el cliente de correo.',
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(
    String phone, {
    required String fallbackMessage,
  }) async {
    final appUri = Uri.parse('whatsapp://send?phone=$phone');
    final webUri = Uri.https('wa.me', '/$phone');

    if (await _tryLaunch(appUri)) return;
    if (await _tryLaunch(webUri)) return;

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(fallbackMessage)));
    }
  }

  Future<void> _openExternalUri(
    Uri uri, {
    required String fallbackMessage,
  }) async {
    if (await _tryLaunch(uri)) return;

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(fallbackMessage)));
    }
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('No se pudo abrir enlace externo: ${uri.scheme}');
      return false;
    }
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade500,
      ),
    ),
  );

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Divider(color: Colors.grey.shade200, height: 1),
  );

  Widget _menuTile(
    IconData icon,
    String title,
    String subtitle,
    Color _,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
            ),
            child: Icon(icon, color: const Color(0xFF6B7280), size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        ],
      ),
    ),
  );
}

class ProfileStaggeredSlide extends StatefulWidget {
  final Widget child;
  final int index;
  const ProfileStaggeredSlide({
    super.key,
    required this.child,
    required this.index,
  });

  @override
  State<ProfileStaggeredSlide> createState() => _ProfileStaggeredSlideState();
}

class _ProfileStaggeredSlideState extends State<ProfileStaggeredSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.2, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}
