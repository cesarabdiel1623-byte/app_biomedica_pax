import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/review_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/review_video_tile.dart';
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

  Future<void> _loadAllReviews({bool showSpinner = true}) async {
    if (mounted && showSpinner) setState(() => _loading = true);

    try {
      final results = await Future.wait<dynamic>([
        ReviewService.getPendingReviews().timeout(const Duration(seconds: 30)),
        ReviewService.getClientReviews().timeout(const Duration(seconds: 30)),
        if (showSpinner) Future.delayed(const Duration(seconds: 2)),
      ]);

      if (!mounted) return;
      setState(() {
        _pendingReviews = results[0] as List<Map<String, dynamic>>;
        _completedReviews = results[1] as List<ProductReview>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _deleteReview(ProductReview review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar opinión'),
        content: const Text(
          'Esta acción eliminará tu calificación, comentario y fotos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: const Text(
              'Eliminar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ReviewService.deleteReview(review.id);
      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(context, 'Opinión eliminada.');
      await _loadAllReviews();
    } catch (_) {
      if (!mounted) return;
      UiHelpers.showFloatingDeleteToast(
        context,
        'No se pudo eliminar la opinión. Intenta nuevamente.',
      );
    }
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
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Hace unos momentos';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    if (diff.inDays < 30) return 'Hace ${diff.inDays} días';
    if (diff.inDays < 365) return 'Hace ${(diff.inDays / 30).floor()} meses';
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
      onRefresh: () => _loadAllReviews(showSpinner: false),
      color: _primary,
      child: ListView.separated(
        physics: UiHelpers.refreshScrollPhysics,
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
      onRefresh: () => _loadAllReviews(showSpinner: false),
      color: _primary,
      child: ListView.separated(
        physics: UiHelpers.refreshScrollPhysics,
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
            onDelete: () => _deleteReview(review),
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
      onRefresh: () => _loadAllReviews(showSpinner: false),
      color: _primary,
      child: ListView(
        physics: UiHelpers.refreshScrollPhysics,
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
    return Container(
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ProductThumbnail(url: product.mainImageUrl, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product.isActive == false) ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Colors.orange,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Publicación pausada',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ReviewsScreenState._navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.formattedPrice,
                          style: const TextStyle(
                            color: _ReviewsScreenState._navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  purchaseText,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12.5,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.star_rounded, size: 18),
                  label: const Text(
                    'Calificar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ReviewsScreenState._primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedReviewCard extends StatelessWidget {
  final ProductReview review;
  final String dateText;
  final VoidCallback onOpenProduct;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CompletedReviewCard({
    required this.review,
    required this.dateText,
    required this.onOpenProduct,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final product = review.product;
    final comment = review.comment?.trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _ReviewsScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                InkWell(
                  onTap: onOpenProduct,
                  borderRadius: BorderRadius.circular(8),
                  child: _ProductThumbnail(
                    url: product?.mainImageUrl,
                    size: 56,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: onOpenProduct,
                    borderRadius: BorderRadius.circular(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product?.isActive == false) ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Colors.orange,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Publicación pausada',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          product?.name ?? 'Equipo médico',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ReviewsScreenState._navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        if (product != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            product.formattedPrice,
                            style: const TextStyle(
                              color: _ReviewsScreenState._navy,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: Color(0xFF6B7280),
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onSelected: (value) {
                    if (value == 'edit' && onEdit != null) {
                      onEdit!();
                    } else if (value == 'delete' && onDelete != null) {
                      onDelete!();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              color: _ReviewsScreenState._primary,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text('Editar opinión'),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFDC2626),
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Eliminar opinión',
                              style: TextStyle(color: Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ...List.generate(
                      5,
                      (index) => Icon(
                        index < review.rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: _ReviewsScreenState._star,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      dateText,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    comment,
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
                if (review.images.isNotEmpty || review.videos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: review.images.length + review.videos.length,
                      itemBuilder: (context, i) {
                        if (i >= review.images.length) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ReviewVideoTile(
                              url: review.videos[i - review.images.length],
                            ),
                          );
                        }
                        return GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.all(12),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    InteractiveViewer(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          review.images[i],
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                              image: DecorationImage(
                                image: NetworkImage(review.images[i]),
                                fit: BoxFit.cover,
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: url != null && url!.isNotEmpty
            ? UiHelpers.networkImage(
                url!,
                fit: BoxFit.cover,
                iconSize: size * 0.45,
              )
            : Icon(
                Icons.shopping_bag_outlined,
                color: _ReviewsScreenState._primary,
                size: size * 0.45,
              ),
      ),
    );
  }
}
