import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/responsive_grid.dart';
import '../../widgets/load_error_state.dart';
import '../home/widgets/product_card.dart';

const _kPrimary = Color(0xFF024C8B);
const _kBackground = Color(0xFFF7F9FC);

class PromotionProductsScreen extends StatefulWidget {
  const PromotionProductsScreen({
    super.key,
    this.promotionId,
    this.title,
    this.initialProducts,
  });

  final String? promotionId;
  final String? title;
  final List<Product>? initialProducts;

  @override
  State<PromotionProductsScreen> createState() =>
      _PromotionProductsScreenState();
}

class _PromotionProductsScreenState extends State<PromotionProductsScreen> {
  List<Product> _products = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialProducts != null && widget.initialProducts!.isNotEmpty) {
      _products = widget.initialProducts!;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final Future<List<Product>> fetchFuture;
      if (widget.promotionId != null && widget.promotionId!.isNotEmpty) {
        fetchFuture = ProductService.getProductsByPromotion(
          widget.promotionId!,
        );
      } else {
        fetchFuture = ProductService.getAllProducts().then(
          (list) => list.where((p) => p.hasDiscount).toList(),
        );
      }
      final results = await Future.wait([
        fetchFuture.timeout(const Duration(seconds: 30)),
        if (showSpinner) Future.delayed(const Duration(seconds: 2)),
      ]);
      final products = results[0] as List<Product>;
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _loading ? Colors.white : _kBackground,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title?.trim().isNotEmpty == true
              ? widget.title!
              : 'Promociones del Día',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }
    if (_error != null) {
      return LoadErrorState(
        error: _error,
        onRetry: _load,
        genericTitle: 'Error al cargar la promoción',
        genericMessage: 'No pudimos consultar sus productos por el momento.',
      );
    }
    if (_products.isEmpty) {
      return RefreshIndicator(
        color: _kPrimary,
        onRefresh: () => _load(showSpinner: false),
        child: ListView(
          physics: UiHelpers.refreshScrollPhysics,
          children: const [
            SizedBox(height: 220),
            Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Center(
              child: Text('No hay productos disponibles en esta promoción.'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _kPrimary,
      onRefresh: () => _load(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          return GridView.builder(
            physics: UiHelpers.refreshScrollPhysics,
            padding: const EdgeInsets.all(10),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: ResponsiveGrid.productColumnCount(
                constraints.maxWidth - 20,
              ),
              mainAxisExtent: ResponsiveGrid.productCardExtent(textScale),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _products.length,
            itemBuilder: (_, index) => ProductCard(product: _products[index]),
          );
        },
      ),
    );
  }
}
