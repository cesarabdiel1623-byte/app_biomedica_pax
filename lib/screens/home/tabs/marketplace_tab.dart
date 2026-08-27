import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/catalog_category.dart';
import '../../../models/product.dart';
import '../../../services/catalog_service.dart';
import '../../../services/product_service.dart';
import '../../../services/address_service.dart';
import '../../../services/auth_identity_service.dart';
import '../../../services/quote_service.dart';
import '../../../services/notification_service.dart';
import '../../../utils/ui_helpers.dart';
import '../../product/category_products_screen.dart';
import '../../product/category_catalog_screen.dart';
import '../../product/search_screen.dart';
import '../../product/quote_cart_screen.dart';
import '../../product/promotion_products_screen.dart';
import '../../profile/notifications_screen.dart';
import '../address_picker_screen.dart';
import '../home_screen.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/product_card.dart';
import '../widgets/promotion_cards_section.dart';
import '../widgets/abandoned_cart_dialog.dart';
import '../../../widgets/load_error_state.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);

class MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class MarketplaceTab extends StatefulWidget {
  const MarketplaceTab({super.key, this.onInitialLoadComplete});

  final VoidCallback? onInitialLoadComplete;

  @override
  State<MarketplaceTab> createState() => MarketplaceTabState();
}

class MarketplaceTabState extends State<MarketplaceTab> {
  List<Product> _products = [];
  List<CatalogCategory> _catalogCategories = const [];
  bool _loading = true;
  bool _refreshingHome = false;
  String? _error;
  String? _activeCategory;
  String _currentLocation = 'Selecciona tu ubicación';
  int _bannerRefreshToken = 0;
  bool _productsInitialLoadDone = false;
  bool _categoriesInitialLoadDone = false;
  bool _locationInitialLoadDone = false;
  bool _bannerInitialLoadDone = false;
  bool _cardsInitialLoadDone = false;
  bool _initialLoadReported = false;
  final _searchController = TextEditingController();
  final String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    load();
    _loadCatalogCategories();
    _loadLocation();
  }

  Future<void> _checkAbandonedCart() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final clientId =
          await AuthIdentityService.getEffectiveClientId() ?? userId;

      final result = await Supabase.instance.client
          .from('carts')
          .select('id, updated_at, followup_status')
          .eq('client_id', clientId)
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
        setState(() => _currentLocation = addr.deliveryLabel);
      }
    } catch (_) {
      // La ubicación no debe bloquear el inicio.
    } finally {
      _locationInitialLoadDone = true;
      _reportInitialLoadIfReady();
    }
  }

  Future<void> _loadCatalogCategories() async {
    try {
      final categories = await CatalogService.getCategories().timeout(
        const Duration(seconds: 30),
      );
      if (mounted) {
        setState(() => _catalogCategories = categories);
      }
    } catch (error) {
      debugPrint('Error al cargar categorías del inicio: $error');
      if (mounted && UiHelpers.isNetworkError(error)) {
        setState(() => _error = error.toString());
      }
    } finally {
      _categoriesInitialLoadDone = true;
      _reportInitialLoadIfReady();
    }
  }

  void _reportInitialLoadIfReady() {
    if (!mounted ||
        _initialLoadReported ||
        !_productsInitialLoadDone ||
        !_categoriesInitialLoadDone ||
        !_locationInitialLoadDone ||
        !_bannerInitialLoadDone ||
        !_cardsInitialLoadDone) {
      return;
    }
    _initialLoadReported = true;
    widget.onInitialLoadComplete?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAbandonedCart());
  }

  void _markBannerInitialLoadDone() {
    if (_bannerInitialLoadDone) return;
    _bannerInitialLoadDone = true;
    _reportInitialLoadIfReady();
  }

  void _markCardsInitialLoadDone() {
    if (_cardsInitialLoadDone) return;
    _cardsInitialLoadDone = true;
    _reportInitialLoadIfReady();
  }

  Future<void> _refreshHome() async {
    if (_refreshingHome) return;
    setState(() {
      _refreshingHome = true;
      _bannerRefreshToken++;
    });
    try {
      await load(showSpinner: false);
    } finally {
      if (mounted) {
        setState(() => _refreshingHome = false);
      }
    }
  }

  Future<void> load({
    bool isLiveSearch = false,
    bool showSpinner = true,
  }) async {
    try {
      if (showSpinner && !isLiveSearch) {
        setState(() {
          _loading = true;
          _error = null;
        });
      } else if (_error != null) {
        setState(() => _error = null);
      }
      CatalogCategory? selectedCategory;
      for (final category in _catalogCategories) {
        if (category.productCategoryKey == _activeCategory) {
          selectedCategory = category;
          break;
        }
      }

      Future<List<Product>> fetchFuture;
      if (_searchQuery.isNotEmpty) {
        fetchFuture = ProductService.searchProducts(_searchQuery).then((
          products,
        ) {
          if (_activeCategory != null) {
            return products.where((item) {
              if (selectedCategory != null) {
                return item.categoryId == selectedCategory.id ||
                    (item.categoryId == null &&
                        item.category == selectedCategory.productCategoryKey);
              }
              return item.category == _activeCategory;
            }).toList();
          }
          return products;
        });
      } else {
        fetchFuture = selectedCategory != null
            ? ProductService.getProductsByCatalogCategory(
                categoryId: selectedCategory.id,
                legacyCategory: selectedCategory.productCategoryKey,
              )
            : ProductService.getAllProducts(category: _activeCategory);
      }

      final results = await Future.wait([
        fetchFuture.timeout(const Duration(seconds: 30)),
        _loadCatalogCategories(),
        if (showSpinner && !isLiveSearch)
          Future.delayed(const Duration(seconds: 3)),
      ]);

      final p = results[0] as List<Product>;
      if (!_productsInitialLoadDone && mounted) {
        await _precacheInitialProductImages(p);
      }
      if (mounted) {
        setState(() {
          _products = p;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } finally {
      _productsInitialLoadDone = true;
      _reportInitialLoadIfReady();
    }
  }

  Future<void> _precacheInitialProductImages(List<Product> products) async {
    final urls = products
        .map(
          (product) => UiHelpers.sanitizeTrustedRemoteUrl(product.mainImageUrl),
        )
        .whereType<String>()
        .toSet()
        .take(2);

    await Future.wait(
      urls.map((url) async {
        try {
          await precacheImage(
            NetworkImage(url),
            context,
          ).timeout(const Duration(seconds: 2));
        } catch (error) {
          debugPrint('[MarketplaceTab] No se pudo precargar producto: $error');
        }
      }),
    );
  }

  void _setCategory(String? cat) {
    setState(() => _activeCategory = _activeCategory == cat ? null : cat);
    load();
  }

  Widget _sectionHeader(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
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
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
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
        height: 336,
        child: ScrollConfiguration(
          behavior: MouseDragScrollBehavior(),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
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
    final isOffline = _error != null && UiHelpers.isNetworkError(_error);
    final promoProducts = _products.where((p) => p.hasDiscount).toList();
    final categorySections = _catalogCategories
        .map(
          (category) => (
            category: category,
            products: _products
                .where(
                  (product) =>
                      product.categoryId == category.id ||
                      (product.categoryId == null &&
                          product.category == category.productCategoryKey),
                )
                .toList(),
          ),
        )
        .where((section) => section.products.isNotEmpty)
        .toList();

    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: _loading
                ? const _MarketplaceLoadingBody()
                : isOffline
                ? RefreshIndicator(
                    color: _kPrimary,
                    backgroundColor: Colors.white,
                    displacement: 42,
                    triggerMode: RefreshIndicatorTriggerMode.onEdge,
                    onRefresh: _refreshHome,
                    child: ListView(
                      physics: UiHelpers.refreshScrollPhysics,
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height - 240,
                          child: LoadErrorState(
                            error: _error,
                            onRetry: _refreshHome,
                            genericTitle: 'Error al cargar productos',
                            genericMessage:
                                'No pudimos cargar el catálogo por el momento.',
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: _kPrimary,
                    backgroundColor: Colors.white,
                    displacement: 42,
                    triggerMode: RefreshIndicatorTriggerMode.onEdge,
                    onRefresh: _refreshHome,
                    child: CustomScrollView(
                      physics: UiHelpers.refreshScrollPhysics,
                      slivers: [
                        SliverToBoxAdapter(
                          child: ColoredBox(
                            color: Colors.white,
                            child: BannerCarousel(
                              refreshToken: _bannerRefreshToken,
                              onInitialLoadComplete: _markBannerInitialLoadDone,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ColoredBox(
                            color: Colors.white,
                            child: PromotionCardsSection(
                              refreshToken: _bannerRefreshToken,
                              onInitialLoadComplete: _markCardsInitialLoadDone,
                            ),
                          ),
                        ),
                        if (_hasQuickCategories())
                          SliverToBoxAdapter(child: _quickCats()),
                        if (_error != null)
                          SliverFillRemaining(
                            child: LoadErrorState(
                              error: _error,
                              onRetry: _refreshHome,
                              genericTitle: 'Error al cargar productos',
                              genericMessage:
                                  'No pudimos cargar el catálogo por el momento.',
                            ),
                          )
                        else if (_products.isEmpty)
                          const SliverFillRemaining(
                            child: Center(
                              child: Text('No hay productos en esta categoría'),
                            ),
                          )
                        else ...[
                          if (isHomeLanding) ...[
                            if (promoProducts.isNotEmpty) ...[
                              _sectionHeader(
                                Icons.local_offer,
                                'Promociones del Día',
                                const Color(0xFFEF4444),
                                () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PromotionProductsScreen(
                                        title: 'Promociones del Día',
                                        initialProducts: promoProducts,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _horizontalProductList(promoProducts),
                            ],
                            for (
                              var index = 0;
                              index < categorySections.length;
                              index++
                            ) ...[
                              _sectionHeader(
                                _categoryIcon(
                                  categorySections[index].category.slug,
                                ),
                                categorySections[index].category.name,
                                _categoryColor(index),
                                () => _openCategoryProducts(
                                  categorySections[index].category,
                                ),
                              ),
                              _horizontalProductList(
                                categorySections[index].products,
                              ),
                            ],
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 32),
                            ),
                          ] else ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  _activeCategory != null
                                      ? _catLabel(_activeCategory!)
                                      : 'Resultados de búsqueda',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: _kNavy,
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisExtent: 315,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                    ),
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, i) =>
                                      ProductCard(product: _products[i]),
                                  childCount: _products.length,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
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
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
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
                          Icon(
                            Icons.search,
                            color: Colors.grey.shade500,
                            size: 20,
                          ),
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
                      MaterialPageRoute(
                        builder: (_) => const QuoteCartScreen(),
                      ),
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
                        child: const Icon(
                          Icons.request_quote_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsListScreen(),
                      ),
                    );
                    final userId =
                        Supabase.instance.client.auth.currentUser?.id;
                    if (userId != null) {
                      NotificationService.instance.updateUnreadCount(userId);
                    }
                  },
                  child: ValueListenableBuilder<int>(
                    valueListenable:
                        NotificationService.instance.unreadCountNotifier,
                    builder: (context, count, _) {
                      return Badge(
                        isLabelVisible: count > 0,
                        label: Text(count > 99 ? '99+' : count.toString()),
                        backgroundColor: const Color(0xFFEF4444),
                        textColor: Colors.white,
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () async {
                final result = await Navigator.of(context).push<ClientAddress>(
                  MaterialPageRoute(
                    builder: (_) => const AddressPickerScreen(),
                  ),
                );
                if (result != null && mounted) {
                  setState(() => _currentLocation = result.deliveryLabel);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(top: 4, bottom: 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        (_loading ||
                                _currentLocation == 'Selecciona tu ubicación')
                            ? '¿Dónde enviamos?'
                            : _currentLocation,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  bool _hasQuickCategories() {
    return _catalogCategories.isNotEmpty;
  }

  List<CatalogCategory> _quickCategories() {
    return _catalogCategories;
  }

  Color _categoryColor(int index) {
    const colors = [
      Color(0xFF0D9488),
      Color(0xFF2563EB),
      Color(0xFF0891B2),
      Color(0xFFDB2777),
      Color(0xFF7C3AED),
      Color(0xFF16A34A),
      Color(0xFFEA580C),
    ];
    return colors[index % colors.length];
  }

  void _openCategoryProducts(CatalogCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryProductsScreen(
          categoryId: category.id,
          categoryKey: category.productCategoryKey,
          categoryLabel: category.name,
          subcategoryLabel: category.name,
        ),
      ),
    );
  }

  void _openCategoryOverview(CatalogCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryCatalogScreen(category: category),
      ),
    );
  }

  IconData _categoryIcon(String value) {
    final key = value.toLowerCase();
    if (key.contains('ultrason') || key.contains('monitor')) {
      return Icons.monitor_heart_outlined;
    }
    if (key.contains('consum')) return Icons.water_drop_outlined;
    if (key.contains('refacc')) return Icons.build_outlined;
    if (key.contains('accesor')) return Icons.extension_outlined;
    if (key.contains('servic')) return Icons.settings_suggest_outlined;
    if (key.contains('equipo') || key.contains('medic')) {
      return Icons.medical_services_outlined;
    }
    return Icons.category_outlined;
  }

  Widget _quickCats() {
    final categories = _quickCategories();
    return Container(
      height: 84,
      color: Colors.white,
      child: ScrollConfiguration(
        behavior: MouseDragScrollBehavior(),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 5),
          itemCount: categories.length,
          itemBuilder: (_, index) {
            final category = categories[index];
            final categoryKey = category.productCategoryKey;
            final active = _activeCategory == categoryKey;
            const color = Color(0xFF9CA3AF);
            final label = category.name;
            return Padding(
              padding: EdgeInsets.only(
                right: index == categories.length - 1 ? 0 : 6,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _openCategoryOverview(category),
                child: SizedBox(
                  width: 74,
                  height: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        width: active ? 44 : 42,
                        height: active ? 44 : 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: active ? 0.16 : 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: color.withValues(
                              alpha: active ? 0.38 : 0.22,
                            ),
                          ),
                        ),
                        child: Icon(
                          _categoryIcon(category.slug),
                          color: color,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF6B7280)
                              : const Color(0xFF374151),
                          fontSize: 10.5,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        width: active ? 24 : 0,
                        height: 3,
                        decoration: BoxDecoration(
                          color: active ? color : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
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

  String _catLabel(String cat) {
    for (final category in _catalogCategories) {
      if (category.productCategoryKey == cat) {
        return category.name;
      }
    }
    return cat.replaceAll('_', ' ');
  }
}

class _MarketplaceLoadingBody extends StatelessWidget {
  const _MarketplaceLoadingBody();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(child: CircularProgressIndicator(color: _kPrimary)),
    );
  }
}
