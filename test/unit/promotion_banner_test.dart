import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/promotion_banner.dart';

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
  });
}
