import 'package:flutter/material.dart';

import '../../../models/catalog_category.dart';
import '../../../services/catalog_service.dart';
import '../../../utils/ui_helpers.dart';
import '../../../widgets/load_error_state.dart';
import '../../../widgets/standard_section_header.dart';
import '../../product/category_products_screen.dart';
import '../home_screen.dart';

const _kPrimary = Color(0xFF0D9488);
const _kBackground = Color(0xFFF8FAFC);

class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});

  @override
  State<CategoriesTab> createState() => CategoriesTabState();
}

class CategoriesTabState extends State<CategoriesTab> {
  List<CatalogCategory> _categories = const [];
  int _selectedIndex = 0;
  bool _loading = true;
  String? _error;
  String? _requestedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  void selectCategory(String categoryId) {
    _requestedCategoryId = categoryId;
    final index = _categories.indexWhere(
      (category) => category.id == categoryId,
    );
    if (index >= 0 && mounted) {
      setState(() => _selectedIndex = index);
    }
  }

  Future<void> _loadCategories() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final categories = await CatalogService.getCategories();
      if (!mounted) return;
      final requestedIndex = _requestedCategoryId == null
          ? -1
          : categories.indexWhere(
              (category) => category.id == _requestedCategoryId,
            );
      setState(() {
        _categories = categories;
        _selectedIndex = requestedIndex >= 0
            ? requestedIndex
            : categories.isEmpty
            ? 0
            : _selectedIndex.clamp(0, categories.length - 1);
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

  IconData _iconFor(String value) {
    final key = value.toLowerCase();
    if (key.contains('ultrason') || key.contains('monitor')) {
      return Icons.monitor_heart_outlined;
    }
    if (key.contains('consum') ||
        key.contains('gel') ||
        key.contains('liquid')) {
      return Icons.water_drop_outlined;
    }
    if (key.contains('refacc') ||
        key.contains('repuesto') ||
        key.contains('cable')) {
      return Icons.build_outlined;
    }
    if (key.contains('accesor')) return Icons.extension_outlined;
    if (key.contains('servic') || key.contains('manten')) {
      return Icons.settings_suggest_outlined;
    }
    if (key.contains('equipo') || key.contains('medic')) {
      return Icons.medical_services_outlined;
    }
    return Icons.category_outlined;
  }

  bool _isRemoteImage(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  void _openProducts(
    CatalogCategory category, {
    CatalogSubcategory? subcategory,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryProductsScreen(
          categoryId: category.id,
          categoryKey: category.productCategoryKey,
          categoryLabel: category.name,
          subcategoryLabel: subcategory?.name ?? category.name,
          subcategoryId: subcategory?.id,
          subcategoryKey: subcategory?.slug,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _categories.isNotEmpty
        ? _categories[_selectedIndex.clamp(0, _categories.length - 1)]
        : null;

    return Column(
      children: [
        StandardSectionHeader(
          title: current?.name ?? 'Categorías',
          backgroundColor: _kPrimary,
          backTooltip: 'Volver al inicio',
          onBack: () => HomeScreen.showTab(0),
        ),
        Expanded(
          child: _buildBody(current),
        ),
      ],
    );
  }

  Widget _buildBody(CatalogCategory? current) {
    if (_loading) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: CircularProgressIndicator(color: _kPrimary),
        ),
      );
    }

    if (_error != null && _categories.isEmpty) {
      return LoadErrorState(
        error: _error,
        onRetry: _loadCategories,
        genericTitle: 'Error al cargar categorías',
        genericMessage: 'No pudimos consultar las categorías por el momento.',
      );
    }

    if (_categories.isEmpty || current == null) {
      return RefreshIndicator(
        color: _kPrimary,
        onRefresh: _loadCategories,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Icon(Icons.category_outlined, color: Colors.grey, size: 48),
            SizedBox(height: 12),
            Center(child: Text('No hay categorías disponibles')),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategorySidebar(),
        Expanded(
          child: current.subcategories.isEmpty
              ? _buildCategoryOverview(current)
              : _buildSubcategoryGrid(current),
        ),
      ],
    );
  }


  Widget _buildCategorySidebar() {
    return Container(
      width: 84,
      color: Colors.white,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _categories.length,
        itemBuilder: (_, index) {
          final category = _categories[index];
          final active = index == _selectedIndex;

          return InkWell(
            onTap: () => setState(() => _selectedIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: const BoxConstraints(minHeight: 82),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFF3F4F6) : Colors.white,
                border: Border(
                  left: BorderSide(
                    color: active
                        ? const Color(0xFF9CA3AF)
                        : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCategoryVisual(category),
                  const SizedBox(height: 6),
                  Text(
                    category.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.2,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active
                          ? const Color(0xFF0F172A)
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryVisual(CatalogCategory category) {
    if (_isRemoteImage(category.imageUrl)) {
      return SizedBox(
        width: 30,
        height: 30,
        child: UiHelpers.networkImage(
          category.imageUrl!,
          fit: BoxFit.contain,
          iconSize: 18,
        ),
      );
    }

    return Icon(_iconFor(category.slug), size: 23, color: Colors.grey.shade500);
  }

  Widget _buildSubcategoryGrid(CatalogCategory category) {
    return Container(
      color: _kBackground,
      padding: const EdgeInsets.all(8),
      child: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _loadCategories,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 8,
            mainAxisExtent: 132,
          ),
          itemCount: category.subcategories.length,
          itemBuilder: (_, index) {
            final subcategory = category.subcategories[index];
            final imageUrl = CatalogService.resolveSubcategoryImageUrl(
              subcategory.imagePath,
            );

            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openProducts(category, subcategory: subcategory),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: imageUrl != null
                          ? UiHelpers.networkImage(
                              imageUrl,
                              fit: BoxFit.contain,
                              iconSize: 26,
                            )
                          : Icon(
                              _iconFor(subcategory.slug),
                              color: Colors.grey.shade500,
                              size: 28,
                            ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        subcategory.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.2,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryOverview(CatalogCategory category) {
    return RefreshIndicator(
      color: _kPrimary,
      onRefresh: _loadCategories,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 90),
          Center(
            child: Icon(
              _iconFor(category.slug),
              color: Colors.grey.shade400,
              size: 58,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            category.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Consulta todos los productos disponibles en esta categoría.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: FilledButton.icon(
              onPressed: () => _openProducts(category),
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text('Ver productos'),
            ),
          ),
        ],
      ),
    );
  }
}
