import 'package:flutter/material.dart';
import '../../services/review_service.dart';

class AllProductReviewsScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const AllProductReviewsScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<AllProductReviewsScreen> createState() => _AllProductReviewsScreenState();
}

class _AllProductReviewsScreenState extends State<AllProductReviewsScreen> {
  static const _kPrimary = Color(0xFF0D9488);
  static const _kNavy = Color(0xFF1E3A5F);
  static const _kGreyBg = Color(0xFFF8FAFC);

  List<ProductReview> _reviews = [];
  bool _loading = true;
  String _selectedFilter = 'all'; // 'all', '5', '4', '3', '2', '1'

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() => _loading = true);
    try {
      final list = await ReviewService.getReviews(widget.productId);
      setState(() {
        _reviews = list;
      });
    } catch (e) {
      debugPrint('Error loading reviews: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  double get _averageRating {
    if (_reviews.isEmpty) return 0.0;
    final total = _reviews.fold<double>(0.0, (sum, rev) => sum + rev.rating);
    return total / _reviews.length;
  }

  Map<int, int> get _ratingCounts {
    final counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final rev in _reviews) {
      if (counts.containsKey(rev.rating)) {
        counts[rev.rating] = counts[rev.rating]! + 1;
      }
    }
    return counts;
  }

  List<ProductReview> get _filteredReviews {
    if (_selectedFilter == 'all') {
      return _reviews;
    }
    final targetRating = int.tryParse(_selectedFilter);
    if (targetRating == null) return _reviews;
    return _reviews.where((r) => r.rating == targetRating).toList();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _ratingCounts;
    final totalReviews = _reviews.length;

    return Scaffold(
      backgroundColor: _kGreyBg,
      appBar: AppBar(
        title: const Text(
          'Opiniones del producto',
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
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kPrimary))
            : Column(
                children: [
                  // Product info header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_bag_outlined, color: _kPrimary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.productName,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: _kNavy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),

                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadReviews,
                      color: _kPrimary,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_reviews.isNotEmpty) ...[
                            // Ratings summary card
                            _buildRatingsSummaryCard(counts, totalReviews),
                            const SizedBox(height: 16),
                            // Filter bar
                            _buildFilterBar(),
                            const SizedBox(height: 16),
                          ],
                          
                          _filteredReviews.isEmpty
                              ? _buildEmptyState()
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _filteredReviews.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                                  itemBuilder: (context, index) {
                                    final rev = _filteredReviews[index];
                                    return _buildReviewCard(rev);
                                  },
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRatingsSummaryCard(Map<int, int> counts, int totalReviews) {
    final avg = _averageRating;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Large number rating
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      avg.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: _kNavy),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (starIdx) {
                        return Icon(
                          starIdx < avg.round() ? Icons.star_rounded : Icons.star_border_rounded,
                          color: const Color(0xFFFBBF24),
                          size: 16,
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      totalReviews == 1 ? '1 opinión' : '$totalReviews opiniones',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Vertical divider
              Container(
                height: 100,
                width: 1,
                color: Colors.grey.shade200,
              ),
              const SizedBox(width: 16),
              // Stars progress bars
              Expanded(
                flex: 6,
                child: Column(
                  children: List.generate(5, (index) {
                    final stars = 5 - index;
                    final count = counts[stars] ?? 0;
                    final pct = totalReviews == 0 ? 0.0 : count / totalReviews;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text('$stars', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kNavy)),
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 12),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: Colors.grey.shade100,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFBBF24)),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 16,
                            child: Text(
                              '$count',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      {'label': 'Todas', 'value': 'all'},
      {'label': '5 ★', 'value': '5'},
      {'label': '4 ★', 'value': '4'},
      {'label': '3 ★', 'value': '3'},
      {'label': '2 ★', 'value': '2'},
      {'label': '1 ★', 'value': '1'},
    ];

    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['value'];

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                filter['label']!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
              ),
              selected: isSelected,
              selectedColor: _kPrimary,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: isSelected ? _kPrimary : Colors.grey.shade300),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _selectedFilter = filter['value']!;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewCard(ProductReview rev) {
    final dateStr = '${rev.createdAt.day.toString().padLeft(2, '0')}/${rev.createdAt.month.toString().padLeft(2, '0')}/${rev.createdAt.year}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: List.generate(5, (starIdx) {
                  return Icon(
                    starIdx < rev.rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: const Color(0xFFFBBF24),
                    size: 18,
                  );
                }),
              ),
              Text(
                dateStr,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rev.clientName,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          if (rev.comment != null && rev.comment!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              rev.comment!,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
            ),
          ],
          if (rev.images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 56,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: rev.images.length,
                itemBuilder: (_, i) {
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
                                    rev.images[i],
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                  onPressed: () => Navigator.of(context).pop(),
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
                        border: Border.all(color: Colors.grey.shade100),
                        image: DecorationImage(image: NetworkImage(rev.images[i]), fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No hay opiniones para este filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
