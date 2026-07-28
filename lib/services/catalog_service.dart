import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog_category.dart';

class CatalogService {
  static final _db = Supabase.instance.client;
  static const _subcategoryImagesBucket = 'product-media';

  static String? resolveSubcategoryImageUrl(String? imagePath) {
    final value = imagePath?.trim();
    if (value == null || value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return value;
    }
    return _db.storage.from(_subcategoryImagesBucket).getPublicUrl(value);
  }

  static Future<List<CatalogCategory>> getCategories() async {
    final responses = await Future.wait([
      _db
          .from('categories')
          .select(
            'id, name, slug, image_url, show_before_slider, '
            'show_after_slider, sort_order',
          )
          .eq('is_active', true)
          .order('sort_order', ascending: true),
      _db
          .from('subcategories')
          .select('id, category_id, name, slug, image_path, sort_order')
          .eq('is_active', true)
          .order('sort_order', ascending: true),
    ]);

    final subcategories = (responses[1] as List)
        .map((row) => CatalogSubcategory.fromJson(row as Map<String, dynamic>))
        .toList();
    subcategories.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0
          ? order
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final subcategoriesByCategory = <String, List<CatalogSubcategory>>{};
    for (final subcategory in subcategories) {
      subcategoriesByCategory
          .putIfAbsent(subcategory.categoryId, () => [])
          .add(subcategory);
    }

    final categories = (responses[0] as List).map((row) {
      final json = row as Map<String, dynamic>;
      final categoryId = json['id'] as String;
      return CatalogCategory.fromJson(
        json,
        subcategories: subcategoriesByCategory[categoryId] ?? const [],
      );
    }).toList();
    categories.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0
          ? order
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return categories;
  }
}
