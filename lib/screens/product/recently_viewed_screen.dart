import 'package:flutter/material.dart';
import '../../services/search_service.dart';
import '../../models/product.dart';
import 'product_detail_screen.dart';
import 'manage_history_screen.dart';
import '../../utils/ui_helpers.dart';

class RecentlyViewedScreen extends StatefulWidget {
  const RecentlyViewedScreen({super.key});

  @override
  State<RecentlyViewedScreen> createState() => _RecentlyViewedScreenState();
}

class _RecentlyViewedScreenState extends State<RecentlyViewedScreen> {
  static const _kPrimary = Color(0xFF0D9488);
  static const _kNavy = Color(0xFF1E3A5F);
  static const _kGreyBg = Color(0xFFF8FAFC);

  List<Product> _historyList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final list = await SearchService.getRecentlyViewed();
      setState(() {
        _historyList = list;
      });
    } catch (e) {
      print('Error al obtener historial: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _removeItemFromHistory(Product product) async {
    try {
      await SearchService.removeFromRecentlyViewed(product.id);
      setState(() {
        _historyList.removeWhere((p) => p.id == product.id);
      });
      if (mounted) {
        UiHelpers.showFloatingDeleteToast(context, '${product.name} eliminado del historial.');
      }
    } catch (e) {
      if (mounted) {
        UiHelpers.showFloatingDeleteToast(context, 'Error al eliminar del historial.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGreyBg,
      appBar: AppBar(
        title: const Text(
          'Mi Historial',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => const ManageHistoryScreen(),
                    ),
                  )
                  .then((_) => _loadHistory()); // Refresh list when returning
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _historyList.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _historyList.length,
              itemBuilder: (context, index) {
                final product = _historyList[index];
                return _buildHistoryCard(product);
              },
            ),
    );
  }

  Widget _buildHistoryCard(Product product) {
    final String photoUrl =
        product.mainImageUrl ??
        (product.images.isNotEmpty ? product.images.first.filePath : '');
    final hasDiscount = product.hasDiscount;
    final oldPrice = product.oldPrice;
    final isUnavailable = _isUnavailable(product);
    final availabilityLabel = _availabilityLabel(product);
    final availabilityColor = isUnavailable
        ? const Color(0xFFEF4444)
        : availabilityLabel == 'Por confirmar'
        ? const Color(0xFFD97706)
        : product.stockStatusColor;

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) =>
                    ProductDetailScreen(productId: product.id),
              ),
            )
            .then(
              (_) => _loadHistory(),
            ); // Refresh list in case they navigate back
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
                // Product image Container
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
                            child: photoUrl.isNotEmpty
                                ? Image.network(
                                    photoUrl,
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
                      // Current price + discount percentage
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            product.formattedPrice,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (hasDiscount) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${product.discountPercent}% OFF',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF16A34A),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
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
                      // Availability info
                      Row(
                        children: [
                          Icon(
                            isUnavailable
                                ? Icons.highlight_off_rounded
                                : availabilityLabel == 'Por confirmar'
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 10,
                            color: availabilityColor,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              availabilityLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: availabilityColor,
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
                              onTap: () => _removeItemFromHistory(product),
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
      color: Colors.grey.shade100,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade400,
        size: 32,
      ),
    );
  }

  bool _isUnavailable(Product product) {
    final status = product.stockStatusLabel.toLowerCase();
    return status.contains('sin stock') || status.contains('agotado');
  }

  String _availabilityLabel(Product product) {
    final rawStatus = product.availabilityStatus?.trim();
    if (rawStatus == null || rawStatus.isEmpty) {
      return product.stock == null ? 'Por confirmar' : product.stockStatusLabel;
    }
    if (_isUnavailable(product)) return 'Agotado';
    return product.stockStatusLabel;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_rounded,
              color: Colors.grey.shade400,
              size: 64,
            ),
            const SizedBox(height: 12),
            const Text(
              'Historial vacío',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Aquí aparecerán los equipos médicos que visites en la aplicación.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
