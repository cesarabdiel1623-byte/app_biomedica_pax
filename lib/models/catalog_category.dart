class CatalogSubcategory {
  const CatalogSubcategory({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.slug,
    required this.sortOrder,
    this.imagePath,
  });

  final String id;
  final String categoryId;
  final String name;
  final String slug;
  final String? imagePath;
  final int sortOrder;

  factory CatalogSubcategory.fromJson(Map<String, dynamic> json) {
    return CatalogSubcategory(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String? ?? 'Subcategoría',
      slug: json['slug'] as String? ?? '',
      imagePath: json['image_path'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.showBeforeSlider,
    required this.showAfterSlider,
    required this.sortOrder,
    required this.subcategories,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String slug;
  final String? imageUrl;
  final bool showBeforeSlider;
  final bool showAfterSlider;
  final int sortOrder;
  final List<CatalogSubcategory> subcategories;

  factory CatalogCategory.fromJson(
    Map<String, dynamic> json, {
    List<CatalogSubcategory> subcategories = const [],
  }) {
    return CatalogCategory(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Categoría',
      slug: json['slug'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      showBeforeSlider: json['show_before_slider'] as bool? ?? false,
      showAfterSlider: json['show_after_slider'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      subcategories: subcategories,
    );
  }

  /// Adapts the catalog slug to the legacy enum currently stored in products.
  String get productCategoryKey {
    const legacyKeys = {
      'equipo-medico': 'equipo_medico',
      'ultrasonido-humano': 'ultrasonido_humano',
      'ultrasonido-veterinario': 'ultrasonido_veterinario',
      'consumibles': 'consumible',
      'refacciones': 'refaccion',
      'accesorios': 'accesorio',
      'servicios': 'servicio',
    };
    return legacyKeys[slug] ?? slug.replaceAll('-', '_');
  }
}
