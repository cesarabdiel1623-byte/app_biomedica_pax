import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../product/product_detail_screen.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFEF4444);

class CategoryProductsScreen extends StatefulWidget {
  final String categoryId;
  final String categoryKey;
  final String categoryLabel;
  final String subcategoryLabel;
  final String? subcategoryId;
  final String? subcategoryKey;

  const CategoryProductsScreen({
    super.key,
    required this.categoryId,
    required this.categoryKey,
    required this.categoryLabel,
    required this.subcategoryLabel,
    this.subcategoryId,
    this.subcategoryKey,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  List<Product> _products = [];
  bool _loading = true;
  String? _error;

  bool get _isSubcategoryView =>
      widget.subcategoryId?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final subcategoryId = widget.subcategoryId;
      final List<Product> list;

      if (subcategoryId == null || subcategoryId.isEmpty) {
        list = await ProductService.getProductsByCatalogCategory(
          categoryId: widget.categoryId,
          legacyCategory: widget.categoryKey,
        );
      } else {
        list = await ProductService.getProductsByCatalogSubcategory(
          categoryId: widget.categoryId,
          subcategoryId: subcategoryId,
          legacyCategory: widget.categoryKey,
          legacySubcategory: widget.subcategoryKey,
        );
      }

      if (mounted) {
        setState(() {
          _products = list;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subcategoryLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_isSubcategoryView &&
                widget.subcategoryLabel != widget.categoryLabel)
              Text(
                widget.categoryLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    if (_error != null) {
      return LoadErrorState(
        error: _error,
        onRetry: _loadProducts,
        genericTitle: 'Error al cargar productos',
        genericMessage: 'No pudimos cargar esta categoría por el momento.',
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              const Text(
                'No hay en existencia',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isSubcategoryView
                    ? 'Actualmente no contamos con productos disponibles para la subcategoría "${widget.subcategoryLabel}".'
                    : 'Actualmente no contamos con productos disponibles para la categoría "${widget.categoryLabel}".',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Volver a Categorías'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _kPrimary,
      onRefresh: _loadProducts,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 315,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _products.length,
        itemBuilder: (context, i) => _ProductCard(product: _products[i]),
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  final bool _addingToCart = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: product.id),
        ),
      ),
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
            // ── Imagen + cart button + badge ──────────
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                children: [
                  // Imagen
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
                  // Badge de descuento en imagen (esquina sup izq)
                  if (product.hasDiscount)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 130),
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

                  // Botón cotización + carrito (esquina inf der) — estilo ML
                ],
              ),
            ),

            // ── Info del producto ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nombre
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

                  // Precio anterior tachado + % descuento (pastilla verde ML)
                  if (product.hasDiscount)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _kGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${product.discountPercent}% OFF',
                            style: const TextStyle(
                              fontSize: 10,
                              color: _kGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            product.formattedOldPrice,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF9CA3AF),
                              decoration: TextDecoration.lineThrough,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                  // Precio actual (grande y bold)
                  Text(
                    product.formattedPrice,
                    style: const TextStyle(
                      fontSize: 18.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      letterSpacing: -0.5,
                    ),
                  ),

                  // Marca/Modelo (si existe) — como 'Vendido por X' en ML
                  if ((product.brand ?? product.commercialBrand) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        (product.brand ?? product.commercialBrand)!,
                        style: const TextStyle(
                          fontSize: 11.0,
                          color: Color(0xFF6B7280),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  const SizedBox(height: 5),

                  // Envio
                  if (product.shippingInfo != null)
                    Row(
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 12,
                          color: product.hasFreeShipping
                              ? _kGreen
                              : const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            product.shippingInfo!,
                            style: TextStyle(
                              fontSize: 11,
                              color: product.hasFreeShipping
                                  ? _kGreen
                                  : const Color(0xFF6B7280),
                              fontWeight: product.hasFreeShipping
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

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
    child: Icon(
      Icons.medical_services_outlined,
      color: Colors.grey.shade300,
      size: 32,
    ),
  );
}
