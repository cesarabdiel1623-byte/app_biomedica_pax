import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/catalog_category.dart';

void main() {
  group('CatalogCategory', () {
    test('parses display flags and related subcategories', () {
      const subcategory = CatalogSubcategory(
        id: 'sub-1',
        categoryId: 'cat-1',
        name: 'Monitores',
        slug: 'monitores_medicos',
        sortOrder: 1,
      );

      final category = CatalogCategory.fromJson(
        {
          'id': 'cat-1',
          'name': 'Equipo médico',
          'slug': 'equipo-medico',
          'show_before_slider': false,
          'show_after_slider': true,
          'sort_order': 2,
        },
        subcategories: const [subcategory],
      );

      expect(category.showBeforeSlider, isFalse);
      expect(category.showAfterSlider, isTrue);
      expect(category.subcategories, hasLength(1));
      expect(category.productCategoryKey, 'equipo_medico');
    });

    test('adapts plural catalog slugs to product enum values', () {
      final category = CatalogCategory.fromJson({
        'id': 'cat-2',
        'name': 'Refacciones',
        'slug': 'refacciones',
      });

      expect(category.productCategoryKey, 'refaccion');
    });
  });
}
