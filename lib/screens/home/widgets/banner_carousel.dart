import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/promotion_banner.dart';
import '../../../models/product.dart';
import '../../../services/product_service.dart';
import '../../../services/promotion_banner_service.dart';
import 'promotion_navigation.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kBannerAspectRatio = 8 / 3; // 1600 x 600 px (2.6667:1)
const _kBannerInterval = Duration(seconds: 3);
const _kInitialBannerPage = 100000;

class BannerCarousel extends StatefulWidget {
  const BannerCarousel({
    super.key,
    this.refreshToken = 0,
    this.onInitialLoadComplete,
  });

  final int refreshToken;
  final VoidCallback? onInitialLoadComplete;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel>
    with WidgetsBindingObserver {
  final _controller = PageController(
    initialPage: _kInitialBannerPage,
    viewportFraction: 0.90,
  );
  List<DisplayPromotionBanner> _banners = const [];
  Map<String, Product?> _productsById = const {};
  int _current = 0;
  int _physicalPage = _kInitialBannerPage;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  bool _screenActive = true;
  bool _appActive = true;
  bool _hasCompletedLoad = false;
  bool _initialLoadReported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBanners();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.valuesOf(context).enabled;
    if (_screenActive == isActive) return;
    _screenActive = isActive;
    if (_screenActive && _appActive) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && _screenActive) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant BannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadBanners(forceRefresh: true);
    }
  }

  Future<void> _loadBanners({bool forceRefresh = false}) async {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        if (!_hasCompletedLoad) _loading = true;
        _error = null;
      });
    }

    try {
      final banners = await PromotionBannerService.getActiveBanners(
        forceRefresh: forceRefresh,
      );
      final productsById = await _loadProducts(banners);
      await _precacheBannerImages(banners);
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _productsById = productsById;
        _current = 0;
        _loading = false;
      });
      _alignCarouselToFirstBanner();
      _completeInitialLoad();
      _startTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      _completeInitialLoad();
    }
  }

  void _completeInitialLoad() {
    _hasCompletedLoad = true;
    if (_initialLoadReported) return;
    _initialLoadReported = true;
    widget.onInitialLoadComplete?.call();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_banners.length < 2 || !_screenActive || !_appActive) return;
    _timer = Timer(_kBannerInterval, _advanceBanner);
  }

  void _alignCarouselToFirstBanner() {
    if (_banners.length < 2) return;
    _physicalPage =
        _kInitialBannerPage - (_kInitialBannerPage % _banners.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(_physicalPage);
    });
  }

  Future<void> _precacheBannerImages(
    List<DisplayPromotionBanner> banners,
  ) async {
    await Future.wait(
      banners.map((banner) async {
        try {
          await precacheImage(
            NetworkImage(banner.imageUrl),
            context,
          ).timeout(const Duration(seconds: 4));
        } catch (error) {
          debugPrint('[BannerCarousel] No se pudo precargar: $error');
        }
      }),
    );
  }

  Future<void> _advanceBanner() async {
    if (!mounted || !_screenActive || !_appActive || _banners.length < 2) {
      return;
    }
    if (!_controller.hasClients) {
      _startTimer();
      return;
    }

    final next = _physicalPage + 1;
    await _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
    if (mounted) _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color _parseColor(String? value, Color fallback) {
    final normalized = value?.trim().replaceFirst('#', '');
    if (normalized == null || normalized.isEmpty) return fallback;
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  Future<Map<String, Product?>> _loadProducts(
    List<DisplayPromotionBanner> banners,
  ) async {
    final ids = banners
        .map((item) => item.banner.productId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final entries = await Future.wait(
      ids.map((id) async {
        try {
          return MapEntry(id, await ProductService.getProductById(id));
        } catch (error) {
          debugPrint(
            '[BannerCarousel] No se pudo cargar el producto $id: $error',
          );
          return MapEntry<String, Product?>(id, null);
        }
      }),
    );
    return Map.fromEntries(entries);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _banners.isEmpty) return _buildLoading();
    if (_error != null && _banners.isEmpty) return _buildError();
    if (_banners.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final bannerWidth = availableWidth > 720 ? 720.0 : availableWidth;
        final isSingle = _banners.length == 1;
        // El ancho real del elemento individual de banner:
        final itemWidth = isSingle
            ? (bannerWidth - 24.0)
            : ((bannerWidth * 0.90) - 10.0);
        // Altura exacta respetando la proporción 8:3 (1600x600 px):
        final itemHeight = itemWidth / _kBannerAspectRatio;
        final height =
            itemHeight + 4.0; // 2px superior + 2px inferior de margen

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: SizedBox(
              width: bannerWidth,
              height: height,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _timer?.cancel();
                  } else if (notification is ScrollEndNotification) {
                    _startTimer();
                  }
                  return false;
                },
                child: _banners.length == 1
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildBanner(_banners.first),
                      )
                    : PageView.builder(
                        controller: _controller,
                        padEnds: true,
                        onPageChanged: (index) {
                          _physicalPage = index;
                          final logicalIndex = index % _banners.length;
                          if (mounted && logicalIndex != _current) {
                            setState(() => _current = logicalIndex);
                          }
                          final nextBanner =
                              _banners[(logicalIndex + 1) % _banners.length];
                          precacheImage(
                            NetworkImage(nextBanner.imageUrl),
                            context,
                          ).catchError((Object _) {});
                        },
                        itemBuilder: (_, index) =>
                            _buildBanner(_banners[index % _banners.length]),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBanner(DisplayPromotionBanner displayBanner) {
    final banner = displayBanner.banner;
    final productId = banner.productId?.trim();
    final isManualFinalHero = banner.isManualFinalHeroRender;
    final product = productId == null ? null : _productsById[productId];
    final overlayProduct = isManualFinalHero ? null : product;
    final backgroundColor = _parseColor(banner.primaryColor, Colors.white);
    final textColor = _parseColor(banner.textColor, Colors.white);
    final accentColor = _parseColor(banner.accentColor, _kPrimary);
    final showOverlay =
        !isManualFinalHero &&
        !banner.isFinalRender &&
        (banner.headline?.trim().isNotEmpty == true ||
            banner.subheadline?.trim().isNotEmpty == true ||
            productId?.isNotEmpty == true);

    // Si un asset legacy antiguo tiene relación muy alejada de 8:3 (e.g. < 2.1:1),
    // usar contain para evitar recorte agresivo, de lo contrario cover para 1600x600.
    final assetRatio = banner.selectedAsset?.aspectRatio;
    final isLegacyNarrowAsset = assetRatio != null && assetRatio < 2.1;
    final imageFit = isManualFinalHero
        ? BoxFit.cover
        : (isLegacyNarrowAsset ? BoxFit.contain : BoxFit.cover);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: const Color(0xFFF8FAFC),
        child: InkWell(
          onTap:
              PromotionNavigation.hasDestination(
                banner,
                productAvailable: productId == null || product != null,
              )
              ? () => PromotionNavigation.open(context, banner)
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                displayBanner.imageUrl,
                fit: imageFit,
                alignment: Alignment.center,
                semanticLabel: banner.selectedAsset?.altText,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _bannerLoadingPlaceholder(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _bannerLoadingPlaceholder();
                },
              ),
              if (showOverlay)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: MediaQuery.sizeOf(context).width * 0.6,
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          backgroundColor.withValues(alpha: 0.94),
                          backgroundColor.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (banner.badgeText?.trim().isNotEmpty == true)
                          Text(
                            banner.badgeText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (banner.headline?.trim().isNotEmpty == true)
                          Text(
                            banner.headline!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (banner.subheadline?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 3),
                          Text(
                            banner.subheadline!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (overlayProduct != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Text(
                                overlayProduct.formattedPrice,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (overlayProduct.hasDiscount) ...[
                                const SizedBox(width: 6),
                                Text(
                                  overlayProduct.formattedOldPrice,
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.7),
                                    fontSize: 10,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: textColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            overlayProduct.stockStatusLabel,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else if (productId?.isNotEmpty == true) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Producto no disponible',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (banner.ctaText?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(
                            banner.ctaText!,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final bannerWidth = availableWidth > 720 ? 720.0 : availableWidth;
        final itemWidth = bannerWidth - 24.0;
        final height = (itemWidth / _kBannerAspectRatio) + 4.0;
        return Center(
          child: Container(
            width: bannerWidth,
            height: height,
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _bannerLoadingPlaceholder(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildError() {
    return Container(
      height: 112,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.image_outlined, color: _kNavy),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No pudimos cargar las promociones.',
              style: TextStyle(
                color: _kNavy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Reintentar',
            onPressed: () => _loadBanners(forceRefresh: true),
            icon: const Icon(Icons.refresh, color: _kPrimary),
          ),
        ],
      ),
    );
  }

  Widget _bannerLoadingPlaceholder() => const ColoredBox(
    color: Color(0xFFF8FAFC),
    child: Center(child: CircularProgressIndicator(color: _kPrimary)),
  );
}
