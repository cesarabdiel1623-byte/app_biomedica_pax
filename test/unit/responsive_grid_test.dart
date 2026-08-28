import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/utils/responsive_grid.dart';

void main() {
  group('ResponsiveGrid product layout', () {
    test('keeps two columns on compact phones', () {
      expect(ResponsiveGrid.productColumnCount(296), 2);
      expect(ResponsiveGrid.productColumnCount(360), 2);
    });

    test('adds columns progressively on tablets', () {
      expect(ResponsiveGrid.productColumnCount(600), 3);
      expect(ResponsiveGrid.productColumnCount(800), 4);
      expect(ResponsiveGrid.productColumnCount(1200), 6);
    });

    test('adds vertical room when system text is enlarged', () {
      expect(ResponsiveGrid.productCardExtent(1), 330);
      expect(ResponsiveGrid.productCardExtent(1.5), 392.5);
      expect(ResponsiveGrid.productCardExtent(2), 455);
    });
  });

  group('ResponsiveGrid subcategory layout', () {
    test('adapts columns from narrow phones to tablets', () {
      expect(ResponsiveGrid.subcategoryColumnCount(220), 2);
      expect(ResponsiveGrid.subcategoryColumnCount(360), 3);
      expect(ResponsiveGrid.subcategoryColumnCount(600), 5);
      expect(ResponsiveGrid.subcategoryColumnCount(800), 6);
    });

    test('adds vertical room when system text is enlarged', () {
      expect(ResponsiveGrid.subcategoryCardExtent(1), 132);
      expect(ResponsiveGrid.subcategoryCardExtent(1.5), 152);
    });
  });
}
