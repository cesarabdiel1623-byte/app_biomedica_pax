import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../widgets/load_error_state.dart';
import '../home/widgets/product_card.dart';

const _kPrimary = Color(0xFF0D9488);
const _kBackground = Color(0xFFF8FAFC);

class PromotionProductsScreen extends StatefulWidget {
  const PromotionProductsScreen({
    super.key,
    required this.promotionId,
    this.title,
  });

  final String promotionId;
  final String? title;

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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await ProductService.getProductsByPromotion(
        widget.promotionId,
      );
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
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: Text(
          widget.title?.trim().isNotEmpty == true ? widget.title! : 'Promoción',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
        onRetry: _load,
        genericTitle: 'Error al cargar la promoción',
        genericMessage: 'No pudimos consultar sus productos por el momento.',
      );
    }
    if (_products.isEmpty) {
      return RefreshIndicator(
        color: _kPrimary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
      onRefresh: _load,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 315,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _products.length,
        itemBuilder: (_, index) => ProductCard(product: _products[index]),
      ),
    );
  }
}
