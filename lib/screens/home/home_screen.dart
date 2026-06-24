import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart';
import '../../models/product.dart';
import '../../models/service_ticket.dart';
import '../../services/product_service.dart';
import '../../services/cart_service.dart';
import '../../services/address_service.dart';
import '../../services/ticket_service.dart';
import '../../models/ticket_message.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../product/product_detail_screen.dart';
import '../product/category_products_screen.dart';
import '../product/search_screen.dart';
import '../profile/profile_details_screens.dart';
import 'address_picker_screen.dart';
import '../../services/notification_service.dart';
import '../../services/quote_service.dart';
import '../product/quote_cart_screen.dart';

// Permite drag con mouse en web (fix para ListView horizontal)
class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

const _kPrimary = Color(0xFF0D9488);     // Teal principal
const _kPrimaryDark = Color(0xFF0A7A6F);  // Teal oscuro
const _kNavy = Color(0xFF1E3A5F);         // Azul navy para textos
const _kAmber = Color(0xFFF59E0B);        // Ámbar CTA
const _kGreen = Color(0xFF16A34A);        // Verde envío
const _kRed = Color(0xFFEF4444);          // Rojo descuento
const _kBg = Color(0xFFF8FAFC);           // Gris claro fondo

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static _HomeScreenState? _state;
  static void showTab(int index) {
    _state?.setTab(index);
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [];
  final GlobalKey<_MarketplaceTabState> _marketplaceTabKey = GlobalKey<_MarketplaceTabState>();
  final GlobalKey<_CartTabState> _cartTabKey = GlobalKey<_CartTabState>();

  @override
  void initState() {
    super.initState();
    HomeScreen._state = this;
    _screens.addAll([
      _MarketplaceTab(key: _marketplaceTabKey),
      const _CategoriesTab(),
      _CartTab(key: _cartTabKey),
      _ProfileTab(
        onSignOut: _signOut,
      ),
    ]);
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    if (HomeScreen._state == this) {
      HomeScreen._state = null;
    }
    _unsubscribeFromNotifications();
    super.dispose();
  }

  void _unsubscribeFromNotifications() {
    NotificationService.instance.stopListening();
  }

  void _subscribeToNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    NotificationService.instance.startListening(userId);
  }

  Future<void> _signOut() async {
    try {
      _unsubscribeFromNotifications();
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false,
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void setTab(int index) {
    setState(() => _currentIndex = index);
    if (index == 2) {
      _cartTabKey.currentState?._load();
    } else if (index == 0) {
      _marketplaceTabKey.currentState?._load(isLiveSearch: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
            if (i == 0) {
              _marketplaceTabKey.currentState?._load(isLiveSearch: true);
            } else if (i == 2) {
              _cartTabKey.currentState?._load();
            }
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: _kPrimary,
          unselectedItemColor: Colors.grey.shade500,
          selectedFontSize: 11, unselectedFontSize: 10,
          backgroundColor: Colors.white, elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Inicio'),
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view), label: 'Categorías'),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), activeIcon: Icon(Icons.shopping_cart), label: 'Carrito'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// TAB 1: MARKETPLACE — Grid 2 cols estilo ML
// ══════════════════════════════════════════
class _MarketplaceTab extends StatefulWidget {
  const _MarketplaceTab({super.key});
  @override
  State<_MarketplaceTab> createState() => _MarketplaceTabState();
}

class _MarketplaceTabState extends State<_MarketplaceTab> {
  List<Product> _products = [];
  bool _loading = true;
  String? _error;
  String? _activeCategory;
  String _currentLocation = 'Selecciona tu ubicación';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    _loadLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      final addr = await AddressService.getDefaultAddress();
      if (addr != null && mounted) {
        setState(() => _currentLocation = addr.displayText);
      }
    } catch (_) {}
  }

  Future<void> _load({bool isLiveSearch = false}) async {
    try {
      if (!isLiveSearch) {
        setState(() { _loading = true; _error = null; });
      }
      List<Product> p;
      if (_searchQuery.isNotEmpty) {
        p = await ProductService.searchProducts(_searchQuery);
        if (_activeCategory != null) {
          p = p.where((item) => item.category == _activeCategory).toList();
        }
      } else {
        p = await ProductService.getAllProducts(category: _activeCategory);
      }
      if (mounted) {
        setState(() {
          _products = p;
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

  void _setCategory(String? cat) {
    setState(() => _activeCategory = _activeCategory == cat ? null : cat);
    _load();
  }

  Widget _sectionHeader(IconData icon, String title, Color color, VoidCallback onTap) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: _kNavy),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      'Ver todo',
                      style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, color: color, size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _horizontalProductList(List<Product> list) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 320,
        child: ScrollConfiguration(
          behavior: _MouseDragScrollBehavior(),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length,
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: SizedBox(
                  width: 185,
                  child: _ProductCard(product: list[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHomeLanding = _searchQuery.isEmpty && _activeCategory == null;

    final promoProducts = _products.where((p) => p.hasDiscount).toList();
    final equiposProducts = _products.where((p) => p.category == 'equipo_medico').toList();
    final ultrasoundProducts = _products.where((p) => 
        p.category == 'ultrasonido_humano' || p.category == 'ultrasonido_veterinario').toList();
    final consumiblesProducts = _products.where((p) => 
        p.category == 'consumible' || p.category == 'refaccion').toList();
    final serviciosProducts = _products.where((p) => p.category == 'servicio').toList();

    return SafeArea(
      child: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // Header + Search
            SliverToBoxAdapter(child: _header()),
            // Banner
            SliverToBoxAdapter(child: _banner()),
            // Quick categories
            SliverToBoxAdapter(child: _quickCats()),
            
            // Content
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: _kPrimary)))
            else if (_error != null)
              SliverFillRemaining(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
                const SizedBox(height: 8),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ])))
            else if (_products.isEmpty)
              const SliverFillRemaining(child: Center(child: Text('No hay productos en esta categoría')))
            else ...[
              if (isHomeLanding) ...[
                // 1. Promociones del Día (Horizontal Scroll)
                if (promoProducts.isNotEmpty) ...[
                  _sectionHeader(Icons.local_offer, 'Promociones del Día', const Color(0xFFEF4444), () {
                    // Reset search / categories to show all (simulating clearing filter to see all)
                    setState(() {
                      _activeCategory = null;
                      _searchQuery = '';
                    });
                  }),
                  _horizontalProductList(promoProducts),
                ],

                // 2. Equipos Médicos Destacados
                if (equiposProducts.isNotEmpty) ...[
                  _sectionHeader(Icons.medical_services, 'Equipos Médicos', const Color(0xFF0D9488), () {
                    _setCategory('equipo_medico');
                  }),
                  _horizontalProductList(equiposProducts),
                ],

                // 3. Ultrasonido y Diagnóstico
                if (ultrasoundProducts.isNotEmpty) ...[
                  _sectionHeader(Icons.monitor_heart, 'Ultrasonido y Diagnóstico', const Color(0xFF3B82F6), () {
                    _setCategory('ultrasonido_humano');
                  }),
                  _horizontalProductList(ultrasoundProducts),
                ],

                // 4. Consumibles y Refacciones
                if (consumiblesProducts.isNotEmpty) ...[
                  _sectionHeader(Icons.water_drop, 'Consumibles y Refacciones', const Color(0xFF0EA5E9), () {
                    _setCategory('consumible');
                  }),
                  _horizontalProductList(consumiblesProducts),
                ],

                // 5. Servicio Técnico Especializado
                if (serviciosProducts.isNotEmpty) ...[
                  _sectionHeader(Icons.settings_suggest, 'Servicios de Mantenimiento', const Color(0xFF8B5CF6), () {
                    _setCategory('servicio');
                  }),
                  _horizontalProductList(serviciosProducts),
                ],
                
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ] else ...[
                // Default filtered/search results (Vertical Grid)
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(_activeCategory != null ? _catLabel(_activeCategory!) : 'Resultados de búsqueda',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kNavy)),
                )),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 315,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ProductCard(product: _products[i]),
                      childCount: _products.length,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    color: _kPrimary,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SearchScreen(),
                  ),
                );
              },
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey.shade500, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Buscar equipo médico',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuoteCartScreen()),
              );
            },
            child: ValueListenableBuilder<int>(
              valueListenable: QuoteService.quoteCountNotifier,
              builder: (context, count, _) {
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text(count.toString()),
                  backgroundColor: _kNavy,
                  textColor: Colors.white,
                  child: const Icon(Icons.request_quote_outlined, color: Colors.white, size: 24),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsListScreen()),
              );
              // Refresh notification count when returning
              final userId = Supabase.instance.client.auth.currentUser?.id;
              if (userId != null) {
                NotificationService.instance.updateUnreadCount(userId);
              }
            },
            child: ValueListenableBuilder<int>(
              valueListenable: NotificationService.instance.unreadCountNotifier,
              builder: (context, count, _) {
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 99 ? '99+' : count.toString()),
                  backgroundColor: const Color(0xFFEF4444),
                  textColor: Colors.white,
                  child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                );
              },
            ),
          ),
        ]),
        // ── Barra de ubicación estilo ML compact ────
        GestureDetector(
          onTap: () async {
            final result = await Navigator.of(context).push<ClientAddress>(
              MaterialPageRoute(builder: (_) => const AddressPickerScreen()),
            );
            if (result != null && mounted) {
              setState(() => _currentLocation = result.displayText);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_on, color: Colors.white, size: 13),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _currentLocation == 'Selecciona tu ubicación'
                    ? '¿Dónde enviamos?'
                    : _currentLocation,
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 14),
            ]),
          ),
        ),
      ],
    ),
  );

  Widget _banner() => const _BannerCarousel();

  Widget _quickCats() {
    final cats = [
      {'icon': Icons.medical_services, 'label': 'Equipos', 'cat': 'equipo_medico', 'color': const Color(0xFF0D9488)},
      {'icon': Icons.monitor_heart, 'label': 'Ultrasonido', 'cat': 'ultrasonido_humano', 'color': const Color(0xFF3B82F6)},
      {'icon': Icons.pets, 'label': 'Veterinaria', 'cat': 'ultrasonido_veterinario', 'color': const Color(0xFF10B981)},
      {'icon': Icons.water_drop, 'label': 'Consumibles', 'cat': 'consumible', 'color': const Color(0xFF0EA5E9)},
      {'icon': Icons.build, 'label': 'Refacciones', 'cat': 'refaccion', 'color': const Color(0xFFEC4899)},
      {'icon': Icons.settings_suggest, 'label': 'Servicios', 'cat': 'servicio', 'color': const Color(0xFF8B5CF6)},
    ];
    return SizedBox(
      height: 90,
      child: ScrollConfiguration(
        behavior: _MouseDragScrollBehavior(),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: cats.length,
          itemBuilder: (_, i) {
            final c = cats[i];
            final catKey = c['cat'] as String?;
            final active = catKey != null && _activeCategory == catKey;
            final color = c['color'] as Color;
            return GestureDetector(
              onTap: () {
                if (catKey != null) _setCategory(catKey);
              },
              child: Container(
                width: 68, margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: active ? color : color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: active ? null : Border.all(color: color.withOpacity(0.25), width: 1),
                    ),
                    child: Icon(c['icon'] as IconData, color: active ? Colors.white : color, size: 22),
                  ),
                  const SizedBox(height: 5),
                  Text(c['label'] as String, textAlign: TextAlign.center,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5,
                      color: active ? color : Colors.grey.shade700,
                      fontWeight: active ? FontWeight.bold : FontWeight.w500)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  String _catLabel(String cat) {
    switch (cat) {
      case 'equipo_medico': return 'Equipos Médicos';
      case 'ultrasonido_humano': return 'Ultrasonido Humano';
      case 'ultrasonido_veterinario': return 'Ultrasonido Veterinario';
      case 'consumible': return 'Consumibles';
      case 'refaccion': return 'Refacciones';
      case 'servicio': return 'Servicios Técnicos';
      default: return cat;
    }
  }
}

// ══════════════════════════════════════════
// BANNER CAROUSEL — Auto-rotating 4 slides
// ══════════════════════════════════════════
class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel();
  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final _controller = PageController();
  int _current = 0;
  Timer? _timer;

  static const _banners = [
    {
      'title': 'Equipa tu clínica',
      'subtitle': 'Hasta 20% OFF en equipos seleccionados',
      'cta': 'Ver ofertas',
      'icon': Icons.local_hospital,
      'colors': [Color(0xFF1E3A5F), Color(0xFF0D9488)],
    },
    {
      'title': 'Ultrasonido Veterinario',
      'subtitle': 'Nuevos modelos portátiles disponibles',
      'cta': 'Ver catálogo',
      'icon': Icons.monitor_heart,
      'colors': [Color(0xFF5B21B6), Color(0xFF2563EB)],
    },
    {
      'title': 'Envío Express',
      'subtitle': 'Entrega en 24-48 hrs en zona metropolitana',
      'cta': 'Comprar ahora',
      'icon': Icons.local_shipping,
      'colors': [Color(0xFF065F46), Color(0xFF0D9488)],
    },
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_current + 1) % _banners.length;
      _controller.animateToPage(next,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      height: 130,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: PageView.builder(
              controller: _controller,
              itemCount: _banners.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final b = _banners[i];
                final colors = b['colors'] as List<Color>;
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(b['title'] as String,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(b['subtitle'] as String,
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.5)),
                          ),
                          child: Text(b['cta'] as String,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    )),
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(b['icon'] as IconData, size: 28, color: Colors.white70),
                    ),
                  ]),
                );
              },
            ),
          ),
          // Dots indicator
          Positioned(
            bottom: 8, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_banners.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(_current == i ? 1.0 : 0.35),
                  shape: BoxShape.circle,
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// PRODUCT CARD — Mercado Libre style
// ══════════════════════════════════════════
class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: product.id),
      )),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Imagen + cart button + badge ──────────
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(children: [
                // Imagen
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: Container(
                    width: double.infinity, height: 150,
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(8),
                    child: product.mainImageUrl != null
                      ? Image.network(product.mainImageUrl!, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                  ),
                ),
                // Badge de descuento en imagen (esquina sup izq)
                if (product.hasDiscount)
                  Positioned(left: 6, top: 6,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 130),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kRed, borderRadius: BorderRadius.circular(3)),
                      child: Text(
                        product.activePromotion?.campaignName != null
                          ? '${product.activePromotion!.campaignName!.toUpperCase()} · ${product.discountPercent}% OFF'
                          : '${product.discountPercent}% OFF',
                        style: const TextStyle(color: Colors.white,
                          fontSize: 9, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                // Botón cotización + carrito (esquina inf der) — estilo ML
                Positioned(right: 6, bottom: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Botón Cotización
                      GestureDetector(
                        onTap: () async {
                          try {
                            await QuoteService.addToQuote(product);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              final controller = ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ ${product.name} añadido a cotización'),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: _kNavy,
                                  action: SnackBarAction(
                                    label: 'VER BOLSA',
                                    textColor: Colors.white,
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const QuoteCartScreen()),
                                      );
                                    },
                                  ),
                                ),
                              );
                              Future.delayed(const Duration(seconds: 2), () {
                                try { controller.close(); } catch (_) {}
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: _kRed),
                              );
                            }
                          }
                        },
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                          ),
                          child: const Icon(Icons.request_quote_outlined,
                            size: 16, color: _kNavy),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Botón carrito
                      GestureDetector(
                        onTap: () async {
                          try {
                            await CartService.addToCart(product.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              final controller = ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ ${product.name} al carrito'),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: _kPrimary,
                                  action: SnackBarAction(
                                    label: 'VER CARRITO',
                                    textColor: Colors.white,
                                    onPressed: () {
                                      Navigator.popUntil(context, (route) => route.isFirst);
                                      HomeScreen.showTab(2);
                                    },
                                  ),
                                ),
                              );
                              Future.delayed(const Duration(seconds: 2), () {
                                try { controller.close(); } catch (_) {}
                              });
                            }
                          } catch (e) {
                            final msg = e.toString().replaceAll('Exception: ', '');
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg), backgroundColor: _kRed));
                          }
                        },
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
                              blurRadius: 4)],
                          ),
                          child: const Icon(Icons.add_shopping_cart_outlined,
                            size: 16, color: _kPrimary),
                        ),
                      ),
                    ],
                  )),
              ]),
            ),

            // ── Info del producto ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [

                  // Nombre
                  Text(product.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5,
                      color: Color(0xFF1F2937), height: 1.3)),

                  const SizedBox(height: 5),

                  // Precio anterior tachado + % descuento (pastilla verde ML)
                  if (product.hasDiscount)
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _kGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(3)),
                        child: Text('${product.discountPercent}% OFF',
                          style: const TextStyle(fontSize: 10,
                            color: _kGreen, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 5),
                      Expanded(child: Text(product.formattedOldPrice,
                        style: const TextStyle(fontSize: 11.5,
                          color: Color(0xFF9CA3AF),
                          decoration: TextDecoration.lineThrough),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),

                  // Precio actual (grande y bold)
                  Text(product.formattedPrice,
                    style: const TextStyle(fontSize: 18.5,
                      fontWeight: FontWeight.w700, color: Color(0xFF111827),
                      letterSpacing: -0.5)),

                  // Marca/Modelo (si existe) — como 'Vendido por X' en ML
                  if ((product.brand ?? product.commercialBrand) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        (product.brand ?? product.commercialBrand)!,
                        style: const TextStyle(fontSize: 11.0,
                          color: Color(0xFF6B7280)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  const SizedBox(height: 5),

                  // Envio
                  if (product.shippingInfo != null)
                    Row(children: [
                      Icon(Icons.local_shipping_outlined, size: 12,
                        color: product.hasFreeShipping ? _kGreen : const Color(0xFF6B7280)),
                      const SizedBox(width: 3),
                      Expanded(child: Text(product.shippingInfo!,
                        style: TextStyle(fontSize: 11,
                          color: product.hasFreeShipping ? _kGreen : const Color(0xFF6B7280),
                          fontWeight: product.hasFreeShipping
                            ? FontWeight.w600 : FontWeight.normal),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),

                  const SizedBox(height: 4),

                  // Stock / Disponibilidad
                  Row(
                    children: [
                      Icon(
                        product.stockStatusLabel == 'Sin stock'
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 12,
                        color: product.stockStatusColor,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          product.stockStatusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: product.stockStatusColor,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Center(
    child: Icon(Icons.medical_services_outlined,
      color: Colors.grey.shade300, size: 32));
}




// ══════════════════════════════════════════
// TAB 2: CATEGORÍAS — Split panel like ML
// ══════════════════════════════════════════
class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab();
  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  int _selectedIndex = 0;

  static final _categories = [
    {
      'key': 'equipo_medico', 'label': 'Equipos\nMédicos',
      'icon': Icons.medical_services, 'color': const Color(0xFF0D9488),
      'subs': [
        {'label': 'Ultrasonido', 'icon': Icons.monitor_heart, 'color': const Color(0xFF0EA5E9)},
        {'label': 'Rayos X', 'icon': Icons.radio_button_checked, 'color': const Color(0xFF6366F1)},
        {'label': 'Monitores', 'icon': Icons.desktop_windows, 'color': const Color(0xFF0D9488)},
        {'label': 'ECG / Cardio', 'icon': Icons.favorite, 'color': const Color(0xFFEF4444)},
        {'label': 'Soporte Vida', 'icon': Icons.health_and_safety, 'color': const Color(0xFFF59E0B)},
        {'label': 'PACS Nube', 'icon': Icons.cloud, 'color': const Color(0xFF3B82F6)},
        {'label': 'Quirúrgico', 'icon': Icons.content_cut, 'color': const Color(0xFFEC4899)},
        {'label': 'Rehabilitación', 'icon': Icons.accessibility_new, 'color': const Color(0xFF10B981)},
        {'label': 'Oftalmología', 'icon': Icons.visibility, 'color': const Color(0xFF8B5CF6)},
      ],
    },
    {
      'key': 'ultrasonido_humano', 'label': 'Ultrasonido',
      'icon': Icons.monitor_heart, 'color': const Color(0xFF3B82F6),
      'subs': [
        {'label': 'Portátil', 'icon': Icons.monitor_heart, 'color': const Color(0xFF3B82F6)},
        {'label': 'Convexo', 'icon': Icons.sensors, 'color': const Color(0xFF0D9488)},
        {'label': 'Doppler Color', 'icon': Icons.waterfall_chart, 'color': const Color(0xFFEC4899)},
        {'label': 'PACS', 'icon': Icons.cloud, 'color': const Color(0xFF0EA5E9)},
        {'label': 'Veterinario', 'icon': Icons.pets, 'color': const Color(0xFF10B981)},
      ],
    },
    {
      'key': 'veterinaria', 'label': 'Veterinaria',
      'icon': Icons.pets, 'color': const Color(0xFF10B981),
      'subs': [
        {'label': 'Monitor Vet.', 'icon': Icons.monitor_heart, 'color': const Color(0xFF10B981)},
        {'label': 'USG Vet.', 'icon': Icons.monitor_heart, 'color': const Color(0xFF3B82F6)},
        {'label': 'Anestesia', 'icon': Icons.air, 'color': const Color(0xFF6366F1)},
        {'label': 'Dental Vet.', 'icon': Icons.medical_information, 'color': const Color(0xFFF59E0B)},
        {'label': 'Rayos X Vet.', 'icon': Icons.radio_button_checked, 'color': const Color(0xFF8B5CF6)},
      ],
    },
    {
      'key': 'consumible', 'label': 'Consumibles',
      'icon': Icons.water_drop, 'color': const Color(0xFF0EA5E9),
      'subs': [
        {'label': 'Gel USG', 'icon': Icons.water_drop, 'color': const Color(0xFF0EA5E9)},
        {'label': 'Papel Térmico', 'icon': Icons.receipt, 'color': const Color(0xFF6B7280)},
        {'label': 'Electrodos', 'icon': Icons.electrical_services, 'color': const Color(0xFFEF4444)},
        {'label': 'Guantes', 'icon': Icons.back_hand, 'color': const Color(0xFF3B82F6)},
        {'label': 'Sondas Foley', 'icon': Icons.device_hub, 'color': const Color(0xFF10B981)},
      ],
    },
    {
      'key': 'refaccion', 'label': 'Refacciones',
      'icon': Icons.build, 'color': const Color(0xFFEC4899),
      'subs': [
        {'label': 'Transductores', 'icon': Icons.sensors, 'color': const Color(0xFFEC4899)},
        {'label': 'Cables ECG', 'icon': Icons.cable, 'color': const Color(0xFFEF4444)},
        {'label': 'Pantallas', 'icon': Icons.monitor, 'color': const Color(0xFF3B82F6)},
        {'label': 'Baterías', 'icon': Icons.battery_charging_full, 'color': const Color(0xFFF59E0B)},
        {'label': 'Fuentes Poder', 'icon': Icons.power, 'color': const Color(0xFF6366F1)},
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final current = _categories[_selectedIndex];
    final subs = current['subs'] as List;
    final catColor = current['color'] as Color;
    final catLabel = (current['label'] as String).replaceAll('\n', ' ');
    return SafeArea(
      child: Column(children: [
        // ── Header con color de categoría activa ──
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [catColor, catColor.withOpacity(0.75)],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
          ),
          child: Row(children: [
            Icon(current['icon'] as IconData, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(catLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ]),
        ),
        // ── Split panel ──
        Expanded(
          child: Row(children: [
            // Left sidebar con iconos y colores
            Container(
              width: 86,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(2, 0))],
              ),
              child: ListView.builder(
                itemCount: _categories.length,
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final active = i == _selectedIndex;
                  final color = cat['color'] as Color;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                      decoration: BoxDecoration(
                        color: active ? color.withOpacity(0.08) : Colors.white,
                        border: Border(left: BorderSide(
                          color: active ? color : Colors.transparent, width: 3)),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(cat['icon'] as IconData,
                          color: active ? color : Colors.grey.shade400, size: 19),
                        const SizedBox(height: 4),
                        Text(cat['label'] as String,
                          textAlign: TextAlign.center, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9.5,
                            color: active ? color : Colors.grey.shade600,
                            fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            // Right grid con tiles coloridos
            Expanded(
              child: Container(
                color: const Color(0xFFF3F4F6),
                child: GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, childAspectRatio: 0.82,
                    mainAxisSpacing: 10, crossAxisSpacing: 10,
                  ),
                  itemCount: subs.length,
                  itemBuilder: (_, i) {
                    final sub = subs[i] as Map;
                    final subColor = sub['color'] as Color;
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CategoryProductsScreen(
                              categoryKey: current['key'] as String,
                              categoryLabel: catLabel,
                              subcategoryLabel: sub['label'] as String,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: subColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(sub['icon'] as IconData, color: subColor, size: 23),
                          ),
                          const SizedBox(height: 7),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(sub['label'] as String,
                              textAlign: TextAlign.center, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 9.5,
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w500)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════
// TAB 3-5: Placeholders
// ══════════════════════════════════════════

class _CartTab extends StatefulWidget {
  const _CartTab({super.key});
  @override
  State<_CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<_CartTab> {
  List<CartItem> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _loading = true);
    }
    try {
      final items = await CartService.getCartItems();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _subtotal => _items.fold(0, (s, i) => s + i.subtotal);
  double get _iva => _subtotal * 0.16;
  double get _total => _subtotal + _iva;
  int get _totalQty => _items.fold(0, (s, i) => s + i.quantity);

  String _fmt(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '\$$buf.${parts[1]}';
  }

  void _showCheckoutBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => CheckoutSheet(
        total: _total,
        onSuccess: () {
          _load(); // Recargar el carrito
        },
      ),
    );
  }

  void _showQuoteRequestBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _QuoteRequestSheet(
        total: _total,
        onSuccess: () {
          _load(); // Recargar el carrito
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        // Header
        Container(
          width: double.infinity, padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Text('Carrito (${_items.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kPrimary))
            : _items.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.shopping_cart_outlined, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('Tu carrito está vacío', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Explora nuestro catálogo médico', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ]))
              : RefreshIndicator(
                  color: _kPrimary, onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      // Items
                      ..._items.map((item) => _cartItemCard(item)),
                      const SizedBox(height: 16),
                      // Summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(children: [
                          _summaryRow('Subtotal', _fmt(_subtotal)),
                          const SizedBox(height: 6),
                          _summaryRow('IVA 16%', _fmt(_iva)),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                          _summaryRow('Total', _fmt(_total), bold: true, size: 18),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      // Continue button
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _showCheckoutBottomSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary, foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text('Continuar ($_totalQty)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _cartItemCard(CartItem item) {
    final p = item.product;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        // Image
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 70, height: 70,
            child: p?.mainImageUrl != null
              ? Image.network(p!.mainImageUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade100, child: const Icon(Icons.medical_services, color: Colors.grey)))
              : Container(color: Colors.grey.shade100, child: const Icon(Icons.medical_services, color: Colors.grey)),
          ),
        ),
        const SizedBox(width: 10),
        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p?.name ?? 'Producto', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          if (p != null && p.hasDiscount)
            Text(p.formattedOldPrice, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough)),
          Text(p?.formattedPrice ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (p != null) ...[
            const SizedBox(height: 4),
            Text(
              p.stockStatusLabel,
              style: TextStyle(
                fontSize: 10,
                color: p.stockStatusColor,
                fontWeight: p.stockStatusLabel == 'Bajo stock' || p.stockStatusLabel == 'Sin stock'
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
            ),
          ],
        ])),
        // Quantity + delete
        Column(mainAxisSize: MainAxisSize.min, children: [
          // Delete
          GestureDetector(
            onTap: () async {
              setState(() => _loading = true);
              try {
                await CartService.removeFromCart(item.id);
                _load();
              } catch (e) {
                setState(() => _loading = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          // Quantity controls
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () async {
                  if (item.quantity <= 1) return;
                  setState(() {
                    item.quantity--;
                  });
                  try {
                    await CartService.updateQuantity(item.id, item.quantity);
                    _load(showSpinner: false);
                  } catch (e) {
                    setState(() {
                      item.quantity++;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.remove,
                    size: 16,
                    color: item.quantity > 1 ? Colors.black87 : Colors.grey.shade300,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.quantity}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              GestureDetector(
                onTap: () async {
                  if (p != null && p.stock != null && item.quantity >= p.stock!) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Límite de stock alcanzado. No hay más piezas disponibles.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  setState(() {
                    item.quantity++;
                  });
                  try {
                    await CartService.updateQuantity(item.id, item.quantity);
                    _load(showSpinner: false);
                  } catch (e) {
                    setState(() {
                      item.quantity--;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: p != null && p.stock != null && item.quantity >= p.stock!
                        ? Colors.grey.shade300
                        : Colors.black87,
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, double size = 14}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: size, color: Colors.grey.shade700, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      Text(value, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
    ]);
  }
}

// ══════════════════════════════════════════
// TICKETS SCREEN
// ══════════════════════════════════════════
class TicketsListScreen extends StatefulWidget {
  const TicketsListScreen({super.key});
  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends State<TicketsListScreen> with SingleTickerProviderStateMixin {
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
        setState(() { _tickets = data; _loading = false; });
        for (final ticket in data) {
          TicketService.markMessagesAsDelivered(ticket.id);
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<ServiceTicket> get _filtered {
    if (_filterStatus == 'all') return _tickets;
    return _tickets.where((t) => t.status == _filterStatus).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open': return const Color(0xFF3B82F6);
      case 'in_progress': return const Color(0xFFF59E0B);
      case 'resolved': return const Color(0xFF16A34A);
      case 'closed': return Colors.grey;
      case 'cancelled': return const Color(0xFFEF4444);
      default: return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical': return const Color(0xFF7C3AED);
      case 'high': return const Color(0xFFEF4444);
      case 'medium': return const Color(0xFFF59E0B);
      case 'low': return const Color(0xFF16A34A);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(8, 14, 16, 0),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF0D9488)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Icon(Icons.support_agent, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Mis Tickets de Servicio',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2, left: 48),
                    child: Text('${_tickets.length} ticket${_tickets.length != 1 ? 's' : ''} encontrado${_tickets.length != 1 ? 's' : ''}',
                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                // Status tabs
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: Colors.white,
                  indicatorWeight: 2.5,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.55),
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabAlignment: TabAlignment.start,
                  tabs: _statusFilters.map((f) => Tab(text: f.$2)).toList(),
                ),
              ],
            ),
          ),
          // ── Content ─────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: _kPrimary,
              onRefresh: _load,
              child: _loading
                ? const SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: 300,
                      child: Center(child: CircularProgressIndicator(color: _kPrimary)),
                    ),
                  )
                : _error != null
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: _buildError(),
                    )
                  : _filtered.isEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: _buildEmpty(),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _TicketCard(
                          ticket: _filtered[i],
                          color: _statusColor(_filtered[i].status),
                          priorityColor: _priorityColor(_filtered[i].priority),
                        ),
                      ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.assignment_outlined, size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        const Text('Sin tickets en este estado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        Text('Tus reportes de servicio aparecerán aquí.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(_error ?? 'Error al cargar tickets', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
        ],
      ),
    ),
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
              // Ticket ID & status badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(ticket.ticketNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F), fontSize: 13.5)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(ticket.statusLabel,
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(ticket.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              if (ticket.description != null && ticket.description!.isNotEmpty)
                Text(ticket.description!,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metaChip(Icons.flag, ticket.priorityLabel, priorityColor),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(_formatDate(ticket.createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
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
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  String _formatDate(DateTime d) {
    final months = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ══════════════════════════════════════════
// TAB 5: PERFIL — Premium Mobile UI
// ══════════════════════════════════════════
class _ProfileTab extends StatefulWidget {
  final VoidCallback onSignOut;
  const _ProfileTab({required this.onSignOut});
  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  String? _clientId;
  Map<String, dynamic>? _clientData;
  bool _loadingClient = true;

  @override
  void initState() {
    super.initState();
    _loadClientData();
  }

  Future<void> _loadClientData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      _clientId = userId; // Fallback inicial para que los botones de navegación funcionen
    }
    try {
      if (userId == null) { setState(() => _loadingClient = false); return; }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('client_id, clients:clients!profiles_client_id_fkey(business_name, trade_name, contact_name, email, rfc)')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) setState(() {
        _clientId = (profile?['client_id'] as String?) ?? userId;
        _clientData = profile?['clients'] as Map<String, dynamic>?;
        _loadingClient = false;
      });
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
    final initials = name.trim().split(' ')
        .where((w) => w.isNotEmpty).take(2)
        .map((w) => w[0].toUpperCase()).join();
    final businessName = _clientData?['business_name'] as String?;
    final tradeName = _clientData?['trade_name'] as String?;
    final rfc = _clientData?['rfc'] as String?;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // ── Hero header ────────────────────────────
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E3A5F), Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 28),
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: Text(initials.isNotEmpty ? initials : 'U',
                        style: const TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(email,
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75))),
                  // Client badge
                  if (!_loadingClient && businessName != null) ...[  
                    const SizedBox(height: 10),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.business, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(tradeName ?? businessName,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // ── Stats row ─────────────────────────
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        _statCell('Tickets', Icons.support_agent, const Color(0xFF0D9488), () {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TicketsListScreen()));
                        }),
                        _vDivider(),
                        _statCell('Pedidos', Icons.receipt_long, const Color(0xFF3B82F6), () {
                          if (_clientId != null) {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrdersScreen(clientId: _clientId!)));
                          }
                        }),
                        _vDivider(),
                        _statCell('Equipos', Icons.medical_services, const Color(0xFF8B5CF6), () {
                          if (_clientId != null) {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => EquipmentScreen(clientId: _clientId!)));
                          }
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Menu sections ──────────────────────────
            Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Mi Cuenta'),
                  _menuTile(Icons.receipt_long, 'Mis Pedidos', 'Historial de compras', const Color(0xFF3B82F6), () {
                    if (_clientId != null) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrdersScreen(clientId: _clientId!)));
                    }
                  }),
                  _menuTile(Icons.request_quote, 'Cotizaciones', 'Ver presupuestos enviados', const Color(0xFF0D9488), () {
                    if (_clientId != null) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuotesScreen(clientId: _clientId!)));
                    }
                  }),
                  _menuTile(Icons.description, 'Facturación', 'Facturas y datos fiscales', const Color(0xFF8B5CF6), () async {
                    if (_clientId != null) {
                      final updated = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BillingScreen(clientId: _clientId!)));
                      if (updated == true) _loadClientData();
                    }
                  }),
                  _divider(),
                  _sectionLabel('Soporte'),
                  _menuTile(Icons.build_circle, 'Mantenimientos', 'Programa un servicio', const Color(0xFFF59E0B), () {
                    if (_clientId != null) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MaintenanceScreen(clientId: _clientId!)));
                    }
                  }),
                  _menuTile(Icons.headset_mic, 'Ayuda y Soporte', 'Contacta a nuestro equipo', const Color(0xFF3B82F6), () => _showHelpBottomSheet()),
                  _divider(),
                  _sectionLabel('Configuración'),
                  _menuTile(Icons.person_outline, 'Editar Perfil', 'Actualiza tus datos', Colors.grey.shade600, () async {
                    final updated = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                    if (updated == true) {
                      _loadClientData();
                      setState(() {});
                    }
                  }),
                  _menuTile(Icons.notifications_outlined, 'Notificaciones', 'Preferencias de alertas', Colors.grey.shade600, () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                  }),
                  const SizedBox(height: 8),
                  // Sign out
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout, size: 18, color: Colors.red),
                        label: const Text('Cerrar Sesión',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ayuda y Soporte', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
            const SizedBox(height: 8),
            const Text('¿Necesitas ayuda con algún producto, pedido o servicio técnico?', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF25D366), child: Icon(Icons.chat, color: Colors.white)),
              title: const Text('WhatsApp Soporte'),
              subtitle: const Text('+52 999 123 4567'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abriendo WhatsApp...')));
              },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: _kPrimary, child: Icon(Icons.email, color: Colors.white)),
              title: const Text('Correo Electrónico'),
              subtitle: const Text('soporte@gomedical.com.mx'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abriendo cliente de correo...')));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String label, IconData icon, Color color, VoidCallback onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: color.withOpacity(0.10), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        ],
      ),
    ),
  );

  Widget _vDivider() => Container(width: 1, height: 40, color: Colors.grey.shade200);

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(label.toUpperCase(),
      style: TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
  );

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Divider(color: Colors.grey.shade200, height: 1),
  );

  Widget _clientInfoCard(String? businessName, String? tradeName, String? rfc) => Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [const Color(0xFF0D9488).withOpacity(0.07), const Color(0xFF1E3A5F).withOpacity(0.04)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.2)),
    ),
    child: Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF0D9488).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.business_center, color: Color(0xFF0D9488), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(businessName ?? tradeName ?? 'Cliente',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
              if (rfc != null && rfc.isNotEmpty)
                Text('RFC: $rfc', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _menuTile(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) =>
    InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );  
}

// ══════════════════════════════════════════
// CHECKOUT SHEET WIDGET
// ══════════════════════════════════════════
class CheckoutSheet extends StatefulWidget {
  final double total;
  final VoidCallback onSuccess;
  const CheckoutSheet({required this.total, required this.onSuccess});

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  bool _isFinancing = false;
  int _selectedMonths = 3;
  String _paymentMethod = 'transfer';
  String _codiOption = 'mobile';
  bool _codiSimulatedPaid = false;
  bool _codiRequestSent = false;
  int _codiTimerSeconds = 120;
  Timer? _codiTimer;
  bool _loading = false;

  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();
  final _codiPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _codiPhoneController.dispose();
    _notesController.dispose();
    _codiTimer?.cancel();
    super.dispose();
  }

  void _startCodiTimer() {
    _codiTimer?.cancel();
    _codiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_codiTimerSeconds > 0) {
          _codiTimerSeconds--;
        } else {
          _codiRequestSent = false;
          timer.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La solicitud de cobro CoDi ha expirado. Por favor intenta de nuevo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    });
  }

  Future<void> _submit() async {
    if (_paymentMethod == 'card') {
      final cardNo = _cardNumberController.text.replaceAll(' ', '');
      if (cardNo.length < 15 || cardNo.length > 16) {
        _showError('Por favor ingresa un número de tarjeta válido.');
        return;
      }
      if (_cardHolderController.text.trim().isEmpty) {
        _showError('Por favor ingresa el nombre del titular.');
        return;
      }
      if (_cardExpiryController.text.trim().length != 5) {
        _showError('Por favor ingresa una fecha de expiración válida (MM/YY).');
        return;
      }
      if (_cardCvvController.text.trim().length < 3) {
        _showError('Por favor ingresa un CVV válido.');
        return;
      }
    } else if (_paymentMethod == 'codi') {
      if (_codiOption == 'mobile') {
        if (_codiPhoneController.text.length != 10) {
          _showError('Por favor ingresa un número de celular de 10 dígitos.');
          return;
        }
        if (!_codiSimulatedPaid) {
          _showError('Por favor simula la aprobación del pago CoDi en tu celular antes de confirmar.');
          return;
        }
      } else {
        if (!_codiSimulatedPaid) {
          _showError('Por favor simula el escaneo del código QR CoDi antes de confirmar.');
          return;
        }
      }
    }

    setState(() => _loading = true);
    try {
      String finalMethod = '';
      String cardEnding = '';
      if (_isFinancing) {
        finalMethod = 'Financiamiento ($_selectedMonths Meses) - ';
      } else {
        finalMethod = 'Contado - ';
      }

      if (_paymentMethod == 'transfer') {
        finalMethod += 'SPEI';
      } else if (_paymentMethod == 'codi') {
        finalMethod += 'CoDi (${_codiOption == 'mobile' ? 'Celular' : 'QR'})';
      } else if (_paymentMethod == 'card') {
        finalMethod += 'Tarjeta';
        final rawNo = _cardNumberController.text.replaceAll(' ', '');
        cardEnding = ' [Tarjeta terminación: **** ${rawNo.substring(rawNo.length - 4)}]';
      } else if (_paymentMethod == 'cash') {
        finalMethod += 'Efectivo';
      } else {
        finalMethod += 'Otro';
      }

      final notesBuf = StringBuffer();
      notesBuf.write('Método de pago seleccionado: $finalMethod.');
      if (_notesController.text.trim().isNotEmpty) {
        notesBuf.write(' Notas: ${_notesController.text.trim()}');
      }
      if (cardEnding.isNotEmpty) {
        notesBuf.write(' $cardEnding');
      }
      if (_paymentMethod == 'codi' && _codiOption == 'mobile') {
        notesBuf.write(' [CoDi Móvil: ${_codiPhoneController.text}]');
      }

      // Map to PostgreSQL enum payment_method_type
      String dbPaymentMethod = 'other';
      if (_isFinancing) {
        dbPaymentMethod = 'financial';
      } else {
        if (_paymentMethod == 'transfer') {
          dbPaymentMethod = 'spei';
        } else if (_paymentMethod == 'card') {
          dbPaymentMethod = 'card';
        } else if (_paymentMethod == 'cash') {
          dbPaymentMethod = 'cash';
        } else if (_paymentMethod == 'codi') {
          dbPaymentMethod = 'spei';
        }
      }

      final orderId = await CartService.checkout(
        paymentMethod: dbPaymentMethod,
        notes: notesBuf.toString(),
      );

      // Save shipping address to the newly created order
      try {
        final addr = await AddressService.getDefaultAddress();
        if (addr != null) {
          await Supabase.instance.client
              .from('orders')
              .update({'shipping_address': addr.address})
              .eq('id', orderId);
        } else {
          final list = await AddressService.getAddresses();
          if (list.isNotEmpty) {
            await Supabase.instance.client
                .from('orders')
                .update({'shipping_address': list.first.address})
                .eq('id', orderId);
          }
        }
      } catch (addrErr) {
        debugPrint('Aviso al guardar la dirección del pedido: $addrErr');
      }

      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
        widget.onSuccess(); // Trigger cart reload to empty state

        // Show success dialog
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: _kPrimary, size: 28),
                SizedBox(width: 10),
                Text('¡Compra Exitosa!', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Tu orden de compra ha sido generada bajo la modalidad de $finalMethod y el stock de los productos se ha actualizado en tiempo real.\n\nRecibirás una notificación con los detalles de tu compra.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                },
                child: const Text('Aceptar', style: TextStyle(color: _kPrimary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final errMsg = e.toString().replaceAll('Exception: ', '');
        _showError('Error al realizar compra: $errMsg');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Confirmar Compra', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kNavy)),
                          const SizedBox(height: 2),
                          Text('Finaliza tu pedido seleccionando tus opciones de pago.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total a Pagar:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kNavy)),
                        Text(
                          _formatCurrency(widget.total),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Modelo de Pago *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _loading ? null : () => setState(() => _isFinancing = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !_isFinancing ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: !_isFinancing
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : [],
                              ),
                              child: Text(
                                'Pago de Contado',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: !_isFinancing ? _kPrimary : Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: _loading ? null : () => setState(() => _isFinancing = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _isFinancing ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _isFinancing
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : [],
                              ),
                              child: Text(
                                'Financiamiento (Plazos)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _isFinancing ? _kPrimary : Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_isFinancing) ...[
                    const Text('Selecciona el plazo de Financiamiento *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildTermCard(3, 'Sin Intereses')),
                        const SizedBox(width: 8),
                        Expanded(child: _buildTermCard(6, 'Sin Intereses')),
                        const SizedBox(width: 8),
                        Expanded(child: _buildTermCard(12, '10% de Interés')),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  const Text('Selecciona el Método de Pago *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
                  const SizedBox(height: 8),
                  _buildPaymentMethodsGrid(),
                  const SizedBox(height: 20),

                  if (_paymentMethod == 'transfer')
                    _buildSpeiFlow()
                  else if (_paymentMethod == 'codi') ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _codiOption = 'mobile';
                                _codiSimulatedPaid = false;
                                _codiRequestSent = false;
                                _codiTimer?.cancel();
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _codiOption == 'mobile' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'CoDi Móvil (Celular)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _codiOption == 'mobile' ? _kPrimary : Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _codiOption = 'qr';
                                _codiSimulatedPaid = false;
                                _codiRequestSent = false;
                                _codiTimer?.cancel();
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _codiOption == 'qr' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Código QR CoDi',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _codiOption == 'qr' ? _kPrimary : Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_codiOption == 'mobile')
                      _buildCodiMobileFlow()
                    else
                      _buildCodiQrMock(),
                  ] else if (_paymentMethod == 'card')
                    _buildCardFlow()
                  else if (_paymentMethod == 'cash')
                    _buildCashFlow(),

                  const SizedBox(height: 20),

                  const Text('Notas / Instrucciones de Entrega', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      hintText: 'Ej. Entregar por la mañana, o requiere facturar.',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Confirmar y Comprar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermCard(int months, String subtitle) {
    final isSelected = _selectedMonths == months;
    double adjustedTotal = widget.total;
    if (months == 12) {
      adjustedTotal = widget.total * 1.10;
    }
    final monthlyAmount = adjustedTotal / months;

    return GestureDetector(
      onTap: _loading ? null : () => setState(() => _selectedMonths = months),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _kPrimary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kPrimary.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Column(
          children: [
            Text(
              '$months Meses',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? _kPrimary : _kNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatCurrency(monthlyAmount),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? _kPrimary : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9,
                color: isSelected ? _kPrimary : Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildPaymentMethodCard('transfer', 'SPEI / Transf.', Icons.account_balance)),
            const SizedBox(width: 12),
            Expanded(child: _buildPaymentMethodCard('codi', 'CoDi Móvil / QR', Icons.qr_code_scanner)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildPaymentMethodCard('card', 'Tarjeta Créd/Déb', Icons.credit_card)),
            const SizedBox(width: 12),
            Expanded(child: _buildPaymentMethodCard('cash', 'Efectivo / Entrega', Icons.local_shipping)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(String value, String label, IconData icon) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: _loading ? null : () {
        setState(() {
          _paymentMethod = value;
          _codiRequestSent = false;
          _codiSimulatedPaid = false;
          _codiTimer?.cancel();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kPrimary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kPrimary.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? _kPrimary : Colors.grey.shade600, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? _kPrimary : Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeiFlow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance, color: _kPrimary, size: 20),
              SizedBox(width: 8),
              Text(
                'Datos para Transferencia SPEI',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14),
              ),
            ],
          ),
          const Divider(height: 20),
          _buildSpeiRow('Banco:', 'STP (Sistema de Transferencias y Pagos)'),
          _buildSpeiRow('Beneficiario:', 'Go Medical S.A. de C.V.'),
          Row(
            children: [
              Expanded(
                child: _buildSpeiRow('CLABE:', '6461 8000 1234 5678 90'),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: _kPrimary, size: 18),
                tooltip: 'Copiar CLABE',
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: '646180001234567890'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('CLABE copiada al portapapeles'),
                      duration: Duration(seconds: 2),
                      backgroundColor: _kPrimary,
                    ),
                  );
                },
              ),
            ],
          ),
          _buildSpeiRow('Referencia:', 'GOMED-CHECKOUT'),
          const SizedBox(height: 10),
          const Text(
            '* Tu orden será revisada por nuestro equipo una vez que se detecte la transferencia. La verificación suele tomar menos de 10 minutos.',
            style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeiRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          children: [
            TextSpan(text: '$label ', style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildCodiQrMock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: 160,
            height: 160,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: CustomPaint(
              size: const Size(140, 140),
              painter: _QrPainter(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner, color: _kPrimary, size: 16),
              const SizedBox(width: 6),
              Text(
                _codiSimulatedPaid ? '¡Pago detectado con éxito!' : 'Esperando escaneo de código...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _codiSimulatedPaid ? _kGreen : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_codiSimulatedPaid)
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _codiSimulatedPaid = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Simulación: Código QR escaneado y pagado'),
                    backgroundColor: _kGreen,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary.withOpacity(0.1),
                foregroundColor: _kPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Simular Escaneo CoDi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            )
          else
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: _kGreen, size: 20),
                SizedBox(width: 6),
                Text('Pago Confirmado', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCodiMobileFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingresa el número celular asociado a tu cuenta CoDi / App Bancaria para recibir la solicitud de cobro de inmediato.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _codiPhoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          enabled: !_codiRequestSent && !_loading,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Número de Celular (10 dígitos)',
            prefixIcon: const Icon(Icons.phone_android),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            fillColor: Colors.white,
            filled: true,
          ),
        ),
        const SizedBox(height: 12),
        if (!_codiRequestSent)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final phone = _codiPhoneController.text.trim();
                if (phone.length != 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa un número celular de 10 dígitos'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                setState(() {
                  _codiRequestSent = true;
                  _codiTimerSeconds = 120;
                  _codiSimulatedPaid = false;
                });
                _startCodiTimer();
              },
              icon: const Icon(Icons.send_to_mobile),
              label: const Text('Enviar Solicitud de Cobro'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_codiSimulatedPaid)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                      ),
                    const SizedBox(width: 10),
                    Text(
                      _codiSimulatedPaid 
                          ? '¡Pago CoDi recibido y confirmado!'
                          : 'Esperando pago en tu app... (0${_codiTimerSeconds ~/ 60}:${(_codiTimerSeconds % 60).toString().padLeft(2, '0')})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_codiSimulatedPaid)
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _codiSimulatedPaid = true;
                        _codiTimer?.cancel();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Simulación: Solicitud de cobro CoDi aprobada en banco'),
                          backgroundColor: _kGreen,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary.withOpacity(0.1),
                      foregroundColor: _kPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Simular Aprobación Bancaria', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                else
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: _kGreen, size: 20),
                      SizedBox(width: 6),
                      Text('Pago Confirmado', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _codiRequestSent = false;
                  _codiTimer?.cancel();
                });
              },
              child: const Text('Reingresar número o cambiar método', style: TextStyle(fontSize: 11, color: Colors.black45)),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildCardFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVirtualCard(),
        const SizedBox(height: 20),
        const Text(
          'Datos de la Tarjeta',
          style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cardNumberController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _CardNumberFormatter(),
          ],
          decoration: InputDecoration(
            labelText: 'Número de Tarjeta',
            prefixIcon: const Icon(Icons.credit_card),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            fillColor: Colors.white,
            filled: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cardHolderController,
          keyboardType: TextInputType.name,
          decoration: InputDecoration(
            labelText: 'Nombre del Titular',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            fillColor: Colors.white,
            filled: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _cardExpiryController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _CardExpiryFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'Expiración (MM/YY)',
                  prefixIcon: const Icon(Icons.calendar_today),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  fillColor: Colors.white,
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _cardCvvController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'CVV',
                  prefixIcon: const Icon(Icons.lock),
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  fillColor: Colors.white,
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVirtualCard() {
    final numStr = _cardNumberController.text.isEmpty ? '•••• •••• •••• ••••' : _cardNumberController.text;
    final holderStr = _cardHolderController.text.isEmpty ? 'NOMBRE DEL TITULAR' : _cardHolderController.text.toUpperCase();
    final expiryStr = _cardExpiryController.text.isEmpty ? 'MM/YY' : _cardExpiryController.text;
    final cvvStr = _cardCvvController.text.isEmpty ? '•••' : _cardCvvController.text;

    final isVisa = _cardNumberController.text.startsWith('4');
    final isMastercard = _cardNumberController.text.startsWith('5');

    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E3A5F),
            Color(0xFF0D9488),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A5F).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  children: [
                    Positioned(left: 10, top: 0, bottom: 0, child: VerticalDivider(color: Colors.black26, width: 1)),
                    Positioned(left: 20, top: 0, bottom: 0, child: VerticalDivider(color: Colors.black26, width: 1)),
                    Positioned(left: 30, top: 0, bottom: 0, child: VerticalDivider(color: Colors.black26, width: 1)),
                    Positioned(top: 10, left: 0, right: 0, child: Divider(color: Colors.black26, height: 1)),
                    Positioned(top: 20, left: 0, right: 0, child: Divider(color: Colors.black26, height: 1)),
                  ],
                ),
              ),
              Text(
                isVisa ? 'VISA' : (isMastercard ? 'mastercard' : 'CREDIT CARD'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ],
          ),
          Text(
            numStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TITULAR', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      holderStr,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('EXPIRA', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    expiryStr,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('CVV', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    cvvStr,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashFlow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping, color: _kPrimary, size: 20),
              SizedBox(width: 8),
              Text(
                'Pago Contra Entrega / Efectivo',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14),
              ),
            ],
          ),
          Divider(height: 20),
          Text(
            '• Puedes pagar en efectivo o con tarjeta al momento de recibir tus productos.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 6),
          Text(
            '• Nuestros choferes y repartidores cuentan con terminal móvil bancaria.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 6),
          Text(
            '• Si pagas en efectivo, por favor ten listo el importe exacto para agilizar la entrega.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '\$$buf.${parts[1]} MXN';
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(' ', '');
    if (text.length > 16) text = text.substring(0, 16);
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll('/', '');
    if (text.length > 4) text = text.substring(0, 4);
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(text[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87;
    final double finderSize = size.width * 0.25;

    _drawFinderPattern(canvas, const Offset(0, 0), finderSize, paint);
    _drawFinderPattern(canvas, Offset(size.width - finderSize, 0), finderSize, paint);
    _drawFinderPattern(canvas, Offset(0, size.height - finderSize), finderSize, paint);

    final randPattern = [
      [1,0,1,1,0,1,0,1,1,0],
      [0,1,0,0,1,0,1,0,0,1],
      [1,1,0,1,1,0,0,1,1,0],
      [0,0,1,0,0,1,1,0,0,1],
      [1,0,1,1,0,1,0,1,1,0],
      [0,1,0,0,1,0,1,0,0,1],
      [1,1,0,1,1,0,0,1,1,0],
      [0,0,1,0,0,1,1,0,0,1],
      [1,0,1,1,0,1,0,1,1,0],
      [0,1,0,0,1,0,1,0,0,1],
    ];

    final blockSize = size.width / 14;
    final startOffset = finderSize + blockSize;

    for (int r = 0; r < randPattern.length; r++) {
      for (int c = 0; c < randPattern[r].length; c++) {
        if (randPattern[r][c] == 1) {
          canvas.drawRect(
            Rect.fromLTWH(
              startOffset + c * blockSize,
              startOffset + r * blockSize,
              blockSize - 1,
              blockSize - 1,
            ),
            paint,
          );
        }
      }
    }

    for (double x = finderSize + blockSize; x < size.width - finderSize - blockSize; x += blockSize * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, blockSize, blockSize), paint);
      canvas.drawRect(Rect.fromLTWH(0, x, blockSize, blockSize), paint);
    }
  }

  void _drawFinderPattern(Canvas canvas, Offset offset, double size, Paint paint) {
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, size, size), paint);
    final whitePaint = Paint()..color = Colors.white;
    final double innerWhiteStart = size * 0.15;
    final double innerWhiteSize = size * 0.7;
    canvas.drawRect(
      Rect.fromLTWH(offset.dx + innerWhiteStart, offset.dy + innerWhiteStart, innerWhiteSize, innerWhiteSize),
      whitePaint,
    );
    final double innerBlackStart = size * 0.3;
    final double innerBlackSize = size * 0.4;
    canvas.drawRect(
      Rect.fromLTWH(offset.dx + innerBlackStart, offset.dy + innerBlackStart, innerBlackSize, innerBlackSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════
// QUOTE REQUEST SHEET WIDGET
// ══════════════════════════════════════════
class _QuoteRequestSheet extends StatefulWidget {
  final double total;
  final VoidCallback onSuccess;
  const _QuoteRequestSheet({required this.total, required this.onSuccess});

  @override
  State<_QuoteRequestSheet> createState() => _QuoteRequestSheetState();
}

class _QuoteRequestSheetState extends State<_QuoteRequestSheet> {
  final _notesController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await CartService.requestQuote(
        notes: _notesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
        widget.onSuccess(); // Trigger cart reload to empty state

        // Show success dialog
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: _kPrimary, size: 28),
                SizedBox(width: 10),
                Text('¡Solicitud Enviada!', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'Tu solicitud de cotización ha sido enviada con éxito.\n\nEl equipo administrativo revisará tu solicitud y se pondrá en contacto contigo a la brevedad. Puedes realizar el seguimiento desde Perfil > Cotizaciones.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                },
                child: const Text('Aceptar', style: TextStyle(color: _kPrimary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final errMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al solicitar cotización: $errMsg'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Solicitar Cotización', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kNavy)),
                          const SizedBox(height: 2),
                          Text('Envía tu solicitud y un ejecutivo se pondrá en contacto contigo.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Importe Estimado:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kNavy)),
                        Text(
                          _formatCurrency(widget.total),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Notas / Instrucciones Especiales', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 4,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      hintText: 'Ej. Solicito descuento por volumen, o requiero entrega en cierta fecha.',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Confirmar y Solicitar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '\$$buf.${parts[1]} MXN';
  }
}

// ══════════════════════════════════════════
// DETAIL SCREEN: TICKET DE SERVICIO
// ══════════════════════════════════════════
class TicketDetailScreen extends StatefulWidget {
  final String ticketId;

  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  ServiceTicket? _ticket;
  bool _loading = true;
  String? _error;
  List<TicketMessage> _messages = [];
  bool _loadingMessages = true;
  bool _uploadingFile = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _chatChannel;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadTicket() async {
    if (!mounted) return;
    setState(() {
      if (_ticket == null) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final ticket = await TicketService.getTicketById(widget.ticketId);
      if (mounted) {
        setState(() {
          _ticket = ticket;
          _loading = false;
        });
        _loadMessages();
        _subscribeToChat();
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

  Future<void> _loadMessages() async {
    try {
      final msgs = await TicketService.getTicketMessages(widget.ticketId);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loadingMessages = false;
        });
        _scrollToBottom();
        TicketService.markMessagesAsRead(widget.ticketId);
      }
    } catch (e) {
      debugPrint('Error loading chat messages: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _subscribeToChat() {
    _chatChannel?.unsubscribe();
    final client = Supabase.instance.client;

    _chatChannel = client
        .channel('public:service_ticket_messages:ticket_id=eq.${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: widget.ticketId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            if (record.isEmpty) return;
            final newId = record['id'] as String?;
            if (newId != null) {
              final index = _messages.indexWhere((m) => m.id == newId);

              final res = await client
                  .from('service_ticket_messages')
                  .select('*, profiles:sender_profile_id(full_name)')
                  .eq('id', newId)
                  .maybeSingle();

              if (res != null && mounted) {
                final msg = TicketMessage.fromJson(res);
                if (!msg.isInternal) {
                  setState(() {
                    if (index == -1) {
                      _messages.add(msg);
                      _scrollToBottom();

                      // Si el mensaje es recibido del soporte, marcar como leído
                      if (msg.senderType != 'client') {
                        TicketService.markMessagesAsRead(widget.ticketId);
                      }
                    } else {
                      _messages[index] = msg;
                    }
                  });
                }
              }
            }
          },
        );

    _chatChannel!.subscribe();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open': return const Color(0xFF3B82F6);
      case 'in_progress': return const Color(0xFFF59E0B);
      case 'resolved': return const Color(0xFF16A34A);
      case 'closed': return Colors.grey;
      case 'cancelled': return const Color(0xFFEF4444);
      default: return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical': return const Color(0xFF7C3AED);
      case 'high': return const Color(0xFFEF4444);
      case 'medium': return const Color(0xFFF59E0B);
      case 'low': return const Color(0xFF16A34A);
      default: return Colors.grey;
    }
  }

  String _formatDate(DateTime d) {
    final months = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year} - $hour:$minute hrs';
  }

  bool get _canChat {
    final status = _ticket?.status.toLowerCase();
    return status != 'resolved' && status != 'closed' && status != 'cancelled' && status != 'canceled';
  }

  Widget _buildChatCard(ServiceTicket ticket) {
    final curUserId = Supabase.instance.client.auth.currentUser?.id;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, color: _kPrimary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Chat de Soporte Técnico',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _kNavy,
                  ),
                ),
                const Spacer(),
                if (_loadingMessages)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            height: 350,
            color: Colors.grey.shade50,
            child: _loadingMessages
                ? const Center(child: CircularProgressIndicator(color: _kPrimary))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 36, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'Sin mensajes aún',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Envía un mensaje para comunicarte con soporte.',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg.senderType == 'client' && msg.senderProfileId == curUserId;
                          final hasImage = msg.attachmentUrl != null && msg.attachmentUrl!.isNotEmpty;
                          final hasCaption = msg.message.isNotEmpty && msg.message != 'Envío de foto';

                          // ── Tiempo + palomitas ────────────────────────
                          Widget timeRow({bool light = true}) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    color: light
                                        ? Colors.white.withOpacity(0.75)
                                        : Colors.grey.shade400,
                                    fontSize: 9,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 3),
                                  Icon(
                                    (msg.readAt != null || msg.deliveredAt != null)
                                        ? Icons.done_all
                                        : Icons.done,
                                    size: 11,
                                    color: msg.readAt != null
                                        ? const Color(0xFF00E5FF)
                                        : (msg.deliveredAt != null
                                            ? Colors.white.withOpacity(0.65)
                                            : Colors.white.withOpacity(0.4)),
                                  ),
                                ],
                              ],
                            );
                          }

                          // ── Nombre del remitente (lado soporte) ───────
                          Widget? senderLabel = !isMe
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    msg.senderName ?? 'Soporte',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _kPrimary,
                                    ),
                                  ),
                                )
                              : null;

                          // Bordes de la burbuja
                          BorderRadius bubbleRadius = BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: isMe
                                ? const Radius.circular(14)
                                : const Radius.circular(0),
                            bottomRight: isMe
                                ? const Radius.circular(0)
                                : const Radius.circular(14),
                          );

                          // ── Burbuja CON imagen ────────────────────────
                          if (hasImage) {
                            return Align(
                              alignment:
                                  isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.72,
                                  minWidth: 160,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe ? _kPrimary : Colors.white,
                                  borderRadius: bubbleRadius,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  border: isMe
                                      ? null
                                      : Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Nombre (soporte)
                                    if (senderLabel != null)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 8, 10, 4),
                                        child: senderLabel,
                                      ),

                                    // Imagen sin padding (llena el ancho)
                                    GestureDetector(
                                      onTap: () async {
                                        final uri =
                                            Uri.parse(msg.attachmentUrl!);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.only(
                                          topLeft: senderLabel == null
                                              ? bubbleRadius.topLeft
                                              : Radius.zero,
                                          topRight: senderLabel == null
                                              ? bubbleRadius.topRight
                                              : Radius.zero,
                                          bottomLeft: (!hasCaption)
                                              ? bubbleRadius.bottomLeft
                                              : Radius.zero,
                                          bottomRight: (!hasCaption)
                                              ? bubbleRadius.bottomRight
                                              : Radius.zero,
                                        ),
                                        child: Image.network(
                                          msg.attachmentUrl!,
                                          width: double.infinity,
                                          height: 220,
                                          fit: BoxFit.cover,
                                          loadingBuilder:
                                              (context, child, loadingProgress) {
                                            if (loadingProgress == null) {
                                              return child;
                                            }
                                            final total = loadingProgress
                                                .expectedTotalBytes;
                                            final loaded = loadingProgress
                                                .cumulativeBytesLoaded;
                                            final pct = total != null
                                                ? loaded / total
                                                : null;
                                            return Container(
                                              width: double.infinity,
                                              height: 220,
                                              color: isMe
                                                  ? _kPrimary.withOpacity(0.5)
                                                  : Colors.grey.shade200,
                                              child: Center(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 28,
                                                      height: 28,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2.5,
                                                        value: pct,
                                                        color: isMe
                                                            ? Colors.white
                                                            : _kPrimary,
                                                      ),
                                                    ),
                                                    if (pct != null) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        '${(pct * 100).toInt()}%',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: isMe
                                                              ? Colors.white70
                                                              : Colors
                                                                  .grey.shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                          errorBuilder: (context, error, _) {
                                            return Container(
                                              width: double.infinity,
                                              height: 220,
                                              color: Colors.grey.shade200,
                                              child: const Center(
                                                child: Icon(
                                                    Icons.broken_image_outlined,
                                                    color: Colors.grey,
                                                    size: 32),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),

                                    // Franja inferior: texto + hora
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          10, 6, 10, 7),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          if (hasCaption)
                                            Expanded(
                                              child: Text(
                                                msg.message,
                                                style: TextStyle(
                                                  color: isMe
                                                      ? Colors.white
                                                      : Colors.black87,
                                                  fontSize: 13,
                                                  height: 1.3,
                                                ),
                                              ),
                                            )
                                          else
                                            const Spacer(),
                                          const SizedBox(width: 6),
                                          timeRow(light: isMe),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          // ── Burbuja SOLO texto ────────────────────────
                          return Align(
                            alignment:
                                isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.72,
                              ),
                              decoration: BoxDecoration(
                                color: isMe ? _kPrimary : Colors.white,
                                borderRadius: bubbleRadius,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                border: isMe
                                    ? null
                                    : Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (senderLabel != null) senderLabel,
                                  Text(
                                    msg.message,
                                    style: TextStyle(
                                      color:
                                          isMe ? Colors.white : Colors.black87,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: timeRow(light: isMe),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const Divider(height: 1),
          if (_canChat)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: _uploadingFile
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                          )
                        : const Icon(Icons.photo_library_outlined, color: Colors.grey),
                    onPressed: _uploadingFile ? null : _pickAndUploadImage,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: _kPrimary),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Ticket resuelto/cerrado. Chat archivado.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await TicketService.sendTicketMessage(widget.ticketId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar mensaje: $e'), backgroundColor: _kRed),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingFile) return;
    setState(() {
      _uploadingFile = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _uploadingFile = false;
        });
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _uploadingFile = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudieron leer los bytes del archivo.'), backgroundColor: _kRed),
          );
        }
        return;
      }

      await _showImagePreviewDialog(bytes, file.name);
    } catch (e) {
      setState(() {
        _uploadingFile = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e'), backgroundColor: _kRed),
        );
      }
    }
  }

  Future<void> _showImagePreviewDialog(Uint8List bytes, String fileName) async {
    final captionController = TextEditingController();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (context) {
        bool isSent = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Imagen a pantalla completa ────────────────────────
                  InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),

                  // ── Barra superior con degradado ──────────────────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.65),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 26),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const Expanded(
                                child: Text(
                                  'Enviar foto',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(color: Colors.black54, blurRadius: 4),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Barra inferior con campo de texto y botón enviar ──
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.80),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: captionController,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    maxLines: 4,
                                    minLines: 1,
                                    decoration: InputDecoration(
                                      hintText: 'Añadir un comentario...',
                                      hintStyle: TextStyle(
                                        color: Colors.white.withOpacity(0.55),
                                        fontSize: 14,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: isSent
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          isSent = true;
                                        });
                                        Navigator.pop(context, {
                                          'caption': captionController.text.trim(),
                                        });
                                      },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: isSent ? Colors.grey.shade600 : _kPrimary,
                                    shape: BoxShape.circle,
                                    boxShadow: isSent
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: _kPrimary.withOpacity(0.5),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                  ),
                                  child: Icon(
                                    Icons.send_rounded,
                                    color: isSent ? Colors.white.withOpacity(0.5) : Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      final caption = result['caption'] ?? '';
      await _uploadAndSendImage(bytes, fileName, caption);
    } else {
      setState(() {
        _uploadingFile = false;
      });
    }
  }

  Future<void> _uploadAndSendImage(Uint8List bytes, String fileName, String caption) async {
    try {
      final attachmentUrl = await TicketService.uploadChatAttachment(
        widget.ticketId,
        fileName,
        bytes,
      );

      await TicketService.sendTicketMessage(
        widget.ticketId,
        caption,
        attachmentUrl: attachmentUrl,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir imagen: $e'), backgroundColor: _kRed),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingFile = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(
          ticket != null ? ticket.ticketNumber : 'Detalle de Ticket',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF0D9488)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: RefreshIndicator(
          color: _kPrimary,
          onRefresh: _loadTicket,
          child: _loading
              ? const SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: 400,
                    child: Center(child: CircularProgressIndicator(color: _kPrimary)),
                  ),
                )
              : _error != null
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: _buildErrorView(),
                    )
                  : ticket == null
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: _buildNotFoundView(),
                        )
                      : LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth > 900;

                          if (isDesktop) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildHeaderCard(ticket),
                                        const SizedBox(height: 16),
                                        _buildInfoCard(
                                          title: 'Información General',
                                          icon: Icons.info_outline,
                                          children: _buildGeneralInfoFields(ticket),
                                        ),
                                        const SizedBox(height: 16),
                                        _buildInfoCard(
                                          title: 'Detalle del Reporte',
                                          icon: Icons.description_outlined,
                                          children: [
                                            _buildDetailSection(
                                              label: 'Asunto / Título',
                                              value: ticket.title,
                                            ),
                                            const SizedBox(height: 16),
                                            _buildDetailSection(
                                              label: 'Descripción de la Falla',
                                              value: ticket.description ?? 'Sin descripción proporcionada.',
                                              isDescription: true,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 4,
                                    child: _buildChatCard(ticket),
                                  ),
                                ],
                              ),
                            );
                          }

                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeaderCard(ticket),
                                const SizedBox(height: 16),
                                _buildInfoCard(
                                  title: 'Información General',
                                  icon: Icons.info_outline,
                                  children: _buildGeneralInfoFields(ticket),
                                ),
                                const SizedBox(height: 16),
                                _buildInfoCard(
                                  title: 'Detalle del Reporte',
                                  icon: Icons.description_outlined,
                                  children: [
                                    _buildDetailSection(
                                      label: 'Asunto / Título',
                                      value: ticket.title,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildDetailSection(
                                      label: 'Descripción de la Falla',
                                      value: ticket.description ?? 'Sin descripción proporcionada.',
                                      isDescription: true,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildChatCard(ticket),
                              ],
                            ),
                          );
                        }
                      ),
      ),
    );
  }

  Widget _buildHeaderCard(ServiceTicket ticket) {
    final statusColor = _statusColor(ticket.status);
    final priorityColor = _priorityColor(ticket.priority);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ticket.ticketNumber,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  ticket.statusLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Prioridad: ',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: priorityColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ticket.priorityLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: priorityColor,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                _formatDate(ticket.createdAt).split(' - ').first,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGeneralInfoFields(ServiceTicket ticket) {
    final hasTechnician = ticket.assignedTechnicianCustomName != null && ticket.assignedTechnicianCustomName!.isNotEmpty;
    final String techValue = hasTechnician ? ticket.assignedTechnicianCustomName! : 'Por asignar';

    final fields = <Widget>[
      _buildDetailRow(
        label: 'Cliente',
        value: ticket.clientName ?? 'No especificado',
        icon: Icons.business,
      ),
      _buildDetailRow(
        label: 'Tipo de Servicio',
        value: ticket.typeLabel,
        icon: Icons.build_circle_outlined,
      ),
      _buildDetailRow(
        label: 'Fecha de Reporte',
        value: _formatDate(ticket.createdAt),
        icon: Icons.calendar_today_outlined,
      ),
      _buildDetailRow(
        label: 'Última Actualización',
        value: ticket.updatedAt != null ? _formatDate(ticket.updatedAt!) : 'Sin actualizaciones',
        icon: Icons.update,
      ),
      _buildDetailRow(
        label: 'Técnico Asignado',
        value: techValue,
        icon: Icons.person_outline,
        valueColor: !hasTechnician ? Colors.orange.shade800 : null,
      ),
    ];

    // Scheduled date/time
    if (ticket.scheduledStartAt != null) {
      fields.add(_buildDetailRow(
        label: 'Fecha Programada',
        value: _formatDate(ticket.scheduledStartAt!),
        icon: Icons.alarm,
        valueColor: const Color(0xFF16A34A),
      ));
    } else if (ticket.requestedServiceDate != null && ticket.requestedServiceDate!.isNotEmpty) {
      fields.add(_buildDetailRow(
        label: 'Fecha de Servicio Solicitada',
        value: ticket.requestedServiceDate!,
        icon: Icons.calendar_today,
      ));
    }

    // Service address / location
    if (ticket.serviceAddress != null && ticket.serviceAddress!.isNotEmpty) {
      final cityPart = ticket.serviceCity != null && ticket.serviceCity!.isNotEmpty ? ', ${ticket.serviceCity}' : '';
      final statePart = ticket.serviceState != null && ticket.serviceState!.isNotEmpty ? ', ${ticket.serviceState}' : '';
      fields.add(_buildDetailRow(
        label: 'Dirección del Servicio',
        value: '${ticket.serviceAddress}$cityPart$statePart',
        icon: Icons.location_on_outlined,
      ));
    }

    if (ticket.serviceLocation != null && ticket.serviceLocation!.isNotEmpty) {
      fields.add(_buildDetailRow(
        label: 'Área / Ubicación',
        value: ticket.serviceLocation!,
        icon: Icons.place_outlined,
      ));
    }

    // Contact info
    if (ticket.contactName != null && ticket.contactName!.isNotEmpty) {
      fields.add(_buildDetailRow(
        label: 'Responsable',
        value: ticket.contactName!,
        icon: Icons.contacts_outlined,
      ));
    }
    if (ticket.contactPhone != null && ticket.contactPhone!.isNotEmpty) {
      fields.add(_buildDetailRow(
        label: 'Teléfono Contacto',
        value: ticket.contactPhone!,
        icon: Icons.phone_android_outlined,
      ));
    }
    if (ticket.contactEmail != null && ticket.contactEmail!.isNotEmpty) {
      fields.add(_buildDetailRow(
        label: 'Email Contacto',
        value: ticket.contactEmail!,
        icon: Icons.email_outlined,
      ));
    }

    // Error code
    if (ticket.errorCode != null && ticket.errorCode!.isNotEmpty) {
      fields.add(_buildDetailRow(
        label: 'Código de Error',
        value: ticket.errorCode!,
        icon: Icons.bug_report_outlined,
        valueColor: const Color(0xFFEF4444),
      ));
    }

    return fields;
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _kNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection({
    required String label,
    required String value,
    bool isDescription = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              color: _kNavy,
              height: isDescription ? 1.4 : 1.2,
              fontWeight: isDescription ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Error al cargar el detalle del ticket',
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTicket,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No se encontró el ticket',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'El ticket de servicio solicitado podría no existir o no tener permisos para verlo.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
