import 'package:flutter/material.dart';
import '../../services/favorite_service.dart';
import '../../services/cart_service.dart';
import '../../models/product.dart';
import '../../utils/ui_helpers.dart';
import 'product_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  static const _kPrimary = Color(0xFF0D9488);
  static const _kNavy = Color(0xFF1E3A5F);
  static const _kGreyBg = Color(0xFFF8FAFC);

  List<Product> _favorites = [];
  bool _loading = true;
  String? _addingCartProductId;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _loading = true);
    }
    try {
      final results = await Future.wait([
        FavoriteService.getFavorites().timeout(const Duration(seconds: 30)),
        Future.delayed(const Duration(seconds: 2)),
      ]);
      if (mounted) {
        setState(() {
          _favorites = results[0] as List<Product>;
        });
      }
    } catch (e) {
      debugPrint('Error al obtener favoritos: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _removeFavorite(Product product) async {
    try {
      final removed = await FavoriteService.toggleFavorite(product.id);
      if (!removed) {
        setState(() {
          _favorites.removeWhere((p) => p.id == product.id);
        });
        if (mounted) {
          UiHelpers.showRemoveFavoriteToast(context, product.name);
        }
      }
    } catch (e) {
      if (mounted) {
        UiHelpers.showErrorToast(context, 'Error al modificar favoritos.');
      }
    }
  }

  Future<void> _addToCart(Product product) async {
    if (_addingCartProductId != null) return;
    if (_isUnavailable(product)) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(productId: product.id),
            ),
          )
          .then((_) => _loadFavorites());
      return;
    }
    setState(() => _addingCartProductId = product.id);
    try {
      await CartService.addToCart(product.id, quantity: 1);
      if (mounted) {
        UiHelpers.showAddToCartSuccessToast(context, product.name, 1);
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString();
        if (errStr.contains('stock_limit_reached')) {
          final stock =
              int.tryParse(errStr.split(':').last) ?? product.stock ?? 0;
          UiHelpers.showStockLimitToast(context, stock);
        } else {
          UiHelpers.showErrorToast(
            context,
            'Error al agregar al carrito: ${errStr.replaceAll('Exception: ', '')}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _addingCartProductId = null);
      }
    }
  }

  bool _isUnavailable(Product product) {
    final status = product.stockStatusLabel.toLowerCase();
    return status.contains('sin stock') || status.contains('agotado');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGreyBg,
      appBar: AppBar(
        title: const Text(
          'Favoritos',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _favorites.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: () => _loadFavorites(showSpinner: false),
              color: _kPrimary,
              child: ListView.builder(
                physics: UiHelpers.refreshScrollPhysics,
                padding: const EdgeInsets.all(16),
                itemCount: _favorites.length,
                itemBuilder: (context, index) {
                  final product = _favorites[index];
                  return _buildFavoriteCard(product);
                },
              ),
            ),
    );
  }

  Widget _buildFavoriteCard(Product product) {
    final hasDiscount = product.hasDiscount;
    final oldPrice = product.oldPrice;
    final isUnavailable = _isUnavailable(product);

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) =>
                    ProductDetailScreen(productId: product.id),
              ),
            )
            .then((_) => _loadFavorites());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Product image
                SizedBox(
                  width: 140,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            color: const Color(0xFFF8FAFC),
                            padding: const EdgeInsets.all(2),
                            child: product.mainImageUrl != null
                                ? Image.network(
                                    product.mainImageUrl!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        _buildPlaceholderImage(),
                                  )
                                : _buildPlaceholderImage(),
                          ),
                        ),
                      ),
                      if (hasDiscount && product.discountPercent > 0)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${product.discountPercent}% OFF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Product details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF1F2937),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Old price
                      if (hasDiscount && oldPrice != null) ...[
                        Text(
                          product.formattedOldPrice,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF9CA3AF),
                            decoration: TextDecoration.lineThrough,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                      ],
                      // Current price and discount stay on separate lines on narrow cards.
                      Text(
                        product.formattedPrice,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${product.discountPercent}% OFF',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      // Shipping Info
                      if (product.hasFreeShipping)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.local_shipping_outlined,
                                size: 10,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 3),
                              const Expanded(
                                child: Text(
                                  'Envío gratis',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Stock info
                      Row(
                        children: [
                          Icon(
                            isUnavailable
                                ? Icons.highlight_off_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 10,
                            color: product.stockStatusColor,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              isUnavailable
                                  ? 'Agotado'
                                  : product.stockStatusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: product.stockStatusColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _addingCartProductId != null
                                  ? null
                                  : () => _addToCart(product),
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _kPrimary,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _kPrimary.withValues(alpha: 0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _addingCartProductId == product.id
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 1.5,
                                            ),
                                          )
                                        : Icon(
                                            isUnavailable
                                                ? Icons.visibility_outlined
                                                : Icons.add_shopping_cart,
                                            color: Colors.white,
                                            size: 12,
                                          ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isUnavailable
                                          ? 'Ver producto'
                                          : 'Agregar',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _removeFavorite(product),
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFFEE2E2),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      color: Color(0xFFEF4444),
                                      size: 12,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Eliminar',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 100,
      height: 100,
      color: Colors.grey.shade100,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade400,
        size: 32,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              color: Colors.grey.shade400,
              size: 64,
            ),
            const SizedBox(height: 12),
            const Text(
              'Aún no tienes favoritos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Agrega equipos médicos a tus favoritos pulsando el icono de corazón en su ficha de detalle.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
