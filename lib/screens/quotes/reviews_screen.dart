import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/review_service.dart';
import '../../utils/ui_helpers.dart';
import '../product/product_detail_screen.dart';
import '../product/write_review_screen.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  static const _primary = Color(0xFF0D9488);
  static const _navy = Color(0xFF172B4D);
  static const _background = Color(0xFFF5F7FA);
  static const _border = Color(0xFFE5E7EB);
  static const _star = Color(0xFFF6B800);

  List<Map<String, dynamic>> _pendingReviews = [];
  List<ProductReview> _completedReviews = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllReviews();
  }

  Future<void> _loadAllReviews() async {
    if (mounted) setState(() => _loading = true);

    final results = await Future.wait<dynamic>([
      ReviewService.getPendingReviews(),
      ReviewService.getClientReviews(),
    ]);

    if (!mounted) return;
    setState(() {
      _pendingReviews = results[0] as List<Map<String, dynamic>>;
      _completedReviews = results[1] as List<ProductReview>;
      _loading = false;
    });
  }

  Future<void> _openEditor(Product product, [ProductReview? review]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            WriteReviewScreen(product: product, existingReview: review),
      ),
    );

    if (changed == true) await _loadAllReviews();
  }

  void _openProduct(String productId) {
    if (productId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: productId),
      ),
    );
  }

  String _formatPurchasedDate(DateTime? date) {
    if (date == null) return 'Compra reciente';
    return 'Comprado el ${date.day} ${_month(date.month)}';
  }

  String _formatReviewDate(DateTime date) {
    return '${date.day} ${_month(date.month)} ${date.year}';
  }

  String _month(int month) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          title: const Text(
            'Mis opiniones',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          elevation: 0,
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFCBE9E6),
            labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Realizadas'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : TabBarView(
                children: [_buildPendingList(), _buildCompletedList()],
              ),
      ),
    );
  }

  Widget _buildPendingList() {
    if (_pendingReviews.isEmpty) {
      return _refreshableEmpty(
        icon: Icons.task_alt_rounded,
        title: 'Estás al día',
        message: 'No tienes productos pendientes por calificar.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllReviews,
      color: _primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        itemCount: _pendingReviews.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          final item = _pendingReviews[index];
          return _PendingReviewCard(
            product: item['product'] as Product,
            purchaseText: _formatPurchasedDate(
              item['purchasedAt'] as DateTime?,
            ),
            onReview: () => _openEditor(item['product'] as Product),
            onOpenProduct: () {
              final product = item['product'] as Product;
              _openProduct(product.id);
            },
          );
        },
      ),
    );
  }

  Widget _buildCompletedList() {
    if (_completedReviews.isEmpty) {
      return _refreshableEmpty(
        icon: Icons.star_outline_rounded,
        title: 'Aún no tienes opiniones',
        message: 'Las opiniones que publiques aparecerán aquí.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllReviews,
      color: _primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        itemCount: _completedReviews.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          final review = _completedReviews[index];
          return _CompletedReviewCard(
            review: review,
            dateText: _formatReviewDate(review.createdAt),
            onOpenProduct: () => _openProduct(review.productId),
            onEdit: review.product == null
                ? null
                : () => _openEditor(review.product!, review),
          );
        },
      ),
    );
  }

  Widget _refreshableEmpty({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return RefreshIndicator(
      onRefresh: _loadAllReviews,
      color: _primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.58,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: const Color(0xFF9CA3AF), size: 64),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingReviewCard extends StatelessWidget {
  final Product product;
  final String purchaseText;
  final VoidCallback onReview;
  final VoidCallback onOpenProduct;

  const _PendingReviewCard({
    required this.product,
    required this.purchaseText,
    required this.onReview,
    required this.onOpenProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onOpenProduct,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _ReviewsScreenState._border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProductThumbnail(url: product.mainImageUrl, size: 76),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ReviewsScreenState._navy,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          purchaseText,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.star_outline_rounded, size: 21),
                  label: const Text(
                    'Calificar producto',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ReviewsScreenState._primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedReviewCard extends StatelessWidget {
  final ProductReview review;
  final String dateText;
  final VoidCallback onOpenProduct;
  final VoidCallback? onEdit;

  const _CompletedReviewCard({
    required this.review,
    required this.dateText,
    required this.onOpenProduct,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final product = review.product;
    final comment = review.comment?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _ReviewsScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenProduct,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProductThumbnail(url: product?.mainImageUrl, size: 68),
                const SizedBox(width: 13),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      product?.name ?? 'Equipo médico',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        color: _ReviewsScreenState._navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ...List.generate(
                5,
                (index) => Icon(
                  index < review.rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: _ReviewsScreenState._star,
                  size: 23,
                ),
              ),
              const Spacer(),
              Text(
                dateText,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              comment,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
          if (onEdit != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: _ReviewsScreenState._primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('Editar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  final String? url;
  final double size;

  const _ProductThumbnail({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _ReviewsScreenState._border),
      ),
      child: url != null && url!.isNotEmpty
          ? UiHelpers.networkImage(
              url!,
              fit: BoxFit.contain,
              iconSize: size * 0.35,
            )
          : Icon(
              Icons.medical_services_outlined,
              color: Colors.grey.shade300,
              size: size * 0.42,
            ),
    );
  }
}
