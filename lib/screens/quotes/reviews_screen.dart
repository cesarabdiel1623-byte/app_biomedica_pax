import 'package:flutter/material.dart';
import '../../services/review_service.dart';
import '../product/product_detail_screen.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  static const _kPrimary = Color(0xFF0D9488);
  static const _kNavy = Color(0xFF1E3A5F);
  static const _kGreyBg = Color(0xFFF8FAFC);

  List<ProductReview> _reviews = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() => _loading = true);
    try {
      final list = await ReviewService.getClientReviews();
      setState(() {
        _reviews = list;
      });
    } catch (e) {
      print('Error al obtener opiniones del cliente: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGreyBg,
      appBar: AppBar(
        title: const Text(
          'Mis Opiniones',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
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
          : _reviews.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadReviews,
                  color: _kPrimary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reviews.length,
                    itemBuilder: (context, index) {
                      final rev = _reviews[index];
                      return _buildReviewCard(rev);
                    },
                  ),
                ),
    );
  }

  Widget _buildReviewCard(ProductReview rev) {
    final dateStr = '${rev.createdAt.day}/${rev.createdAt.month}/${rev.createdAt.year}';
    final hasComment = rev.comment != null && rev.comment!.trim().isNotEmpty;
    final hasImages = rev.images.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Header
            GestureDetector(
              onTap: () {
                if (rev.productId.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ProductDetailScreen(productId: rev.productId),
                    ),
                  );
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.shopping_bag_outlined, color: _kPrimary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rev.product?.name ?? 'Equipo Médico',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: _kPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _kPrimary, size: 16),
                ],
              ),
            ),
            const Divider(height: 20, thickness: 1),
            // Star rating row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(5, (starIdx) {
                    return Icon(
                      starIdx < rev.rating ? Icons.star_rounded : Icons.star_border_rounded,
                      color: const Color(0xFFFBBF24), // Amber star
                      size: 20,
                    );
                  }),
                ),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
            if (hasComment) ...[
              const SizedBox(height: 12),
              Text(
                rev.comment!,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF334155),
                  height: 1.4,
                ),
              ),
            ],
            if (hasImages) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 70,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: rev.images.length,
                  itemBuilder: (context, imgIdx) {
                    final url = rev.images[imgIdx];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 70,
                            height: 70,
                            color: Colors.grey.shade100,
                            child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: 20),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star_border_rounded,
                color: _kPrimary,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aún no has escrito opiniones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tus opiniones y valoraciones sobre los equipos médicos que compres aparecerán en esta sección.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
