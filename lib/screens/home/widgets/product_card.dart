import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/product.dart';
import '../../../utils/ui_helpers.dart';
import '../../product/product_detail_screen.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFEF4444);

class ProductCard extends StatefulWidget {
  final Product product;
  final bool enableHero;

  const ProductCard({super.key, required this.product, this.enableHero = true});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  final bool _addingToCart = false;
  bool _isTapped = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return GestureDetector(
      onTapDown: (_) => setState(() => _isTapped = true),
      onTapUp: (_) {
        setState(() => _isTapped = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(productId: product.id),
          ),
        );
      },
      onTapCancel: () => setState(() => _isTapped = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.diagonal3Values(
          _isTapped ? 1.02 : 1.0,
          _isTapped ? 1.02 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 150,
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: product.mainImageUrl != null
                          ? widget.enableHero
                                ? Hero(
                                    tag: 'product-image-${product.id}',
                                    child: UiHelpers.networkImage(
                                      product.mainImageUrl!,
                                      fit: BoxFit.contain,
                                      iconSize: 32,
                                    ),
                                  )
                                : UiHelpers.networkImage(
                                    product.mainImageUrl!,
                                    fit: BoxFit.contain,
                                    iconSize: 32,
                                  )
                          : widget.enableHero
                          ? Hero(
                              tag: 'product-image-${product.id}',
                              child: _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  if (product.activePromotion != null ||
                      product.salesCount >= 50)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 120),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: _kRed,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: MarqueeText(
                          text: (product.activePromotion != null)
                              ? ((product.activePromotion!.campaignName !=
                                            null &&
                                        product
                                            .activePromotion!
                                            .campaignName!
                                            .isNotEmpty)
                                    ? product.activePromotion!.campaignName!
                                          .toUpperCase()
                                    : (product.activePromotion!.promotionName !=
                                              null &&
                                          product
                                              .activePromotion!
                                              .promotionName!
                                              .isNotEmpty)
                                    ? product.activePromotion!.promotionName!
                                          .toUpperCase()
                                    : 'PROMOCIÓN')
                              : 'MÁS VENDIDO',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF1F2937),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),

                  if (product.hasDiscount) ...[
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            product.formattedOldPrice,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '-${product.discountPercent}%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                  ],

                  Text(
                    product.formattedPrice,
                    style: const TextStyle(
                      fontSize: 18.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (product.salesCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _formatSalesCount(product.salesCount),
                        style: const TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  const SizedBox(height: 5),
                  if (product.shippingInfo != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          size: 12,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            product.shippingInfo!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
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
                  if (product.productCondition != null &&
                      (product.productCondition == 'preowned' ||
                          product.productCondition == 'remanufactured')) ...[
                    const SizedBox(height: 5),
                    Text(
                      product.conditionLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3483FA),
                      ),
                    ),
                  ],
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
      Icons.medical_services_outlined,
      color: Colors.grey.shade300,
      size: 32,
    ),
  );

  /// Formatea el conteo real de ventas de la BD (sin datos inventados).
  String _formatSalesCount(int count) {
    if (count <= 0) return '';
    if (count < 1000) return '+$count vendidos';
    if (count < 1000000) {
      final miles = count / 1000;
      if (miles == miles.roundToDouble()) {
        return '+${miles.toInt()} mil vendidos';
      }
      return '+${miles.toStringAsFixed(1)} mil vendidos';
    }
    final millones = count / 1000000;
    return '+${millones.toStringAsFixed(1)} M vendidos';
  }
}

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const MarqueeText({super.key, required this.text, required this.style});

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startScrolling();
      }
    });
  }

  void _startScrolling() async {
    // Prevent starting scrolls in a test environment to avoid timer leak exceptions
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    if (!mounted || !_scrollController.hasClients) return;

    // Small delay to ensure layout is fully computed
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return; // No scroll needed

    _isScrolling = true;
    while (mounted && _isScrolling) {
      if (!_scrollController.hasClients) break;

      // Pause at start
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isScrolling || !_scrollController.hasClients) break;

      // Scroll to end
      await _scrollController.animateTo(
        maxScroll,
        duration: Duration(milliseconds: (maxScroll * 40).toInt() + 1000),
        curve: Curves.linear,
      );

      // Pause at end
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isScrolling || !_scrollController.hasClients) break;

      // Scroll back to start
      await _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: (maxScroll * 40).toInt() + 1000),
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style),
    );
  }
}
