import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/product.dart';
import '../../../services/product_service.dart';
import '../../../services/address_service.dart';
import '../../../services/quote_service.dart';
import '../../../services/notification_service.dart';
import '../../product/search_screen.dart';
import '../../product/quote_cart_screen.dart';
import '../../profile/notifications_screen.dart';
import '../address_picker_screen.dart';
import '../home_screen.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/product_card.dart';
import '../widgets/abandoned_cart_dialog.dart';
import '../widgets/shimmer_card.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);

class MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class MarketplaceTab extends StatefulWidget {
  const MarketplaceTab({super.key});
  @override
  State<MarketplaceTab> createState() => MarketplaceTabState();
}

class MarketplaceTabState extends State<MarketplaceTab> {
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
    load();
    _loadLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAbandonedCart());
  }

  Future<void> _checkAbandonedCart() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final result = await Supabase.instance.client
          .from('carts')
          .select('id, updated_at, followup_status')
          .eq('client_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (result == null || !mounted) return;

      final followup = result['followup_status'] as String?;
      if (followup == 'recovered' || followup == 'dismissed') return;

      final updatedAt = DateTime.tryParse(result['updated_at'] ?? '');
      if (updatedAt == null) return;

      final diff = DateTime.now().toUtc().difference(updatedAt.toUtc());
      if (diff.inHours < 5) return;

      final cartId = result['id'] as String;
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AbandonedCartDialog(
          cartId: cartId,
          onGoToCart: () {
            Navigator.of(context).pop();
            HomeScreen.showTab(2);
          },
          onDismiss: () => Navigator.of(context).pop(),
        ),
      );
    } catch (_) {}
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

  Future<void> load({bool isLiveSearch = false}) async {
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
    load();
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
                  color: color.withValues(alpha: 0.08),
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
          behavior: MouseDragScrollBehavior(),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length,
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: SizedBox(
                  width: 185,
                  child: ProductCard(product: list[i]),
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
    final topPadding = MediaQuery.of(context).padding.top;
    return RefreshIndicator(
      color: _kPrimary,
      edgeOffset: topPadding + 90, // Emerge justo debajo de la barra verde
      onRefresh: load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverToBoxAdapter(child: _banner()),
          SliverToBoxAdapter(child: _quickCats()),
          
          if (_loading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 230,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const ShimmerCard(),
                  childCount: 4,
                ),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
              const SizedBox(height: 8),
              TextButton(onPressed: load, child: const Text('Reintentar')),
            ])))
          else if (_products.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('No hay productos en esta categoría')))
          else ...[
            if (isHomeLanding) ...[
              if (promoProducts.isNotEmpty) ...[
                _sectionHeader(Icons.local_offer, 'Promociones del Día', const Color(0xFFEF4444), () {
                  setState(() {
                    _activeCategory = null;
                    _searchQuery = '';
                  });
                }),
                _horizontalProductList(promoProducts),
              ],

              if (equiposProducts.isNotEmpty) ...[
                _sectionHeader(Icons.medical_services, 'Equipos Médicos', const Color(0xFF0D9488), () {
                  _setCategory('equipo_medico');
                }),
                _horizontalProductList(equiposProducts),
              ],

              if (ultrasoundProducts.isNotEmpty) ...[
                _sectionHeader(Icons.monitor_heart, 'Ultrasonido y Diagnóstico', const Color(0xFF3B82F6), () {
                  _setCategory('ultrasonido_humano');
                }),
                _horizontalProductList(ultrasoundProducts),
              ],

              if (consumiblesProducts.isNotEmpty) ...[
                _sectionHeader(Icons.water_drop, 'Consumibles y Refacciones', const Color(0xFF0EA5E9), () {
                  _setCategory('consumible');
                }),
                _horizontalProductList(consumiblesProducts),
              ],

              if (serviciosProducts.isNotEmpty) ...[
                _sectionHeader(Icons.settings_suggest, 'Servicios de Mantenimiento', const Color(0xFF8B5CF6), () {
                  _setCategory('servicio');
                }),
                _horizontalProductList(serviciosProducts),
              ],
              
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ] else ...[
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
                    (ctx, i) => ProductCard(product: _products[i]),
                    childCount: _products.length,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header() => Container(
    color: _kPrimary,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
                margin: const EdgeInsets.only(top: 4, bottom: 0),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
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
      ),
    ),
  );

  Widget _banner() => const BannerCarousel();

  Widget _quickCats() {
    final cats = [
      {'icon': Icons.medical_services, 'label': 'Equipos', 'cat': 'equipo_medico', 'color': const Color(0xFF0D9488)},
      {'icon': Icons.monitor_heart, 'label': 'Ultrasonido', 'cat': 'ultrasonido_humano', 'color': const Color(0xFF3B82F6)},
      {'icon': Icons.water_drop, 'label': 'Consumibles', 'cat': 'consumible', 'color': const Color(0xFF0EA5E9)},
      {'icon': Icons.build, 'label': 'Refacciones', 'cat': 'refaccion', 'color': const Color(0xFFEC4899)},
      {'icon': Icons.settings_suggest, 'label': 'Servicios', 'cat': 'servicio', 'color': const Color(0xFF8B5CF6)},
    ];
    return SizedBox(
      height: 90,
      child: ScrollConfiguration(
        behavior: MouseDragScrollBehavior(),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
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
                      color: active ? color : color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: active ? null : Border.all(color: color.withValues(alpha: 0.25), width: 1),
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
