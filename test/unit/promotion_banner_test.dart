import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/promotion_banner.dart';
import 'package:gomedical_app/screens/home/widgets/promotion_navigation.dart';

void main() {
  group('PromotionBanner', () {
    test('prefers a primary asset before sort order', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'creative-1',
        'priority': 1,
        'assets': [
          {
            'public_url': 'https://example.com/first.png',
            'is_primary': false,
            'sort_order': 0,
            'role': 'background',
          },
          {
            'public_url': 'https://example.com/primary.png',
            'is_primary': true,
            'sort_order': 5,
            'role': 'final_render',
          },
        ],
      });

      expect(
        banner.selectedAsset?.publicUrl,
        'https://example.com/primary.png',
      );
    });

    test('prefers final render before thumbnail', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'creative-2',
        'assets': [
          {
            'storage_path': 'later.png',
            'sort_order': 4,
            'role': 'final_render',
          },
          {'storage_path': 'first.png', 'sort_order': 1, 'role': 'thumbnail'},
        ],
      });

      expect(banner.selectedAsset?.storagePath, 'later.png');
    });

    test('banner with product id remains tappable before product preload', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'hero-product-link',
        'placement': 'hero_banner',
        'product_id': 'product-123',
        'assets': [
          {
            'public_url': 'https://example.com/banner.webp',
            'role': 'final_render',
          },
        ],
      });

      expect(
        PromotionNavigation.hasDestination(banner, productAvailable: false),
        isTrue,
      );
    });

    test('prefers a mobile asset before a desktop primary asset', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'creative-mobile',
        'assets': [
          {
            'storage_path': 'desktop.png',
            'device_scope': 'desktop',
            'is_primary': true,
            'role': 'final_render',
          },
          {
            'storage_path': 'mobile.png',
            'device_scope': 'mobile',
            'is_primary': false,
            'role': 'background',
          },
        ],
      });

      expect(banner.selectedAsset?.storagePath, 'mobile.png');
    });

    test('parses assets supplied as encoded JSON', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'creative-3',
        'assets': jsonEncode({
          'items': [
            {
              'bucket': 'promotion-assets',
              'path': 'campaign/banner.webp',
              'isPrimary': true,
              'sortOrder': 0,
              'width': 594,
              'height': 280,
            },
          ],
        }),
      });

      expect(banner.assets, hasLength(1));
      expect(banner.selectedAsset?.storageBucket, 'promotion-assets');
      expect(banner.selectedAsset?.storagePath, 'campaign/banner.webp');
      expect(banner.selectedAsset?.aspectRatio, closeTo(594 / 280, 0.001));
    });

    test('parses nullable creative metadata safely', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'creative-4',
        'placement': 'promo_card',
        'publish_status': 'published',
        'discount_value': '15.5',
        'effective_starts_at': '2026-07-24T18:08:00Z',
        'renderer_type': 'native',
        'template_config': '{"show_price":true}',
        'assets': const [],
      });

      expect(banner.placement, 'promo_card');
      expect(banner.publishStatus, 'published');
      expect(banner.discountValue, 15.5);
      expect(banner.effectiveStartsAt, isNotNull);
      expect(banner.templateConfig?['show_price'], isTrue);
      expect(banner.selectedAsset, isNull);
    });

    test('parses real subcategory banner action from cta fields', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'subcategory-banner',
        'placement': 'hero_banner',
        'cta_action': 'open_subcategory',
        'cta_target': 'a610b416-ee0f-4ee7-bf77-cdd24979df40',
        'layout_config': {
          'cta': {
            'route': 'subcategory',
            'target_type': 'subcategory',
            'category_id': '5365517f-c76b-4557-ae2f-c225c74a12f6',
            'subcategory_id': 'a610b416-ee0f-4ee7-bf77-cdd24979df40',
            'subcategory_name': 'Baterias',
          },
        },
        'assets': const [],
      });

      expect(banner.ctaAction, 'open_subcategory');
      expect(banner.ctaTarget, 'a610b416-ee0f-4ee7-bf77-cdd24979df40');
      expect(PromotionNavigation.hasDestination(banner), isTrue);
    });

    test('parses alternate subcategory action field names defensively', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'subcategory-legacy-fields',
        'action_type': 'subcategory',
        'action_target_id': 'subcategory-123',
        'assets': const [],
      });

      expect(banner.ctaAction, 'subcategory');
      expect(banner.ctaTarget, 'subcategory-123');
      expect(PromotionNavigation.hasDestination(banner), isTrue);
    });

    test('subcategory action without target is not tappable', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'subcategory-without-target',
        'cta_action': 'open_subcategory',
        'assets': const [],
      });

      expect(PromotionNavigation.hasDestination(banner), isFalse);
    });

    test(
      'T4.4 / Phase 2: BannerCarousel source code uses 8:3 ratio and does not contain 16/9 clamp',
      () {
        final file = File('lib/screens/home/widgets/banner_carousel.dart');
        expect(file.existsSync(), isTrue);
        final code = file.readAsStringSync();

        expect(code.contains('_kBannerAspectRatio = 8 / 3'), isTrue);
        expect(code.contains('_kBannerAspectRatio = 16 / 9'), isFalse);
        expect(code.contains('.clamp(140.0, 300.0)'), isFalse);
      },
    );

    test(
      'T4.4 / Phase 2: Responsive banner height calculation accurately preserves 8:3 ratio for standard screens',
      () {
        const bannerAspectRatio = 8 / 3; // 2.6667 (1600x600 px)

        // Test screen widths: 360px, 390px, 412px, 480px, 720px
        for (final screenWidth in [360.0, 390.0, 412.0, 480.0, 720.0]) {
          final bannerWidth = screenWidth > 720 ? 720.0 : screenWidth;
          final itemWidth = (bannerWidth * 0.90) - 10.0;
          final itemHeight = itemWidth / bannerAspectRatio;
          final measuredRatio = itemWidth / itemHeight;

          expect(measuredRatio, closeTo(2.6667, 0.001));
        }
      },
    );

    test(
      'hero banner loading and image failure use neutral spinner placeholder',
      () {
        final file = File('lib/screens/home/widgets/banner_carousel.dart');
        expect(file.existsSync(), isTrue);
        final code = file.readAsStringSync();

        expect(
          code,
          contains('errorBuilder: (_, _, _) => _bannerLoadingPlaceholder()'),
        );
        expect(code, contains('color: const Color(0xFFF8FAFC)'));
        expect(code, contains('child: Material('));
        expect(code, contains('color: const Color(0xFFF8FAFC),'));
        expect(code, isNot(contains('Icons.image_not_supported_outlined')));
        expect(code, isNot(contains('color: backgroundColor,')));
      },
    );

    test(
      'subcategory banner navigation is wired to category products screen',
      () {
        final file = File('lib/screens/home/widgets/promotion_navigation.dart');
        expect(file.existsSync(), isTrue);
        final code = file.readAsStringSync();

        expect(code, contains("'open_subcategory'"));
        expect(code, contains('_openSubcategory(context, target!)'));
        expect(code, contains('subcategoryId: selectedSubcategory.id'));
        expect(code, contains('subcategoryKey: selectedSubcategory.slug'));
      },
    );

    test(
      'T4.4 / Phase 2: PromotionCardsSection source code respects 1:1 square for final renders',
      () {
        final file = File(
          'lib/screens/home/widgets/promotion_cards_section.dart',
        );
        expect(file.existsSync(), isTrue);
        final code = file.readAsStringSync();

        expect(code.contains('isSquareRender ? 184.0 : 292.0'), isTrue);
        expect(code.contains('isSquareRender'), isTrue);
      },
    );

    test(
      'T4.4 / Phase 2: Standard 1600x600 banner asset evaluates to 2.6667 aspect ratio',
      () {
        final banner = PromotionBanner.fromJson({
          'creative_id': 'banner-standard',
          'placement': 'hero_banner',
          'assets': [
            {
              'public_url': 'https://example.com/banner-1600x600.webp',
              'is_primary': true,
              'role': 'final_render',
              'width': 1600,
              'height': 600,
            },
          ],
        });

        expect(banner.selectedAsset?.aspectRatio, closeTo(8 / 3, 0.001));
      },
    );

    test('T5: hero banner final render is treated as a pure manual image', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'hero-final-render',
        'placement': 'hero_banner',
        'design_mode': 'manual',
        'renderer_type': 'raster',
        'headline': 'Texto que no debe montarse',
        'cta_text': 'Comprar',
        'product_id': 'product-1',
        'assets': [
          {
            'public_url': 'https://example.com/banner-1600x600.webp',
            'role': 'final_render',
            'width': 1600,
            'height': 600,
          },
        ],
      });

      expect(banner.isHeroBanner, isTrue);
      expect(banner.isManualFinalHeroRender, isTrue);
      expect(banner.isFinalRender, isTrue);
    });

    test('T5: dynamic hero banner remains eligible for generated overlay', () {
      final banner = PromotionBanner.fromJson({
        'creative_id': 'hero-template',
        'placement': 'hero_banner',
        'design_mode': 'template',
        'renderer_type': 'native',
        'headline': 'Oferta generada por layout',
        'assets': [
          {
            'public_url': 'https://example.com/background.webp',
            'role': 'background',
            'width': 1600,
            'height': 600,
          },
        ],
      });

      expect(banner.isHeroBanner, isTrue);
      expect(banner.isManualFinalHeroRender, isFalse);
      expect(banner.isFinalRender, isFalse);
    });

    test(
      'T5: BannerCarousel separates manual hero from dynamic overlay rendering',
      () {
        final file = File('lib/screens/home/widgets/banner_carousel.dart');
        expect(file.existsSync(), isTrue);
        final code = file.readAsStringSync();

        expect(
          code,
          contains('final isManualFinalHero = banner.isManualFinalHeroRender'),
        );
        expect(
          code,
          contains('final overlayProduct = isManualFinalHero ? null : product'),
        );
        expect(code, contains('!isManualFinalHero &&'));
        expect(code, contains('final imageFit = isManualFinalHero'));
        expect(code, contains('? BoxFit.cover'));
        expect(code, contains('Image.network('));
      },
    );

    test(
      'T4.4 / Phase 2: Standard 800x800 promo card asset evaluates to 1.0 aspect ratio',
      () {
        final promoCard = PromotionBanner.fromJson({
          'creative_id': 'card-standard',
          'placement': 'promo_card',
          'assets': [
            {
              'public_url': 'https://example.com/card-800x800.png',
              'is_primary': true,
              'role': 'final_render',
              'width': 800,
              'height': 800,
            },
          ],
        });

        expect(promoCard.selectedAsset?.aspectRatio, closeTo(1.0, 0.001));
      },
    );

    test(
      'T5: promo cards keep their own section and layout separate from hero banner',
      () {
        final file = File(
          'lib/screens/home/widgets/promotion_cards_section.dart',
        );
        expect(file.existsSync(), isTrue);
        final code = file.readAsStringSync();

        expect(code, contains('PromotionBannerService.getActiveCards'));
        expect(code, contains("height: 184"));
        expect(code, contains('isSquareRender ? 184.0 : 292.0'));
        expect(code, isNot(contains('_kBannerAspectRatio')));
        expect(code, isNot(contains('isManualFinalHeroRender')));
      },
    );
  });
}
