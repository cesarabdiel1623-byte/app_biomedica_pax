import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/customer_coupon.dart';
import '../../models/product.dart';
import '../../services/coupon_service.dart';
import '../../services/product_service.dart';
import '../../utils/responsive_grid.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';
import '../home/widgets/product_card.dart';
import 'profile_helpers.dart';

class CouponEligibleProductsScreen extends StatefulWidget {
  final CustomerCoupon coupon;
  final Future<CouponEligibleProductsResult> Function({
    required String couponId,
    String? search,
    int limit,
    int offset,
  })?
  eligibleProductsLoader;
  final Future<List<Product>> Function(List<String> ids)? productsLoader;

  const CouponEligibleProductsScreen({
    super.key,
    required this.coupon,
    this.eligibleProductsLoader,
    this.productsLoader,
  });

  @override
  State<CouponEligibleProductsScreen> createState() =>
      _CouponEligibleProductsScreenState();
}

class _CouponEligibleProductsScreenState
    extends State<CouponEligibleProductsScreen> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  List<Product> _products = const [];
  int _totalCount = 0;
  bool _isFullCatalog = false;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  String? _error;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 250) {
      _loadMore();
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _loadInitial(showSpinner: true);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _loadInitial(showSpinner: true);
  }

  Future<void> _loadInitial({bool showSpinner = true}) async {
    _debounceTimer?.cancel();
    if (mounted && showSpinner) {
      setState(() {
        _loadingInitial = true;
        _error = null;
        _offset = 0;
      });
    }

    try {
      final query = _searchController.text.trim();
      final rpcFuture = widget.eligibleProductsLoader != null
          ? widget.eligibleProductsLoader!(
              couponId: widget.coupon.couponId,
              search: query.isNotEmpty ? query : null,
              limit: _pageSize,
              offset: 0,
            )
          : CouponService.getCouponEligibleProductIds(
              couponId: widget.coupon.couponId,
              search: query.isNotEmpty ? query : null,
              limit: _pageSize,
              offset: 0,
            );

      final rpcResult = await rpcFuture;

      List<Product> fetchedProducts = const [];
      if (rpcResult.productIds.isNotEmpty) {
        final productsFuture = widget.productsLoader != null
            ? widget.productsLoader!(rpcResult.productIds)
            : ProductService.getProductsByIds(rpcResult.productIds);
        fetchedProducts = await productsFuture;
      }

      if (mounted) {
        setState(() {
          _products = fetchedProducts;
          _totalCount = rpcResult.totalCount;
          _isFullCatalog = rpcResult.isFullCatalog;
          _offset = rpcResult.productIds.length;
          _loadingInitial = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('Error en CouponEligibleProductsScreen._loadInitial: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loadingInitial = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loadingInitial || _products.length >= _totalCount) {
      return;
    }

    setState(() => _loadingMore = true);

    try {
      final query = _searchController.text.trim();
      final rpcFuture = widget.eligibleProductsLoader != null
          ? widget.eligibleProductsLoader!(
              couponId: widget.coupon.couponId,
              search: query.isNotEmpty ? query : null,
              limit: _pageSize,
              offset: _offset,
            )
          : CouponService.getCouponEligibleProductIds(
              couponId: widget.coupon.couponId,
              search: query.isNotEmpty ? query : null,
              limit: _pageSize,
              offset: _offset,
            );

      final rpcResult = await rpcFuture;

      if (rpcResult.productIds.isNotEmpty) {
        final productsFuture = widget.productsLoader != null
            ? widget.productsLoader!(rpcResult.productIds)
            : ProductService.getProductsByIds(rpcResult.productIds);
        final nextProducts = await productsFuture;

        if (mounted) {
          final existingIds = _products.map((p) => p.id).toSet();
          final uniqueNext = nextProducts
              .where((p) => !existingIds.contains(p.id))
              .toList();

          setState(() {
            _products = [..._products, ...uniqueNext];
            _totalCount = rpcResult.totalCount;
            _isFullCatalog = rpcResult.isFullCatalog;
            _offset += rpcResult.productIds.length;
            _loadingMore = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _totalCount = rpcResult.totalCount;
            _loadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error en CouponEligibleProductsScreen._loadMore: $e');
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Productos participantes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header info bar
          _buildCouponHeaderBar(),

          // Search bar
          _buildSearchBar(),

          // Full catalog banner (if applicable)
          if (_isFullCatalog && !_loadingInitial && _error == null)
            _buildFullCatalogBanner(),

          // Main body
          Expanded(
            child: _loadingInitial
                ? const Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  )
                : _error != null
                ? RefreshIndicator(
                    color: kPrimary,
                    backgroundColor: Colors.white,
                    onRefresh: () => _loadInitial(showSpinner: false),
                    child: ListView(
                      physics: UiHelpers.refreshScrollPhysics,
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height - 250,
                          child: LoadErrorState(
                            error: _error,
                            onRetry: _loadInitial,
                            genericTitle: 'Error al consultar productos',
                            genericMessage:
                                'No pudimos cargar los productos participantes del cupón.',
                          ),
                        ),
                      ],
                    ),
                  )
                : _products.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    color: kPrimary,
                    backgroundColor: Colors.white,
                    onRefresh: () => _loadInitial(showSpinner: false),
                    child: _buildProductsGrid(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponHeaderBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.discount_outlined,
              size: 16,
              color: kPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      widget.coupon.code,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• ${widget.coupon.benefitText}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kSecondary,
                      ),
                    ),
                  ],
                ),
                if (widget.coupon.name.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    widget.coupon.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_loadingInitial && _error == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_totalCount ${_totalCount == 1 ? 'producto' : 'productos'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A)),
        decoration: InputDecoration(
          hintText: 'Buscar productos participantes...',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 20,
            color: Color(0xFF94A3B8),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: _clearSearch,
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kPrimary, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _buildFullCatalogBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF0FDF4),
        border: Border(bottom: BorderSide(color: Color(0xFFDCFCE7))),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 15,
            color: Color(0xFF16A34A),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Este cupón aplica a todo el catálogo disponible.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF15803D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.trim().isNotEmpty;
    final title = hasSearch
        ? 'No encontramos productos con esa búsqueda'
        : (!widget.coupon.isAvailable
              ? 'Este cupón ya no está disponible'
              : 'No hay productos participantes disponibles actualmente');
    final subtitle = hasSearch
        ? 'Intenta con otro término o borra la búsqueda.'
        : 'Consulta las condiciones del cupón o revisa nuestro catálogo general.';

    return RefreshIndicator(
      color: kPrimary,
      backgroundColor: Colors.white,
      onRefresh: () => _loadInitial(showSpinner: false),
      child: ListView(
        physics: UiHelpers.refreshScrollPhysics,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 300,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasSearch
                            ? Icons.search_off_rounded
                            : Icons.inventory_2_outlined,
                        size: 32,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (hasSearch) ...[
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: _clearSearch,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kPrimary,
                          side: const BorderSide(color: kPrimary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: const Text('Limpiar búsqueda'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final columnCount = ResponsiveGrid.productColumnCount(
          constraints.maxWidth - 20,
        );
        final cardExtent = ResponsiveGrid.productCardExtent(textScale);

        return CustomScrollView(
          controller: _scrollController,
          physics: UiHelpers.refreshScrollPhysics,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  mainAxisExtent: cardExtent,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  return ProductCard(product: _products[index]);
                }, childCount: _products.length),
              ),
            ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: kPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
      },
    );
  }
}
