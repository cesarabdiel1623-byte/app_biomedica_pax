import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../../../models/promotion_banner.dart';
import '../../../services/product_service.dart';
import '../../../services/promotion_banner_service.dart';
import 'promotion_navigation.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);

class PromotionCardsSection extends StatefulWidget {
  const PromotionCardsSection({
    super.key,
    this.refreshToken = 0,
    this.onInitialLoadComplete,
  });

  final int refreshToken;
  final VoidCallback? onInitialLoadComplete;

  @override
  State<PromotionCardsSection> createState() => _PromotionCardsSectionState();
}

class _PromotionCardsSectionState extends State<PromotionCardsSection> {
  List<DisplayPromotionBanner> _cards = const [];
  Map<String, Product?> _productsById = const {};
  bool _loading = true;
  bool _failed = false;
  bool _hasCompletedLoad = false;
  bool _initialLoadReported = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PromotionCardsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load(forceRefresh: true);
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        if (!_hasCompletedLoad) _loading = true;
        _failed = false;
      });
    }
    try {
      final cards = await PromotionBannerService.getActiveCards(
        forceRefresh: forceRefresh,
      );
      final productIds = cards
          .map((item) => item.banner.productId?.trim())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      final products = await Future.wait(
        productIds.map((id) async {
          try {
            return MapEntry(id, await ProductService.getProductById(id));
          } catch (error) {
            debugPrint(
              '[PromotionCardsSection] No se pudo cargar el producto $id: '
              '$error',
            );
            return MapEntry<String, Product?>(id, null);
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _productsById = Map.fromEntries(products);
        _loading = false;
      });
      _completeInitialLoad();
    } catch (error) {
      debugPrint(
        '[PromotionCardsSection] No se pudieron cargar tarjetas: $error',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_failed) return _buildError();
    if (_cards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.local_offer_outlined, color: _kPrimary, size: 19),
                SizedBox(width: 7),
                Text(
                  'Promociones',
                  style: TextStyle(
                    color: _kNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 184,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, index) => _buildCard(_cards[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(DisplayPromotionBanner displayCard) {
    final creative = displayCard.banner;
    final productId = creative.productId?.trim();
    final product = productId == null ? null : _productsById[productId];
    final background = _parseColor(creative.primaryColor, Colors.white);
    final textColor = _parseColor(creative.textColor, _kNavy);
    final accent = _parseColor(creative.accentColor, _kPrimary);
    final isBackground = displayCard.assetRole?.toLowerCase() == 'background';

    return SizedBox(
      width: 292,
      child: Material(
        color: background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: InkWell(
          onTap:
              PromotionNavigation.hasDestination(
                creative,
                productAvailable: productId == null || product != null,
              )
              ? () => PromotionNavigation.open(context, creative)
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                displayCard.imageUrl,
                fit: isBackground ? BoxFit.cover : BoxFit.contain,
                filterQuality: FilterQuality.high,
                semanticLabel: creative.selectedAsset?.altText,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      color: _kPrimary,
                      strokeWidth: 2,
                    ),
                  );
                },
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey,
                    size: 32,
                  ),
                ),
              ),
              if (!creative.isFinalRender)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 190,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          background.withValues(alpha: 0.96),
                          background.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (creative.badgeText?.trim().isNotEmpty == true)
                          Text(
                            creative.badgeText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          creative.headline?.trim().isNotEmpty == true
                              ? creative.headline!
                              : product?.name ?? 'Promoción',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (product != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            product.formattedPrice,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (product.hasDiscount)
                            Text(
                              '${product.formattedOldPrice}  ${product.discountPercent}% OFF',
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Text(
                            product.stockStatusLabel,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.82),
                              fontSize: 10,
                            ),
                          ),
                        ] else if (productId?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Producto no disponible',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.82),
                              fontSize: 10,
                            ),
                          ),
                        ],
                        if (creative.ctaText?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 7),
                          Text(
                            creative.ctaText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
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
    return Container(
      height: 122,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      height: 76,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'No pudimos cargar las tarjetas promocionales.',
              style: TextStyle(
                color: _kNavy,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Reintentar',
            onPressed: () => _load(forceRefresh: true),
            icon: const Icon(Icons.refresh, color: _kPrimary),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? value, Color fallback) {
    final normalized = value?.trim().replaceFirst('#', '');
    if (normalized == null || normalized.isEmpty) return fallback;
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }
}
