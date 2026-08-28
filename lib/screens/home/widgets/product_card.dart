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

  const ProductCard({
    super.key,
    required this.product,
    this.enableHero = false,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  final bool _addingToCart = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(productId: product.id),
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
        clipBehavior: Clip.antiAlias,
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
                      top: Radius.circular(8),
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 150,
                      color: const Color(0xFFF8FAFC),
                      padding: const EdgeInsets.all(8),
                      child: product.mainImageUrl != null
                          ? UiHelpers.networkImage(
                              product.mainImageUrl!,
                              fit: BoxFit.contain,
                              iconSize: 32,
                            )
                          : _placeholder(),
                    ),
                  ),
                  if (product.hasDiscount || product.salesCount >= 50)
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
                        child: Text(
                          product.hasDiscount
                              ? '-${product.discountPercent}%'
                              : 'MÁS VENDIDO',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
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
                    Text(
                      'Antes: ${product.formattedOldPrice}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                        decoration: TextDecoration.lineThrough,
                        fontWeight: FontWeight.w500,
                      ),
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
      size: 32,
    ),
  );
}
