import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/search_service.dart';
import '../../widgets/standard_section_header.dart';
import '../home/widgets/product_card.dart';
import 'product_detail_screen.dart';
import '../../utils/ui_helpers.dart';

const _kPrimary = Color(0xFF0D9488); // Teal principal
const _kNavy = Color(0xFF1E3A5F); // Azul navy
const _kGreen = Color(0xFF16A34A); // Verde envío
const _kRed = Color(0xFFEF4444); // Rojo descuento
const _kBg = Color(0xFFF8FAFC); // Gris claro fondo

class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<String> _history = [];
  List<Product> _recentlyViewed = [];
  List<Product> _suggestions = [];
  List<Product> _results = [];

  bool _isLoading = false;
  bool _isSearching = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHistoryAndRecent();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      _currentQuery = widget.initialQuery!;
      _onQueryChanged(widget.initialQuery!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistoryAndRecent() async {
    final history = await SearchService.getSearchHistory();
    final recent = await SearchService.getRecentlyViewed();
    if (mounted) {
      setState(() {
        _history = history;
        _recentlyViewed = recent;
      });
    }
  }

  Future<void> _onQueryChanged(String query) async {
    setState(() {
      _currentQuery = query;
      _isSearching = false;
    });

    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    try {
      final suggestions = await ProductService.searchProducts(query);
      if (mounted && _searchController.text == query) {
        setState(() {
          _suggestions = suggestions;
        });
      }
    } catch (e) {
      print('Error loading search suggestions: $e');
    }
  }

  Future<void> _executeSearch(String query, {bool showSpinner = false}) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    _focusNode.unfocus();
    setState(() {
      _currentQuery = trimmedQuery;
      _searchController.text = trimmedQuery;
    });

    await SearchService.saveSearchQuery(trimmedQuery);

    try {
      final results = await ProductService.searchProducts(trimmedQuery);
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = true;
          _isLoading = false;
        });
        _loadHistoryAndRecent();
      }
    } catch (e) {
      print('Error executing search: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshSearchResults() async {
    if (_currentQuery.trim().isEmpty) return;
    await _executeSearch(_currentQuery, showSpinner: false);
  }

  Future<void> _deleteHistoryItem(String query) async {
    await SearchService.removeSearchQuery(query);
    _loadHistoryAndRecent();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _currentQuery = '';
      _isSearching = false;
      _suggestions = [];
      _results = [];
    });
    _focusNode.requestFocus();
  }

  Future<void> _navigateToDetail(
    String productId, {
    String? searchQuery,
  }) async {
    if (searchQuery != null && searchQuery.isNotEmpty) {
      setState(() {
        _searchController.text = searchQuery;
        _currentQuery = searchQuery;
        _isSearching = true;
      });
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ProductDetailScreen(productId: productId, searchQuery: searchQuery),
      ),
    );
    _loadHistoryAndRecent();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: !_isSearching && _currentQuery.isEmpty,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_isSearching || _currentQuery.isNotEmpty) {
            _clearSearch();
          }
        },
        child: Scaffold(
          backgroundColor: _kBg,
          body: Column(
            children: [
              _buildHeader(context),
              Expanded(child: SafeArea(top: false, child: _buildBody())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ColoredBox(
      color: _kPrimary,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              StandardBackButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Regresar',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
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
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    style: const TextStyle(color: _kNavy, fontSize: 14),
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                    onSubmitted: _executeSearch,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.only(
                        left: 12,
                        right: 8,
                        top: 12,
                        bottom: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.search,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 46,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 46,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _currentQuery.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF64748B),
                                    size: 14,
                                  ),
                                ),
                                onPressed: _clearSearch,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                splashRadius: 18,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return _buildSearchResults();
    }

    if (_currentQuery.isNotEmpty) {
      return _buildSuggestionsList();
    }

    return _buildInitialState();
  }

  Widget _buildInitialState() {
    final bool hasHistory = _history.isNotEmpty;
    final bool hasRecent = _recentlyViewed.isNotEmpty;

    if (!hasHistory && !hasRecent) {
      return ListView(
        physics: const ClampingScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _kPrimary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      size: 64,
                      color: _kPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Busca equipos médicos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _kNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Encuentra ultrasonidos, consumibles, refacciones y más en Biomedica Pax.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      physics: const ClampingScrollPhysics(),
      children: [
        if (hasHistory) ...[
          const Text(
            'Búsquedas recientes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _kNavy,
            ),
          ),
          const SizedBox(height: 12),
          _buildHistoryChips(),
          const SizedBox(height: 28),
        ],
        if (hasRecent) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recién visto',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('recently_viewed_products');
                  _loadHistoryAndRecent();
                },
                child: Text(
                  'Limpiar',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: _recentlyViewed.length,
              itemBuilder: (context, index) {
                final product = _recentlyViewed[index];
                return _buildRecentlyViewedItem(product);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _history.map((query) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.only(left: 14, right: 6, top: 6, bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _executeSearch(query),
                child: Text(
                  query,
                  style: const TextStyle(
                    color: _kNavy,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _deleteHistoryItem(query),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentlyViewedItem(Product product) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 140,
        height: 240,
        child: _ProductCard(
          product: product,
          searchQuery: null,
          isCompact: true,
          onGoToCart: () {
            _loadHistoryAndRecent();
          },
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return ListView.separated(
      physics: const ClampingScrollPhysics(),
      itemCount: _suggestions.length + 1,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_rounded,
                color: _kPrimary,
                size: 18,
              ),
            ),
            title: Text(
              'Buscar "${_searchController.text}"',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: _kPrimary,
                fontSize: 14.5,
              ),
            ),
            onTap: () => _executeSearch(_searchController.text),
          );
        }
        final product = _suggestions[index - 1];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ),
          title: Text(
            product.name,
            style: const TextStyle(
              color: _kNavy,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(
            Icons.arrow_outward_rounded,
            color: Color(0xFF94A3B8),
            size: 16,
          ),
          onTap: () => _executeSearch(product.name),
        );
      },
    );
  }

  Widget _buildSearchOffIcon() {
    return Icon(Icons.search_rounded, size: 64, color: Colors.grey.shade400);
  }

  Widget _buildSearchResults() {
    if (_results.isEmpty) {
      return RefreshIndicator(
        color: _kPrimary,
        backgroundColor: Colors.white,
        displacement: 42,
        triggerMode: RefreshIndicatorTriggerMode.onEdge,
        onRefresh: _refreshSearchResults,
        child: ListView(
          physics: UiHelpers.refreshScrollPhysics,
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.58,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSearchOffIcon(),
                    const SizedBox(height: 12),
                    Text(
                      'Sin resultados para "$_currentQuery"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No encontramos coincidencias para esta búsqueda.\nIntenta con otros términos o verifica la ortografía.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _kPrimary,
      backgroundColor: Colors.white,
      displacement: 42,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      onRefresh: _refreshSearchResults,
      child: CustomScrollView(
        physics: UiHelpers.refreshScrollPhysics,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '${_results.length} resultado${_results.length > 1 ? 's' : ''} para "$_currentQuery"',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 315,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final product = _results[index];
                return ProductCard(product: product, enableHero: false);
              }, childCount: _results.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback? onGoToCart;
  final String? searchQuery;
  final bool isCompact;
  const _ProductCard({
    required this.product,
    this.onGoToCart,
    this.searchQuery,
    this.isCompact = false,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  final bool _addingToCart = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final onGoToCart = widget.onGoToCart;
    final searchQuery = widget.searchQuery;
    final isCompact = widget.isCompact;
    final imgHeight = isCompact ? 110.0 : 150.0;
    final titleFontSize = isCompact ? 10.5 : 13.5;
    final oldPriceFontSize = isCompact ? 9.0 : 11.5;
    final priceFontSize = isCompact ? 12.5 : 18.5;
    final infoFontSize = isCompact ? 9.0 : 11.0;
    final btnSize = isCompact ? 28.0 : 34.0;
    final iconSize = isCompact ? 14.0 : 16.0;
    final padding = const EdgeInsets.fromLTRB(8, 6, 8, 8);

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(
              productId: product.id,
              searchQuery: searchQuery,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Imagen + cart button + badge
            SizedBox(
              height: imgHeight,
              width: double.infinity,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    child: Container(
                      width: double.infinity,
                      height: imgHeight,
                      color: const Color(0xFFF8FAFC),
                      padding: const EdgeInsets.all(6),
                      child:
                          product.mainImageUrl != null &&
                              product.mainImageUrl!.isNotEmpty
                          ? UiHelpers.networkImage(
                              product.mainImageUrl!,
                              fit: BoxFit.contain,
                              iconSize: 32,
                            )
                          : _placeholder(),
                    ),
                  ),
                  if (product.hasDiscount)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: isCompact ? 100 : 130,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kRed,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          product.activePromotion?.campaignName != null
                              ? '${product.activePromotion!.campaignName!.toUpperCase()} · ${product.discountPercent}% OFF'
                              : '${product.discountPercent}% OFF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 8.0 : 9.0,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info del producto
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      color: const Color(0xFF1F2937),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (product.hasDiscount)
                    Text(
                      product.formattedOldPrice,
                      style: TextStyle(
                        fontSize: oldPriceFontSize,
                        color: const Color(0xFF9CA3AF),
                        decoration: TextDecoration.lineThrough,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    product.formattedPrice,
                    style: TextStyle(
                      fontSize: priceFontSize,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF111827),
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.hasDiscount) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${product.discountPercent}% OFF',
                      style: TextStyle(
                        fontSize: oldPriceFontSize,
                        color: _kGreen,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (product.hasFreeShipping)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            size: isCompact ? 10.0 : 12.0,
                            color: _kGreen,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              'Envío gratis',
                              style: TextStyle(
                                fontSize: infoFontSize,
                                color: _kGreen,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Icon(
                        product.stockStatusLabel == 'Sin stock'
                            ? Icons.highlight_off_rounded
                            : Icons.check_circle_outline_rounded,
                        size: isCompact ? 10.0 : 12.0,
                        color: product.stockStatusColor,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          product.stockStatusLabel,
                          style: TextStyle(
                            fontSize: infoFontSize,
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
    child: Icon(
      Icons.image_not_supported_outlined,
      color: Colors.grey.shade300,
      size: widget.isCompact ? 28 : 32,
    ),
  );
}
