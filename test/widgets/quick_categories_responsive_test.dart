import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/catalog_category.dart';

Widget _buildCategoryItem({
  required CatalogCategory category,
  required bool active,
  required VoidCallback onTap,
}) {
  const color = Color(0xFF9CA3AF);
  final label = category.name;

  IconData categoryIcon(String value) {
    final key = value.toLowerCase();
    if (key.contains('ultrason') || key.contains('monitor')) {
      return Icons.monitor_heart_outlined;
    }
    if (key.contains('consum')) return Icons.water_drop_outlined;
    if (key.contains('refacc')) return Icons.build_outlined;
    if (key.contains('accesor')) return Icons.extension_outlined;
    if (key.contains('servic')) return Icons.settings_suggest_outlined;
    if (key.contains('equipo') || key.contains('medic')) {
      return Icons.medical_services_outlined;
    }
    return Icons.category_outlined;
  }

  return Padding(
    padding: const EdgeInsets.only(right: 6),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 86,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: active ? 60 : 56,
              height: active ? 60 : 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: active ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color.withValues(alpha: active ? 0.38 : 0.22),
                ),
              ),
              child: Icon(categoryIcon(category.slug), color: color, size: 30),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF374151),
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: active ? 28 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: active ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildQuickCategoriesBar(
  List<CatalogCategory> categories, {
  String? activeSlug,
}) {
  return Container(
    height: 118,
    color: Colors.white,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: categories.length,
      itemBuilder: (_, index) {
        final category = categories[index];
        final active = category.slug == activeSlug;
        return _buildCategoryItem(
          category: category,
          active: active,
          onTap: () {},
        );
      },
    ),
  );
}

void main() {
  group('Quick Categories Responsive & Overflow Tests', () {
    final sampleCategories = [
      const CatalogCategory(
        id: 'cat-1',
        name: 'Equipo médico',
        slug: 'equipo-medico',
        showBeforeSlider: true,
        showAfterSlider: false,
        sortOrder: 1,
        subcategories: [],
      ),
      const CatalogCategory(
        id: 'cat-2',
        name: 'Refacciones',
        slug: 'refacciones',
        showBeforeSlider: true,
        showAfterSlider: false,
        sortOrder: 2,
        subcategories: [],
      ),
      const CatalogCategory(
        id: 'cat-3',
        name: 'Accesorios',
        slug: 'accesorios',
        showBeforeSlider: true,
        showAfterSlider: false,
        sortOrder: 3,
        subcategories: [],
      ),
      const CatalogCategory(
        id: 'cat-4',
        name: 'Consumibles biomédicos',
        slug: 'consumibles',
        showBeforeSlider: true,
        showAfterSlider: false,
        sortOrder: 4,
        subcategories: [],
      ),
    ];

    testWidgets(
      'Renders without any RenderFlex overflow on standard screen (390x844)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: _buildQuickCategoriesBar(sampleCategories)),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Equipo médico'), findsOneWidget);
        expect(find.text('Refacciones'), findsOneWidget);
        expect(find.text('Accesorios'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Renders without any RenderFlex overflow on narrow screen (320x640)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: _buildQuickCategoriesBar(sampleCategories)),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Equipo médico'), findsOneWidget);
        expect(find.text('Refacciones'), findsOneWidget);
        expect(find.text('Accesorios'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Renders without any RenderFlex overflow with active category item',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: _buildQuickCategoriesBar(
                  sampleCategories,
                  activeSlug: 'equipo-medico',
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Equipo médico'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Renders without any RenderFlex overflow under enlarged system text scaling (1.3x)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: Center(child: _buildQuickCategoriesBar(sampleCategories)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Equipo médico'), findsOneWidget);
        expect(find.text('Refacciones'), findsOneWidget);
        expect(find.text('Accesorios'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Renders without any RenderFlex overflow under high accessibility text scaling (1.5x)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: Center(child: _buildQuickCategoriesBar(sampleCategories)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Equipo médico'), findsOneWidget);
        expect(find.text('Refacciones'), findsOneWidget);
        expect(find.text('Accesorios'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
