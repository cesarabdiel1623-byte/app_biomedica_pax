import 'package:flutter/material.dart';

import '../../models/catalog_category.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';
import '../home/widgets/product_card.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);

class CategoryCatalogScreen extends StatefulWidget {
  const CategoryCatalogScreen({super.key, required this.category});

  final CatalogCategory category;

  @override
  State<CategoryCatalogScreen> createState() => _CategoryCatalogScreenState();
}

class _CategoryCatalogScreenState extends State<CategoryCatalogScreen> {
  List<Product> _products = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

    try {
      final results = await Future.wait([
        ProductService.getProductsByCatalogCategory(
          categoryId: widget.category.id,
          legacyCategory: widget.category.productCategoryKey,
        ).timeout(const Duration(seconds: 30)),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 26),
          tooltip: 'Regresar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
        onRetry: _loadProducts,
        genericTitle: 'Error al cargar productos',
        genericMessage: 'No pudimos cargar esta categoría por el momento.',
      );
    }

    if (_products.isEmpty) {
      return RefreshIndicator(
        color: _kPrimary,
        backgroundColor: Colors.white,
        displacement: 42,
        triggerMode: RefreshIndicatorTriggerMode.onEdge,
        onRefresh: () => _loadProducts(showSpinner: false),
        child: ListView(
          physics: UiHelpers.refreshScrollPhysics,
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
            Icon(
              Icons.shopping_cart_outlined,
              size: 58,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 18),
            const Text(
              'No hay productos disponibles',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kNavy,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Los productos de ${widget.category.name} aparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final sections = _buildSections();
    return RefreshIndicator(
      color: _kPrimary,
      backgroundColor: Colors.white,
      displacement: 42,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      onRefresh: () => _loadProducts(showSpinner: false),
      child: ListView.builder(
        physics: UiHelpers.refreshScrollPhysics,
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: sections.length,
        itemBuilder: (context, index) => _ProductSection(
          section: sections[index],
          icon: _categoryIcon(sections[index].slug),
        ),
      ),
    );
  }

  List<_CatalogProductSection> _buildSections() {
    final subcategories = [...widget.category.subcategories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (subcategories.isEmpty) {
      return [
        _CatalogProductSection(
          title: widget.category.name,
          slug: widget.category.slug,
          products: _products,
        ),
      ];
    }

    final assignedProductIds = <String>{};
    final sections = <_CatalogProductSection>[];
    for (final subcategory in subcategories) {
      final acceptedKeys = {
        _normalize(subcategory.slug),
        _normalize(subcategory.name),
      };
      final products = _products.where((product) {
        final matches =
            product.subcategoryId == subcategory.id ||
            (product.subcategoryId == null &&
                acceptedKeys.contains(_normalize(product.subcategory)));
        if (matches) assignedProductIds.add(product.id);
        return matches;
      }).toList();

      if (products.isNotEmpty) {
        sections.add(
          _CatalogProductSection(
            title: subcategory.name,
            slug: subcategory.slug,
            products: products,
          ),
        );
      }
    }

    final unassigned = _products
        .where((product) => !assignedProductIds.contains(product.id))
        .toList();
    if (unassigned.isNotEmpty) {
      sections.add(
        _CatalogProductSection(
          title: sections.isEmpty ? widget.category.name : 'Otros productos',
          slug: widget.category.slug,
          products: unassigned,
        ),
      );
    }
    return sections;
  }

  String _normalize(String? value) {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  IconData _categoryIcon(String value) {
    final key = _normalize(value);
    if (key.contains('ultrason') || key.contains('monitor')) {
      return Icons.monitor_heart_outlined;
    }
    if (key.contains('consum')) return Icons.water_drop_outlined;
    if (key.contains('refacc')) return Icons.build_outlined;
    if (key.contains('accesor')) return Icons.extension_outlined;
    if (key.contains('servic')) return Icons.settings_suggest_outlined;
    return Icons.medical_services_outlined;
  }
}

class _ProductSection extends StatelessWidget {
  const _ProductSection({required this.section, required this.icon});

  final _CatalogProductSection section;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF6B7280), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.title,
                  style: const TextStyle(
                    color: _kNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 320,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: section.products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => SizedBox(
              width: 185,
              child: ProductCard(
                product: section.products[index],
                enableHero: false,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogProductSection {
  const _CatalogProductSection({
    required this.title,
    required this.slug,
    required this.products,
  });

  final String title;
  final String slug;
  final List<Product> products;
}
