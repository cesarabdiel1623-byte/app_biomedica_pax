import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/promotion_banner.dart';
import '../../../models/product.dart';
import '../../../services/product_service.dart';
import '../../../services/promotion_banner_service.dart';
import 'promotion_navigation.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kBannerAspectRatio = 16 / 9;
const _kBannerInterval = Duration(seconds: 5);

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
  final _controller = PageController();
  List<DisplayPromotionBanner> _banners = const [];
  Map<String, Product?> _productsById = const {};
  int _current = 0;
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
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _productsById = productsById;
        _current = 0;
        _loading = false;
      });
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

  Future<void> _advanceBanner() async {
    if (!mounted || !_screenActive || !_appActive || _banners.length < 2) {
      return;
    }
    if (!_controller.hasClients) {
      _startTimer();
      return;
    }

    final next = (_current + 1) % _banners.length;
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
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_banners.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 24;
        final bannerWidth = availableWidth > 720 ? 720.0 : availableWidth;
        final height = (bannerWidth / _kBannerAspectRatio).clamp(150.0, 320.0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _banners.length,
                    onPageChanged: (index) {
                      if (mounted) setState(() => _current = index);
                    },
                    itemBuilder: (_, index) => _buildBanner(_banners[index]),
                  ),
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
    final product = productId == null ? null : _productsById[productId];
    final backgroundColor = _parseColor(banner.primaryColor, Colors.white);
    final textColor = _parseColor(banner.textColor, Colors.white);
    final accentColor = _parseColor(banner.accentColor, _kPrimary);
    final showOverlay =
        !banner.isFinalRender &&
        (banner.headline?.trim().isNotEmpty == true ||
            banner.subheadline?.trim().isNotEmpty == true ||
            productId?.isNotEmpty == true);
    return Material(
      color: backgroundColor,
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
              fit: BoxFit.cover,
              alignment: Alignment.center,
              semanticLabel: banner.selectedAsset?.altText,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => ColoredBox(
                color: backgroundColor,
                child: const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey,
                    size: 32,
                  ),
                ),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return ColoredBox(
                  color: backgroundColor,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: _kPrimary,
                      strokeWidth: 2,
                    ),
                  ),
                );
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
                      if (product != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              product.formattedPrice,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (product.hasDiscount) ...[
                              const SizedBox(width: 6),
                              Text(
                                product.formattedOldPrice,
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
                          product.stockStatusLabel,
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
    );
  }

  Widget _buildLoading() {
    return Container(
      height: 138,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2),
      ),
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
}
