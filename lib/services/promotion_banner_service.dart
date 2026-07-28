import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/promotion_banner.dart';
import '../utils/ui_helpers.dart';

class PromotionBannerService {
  static final _db = Supabase.instance.client;
  static const _defaultBucket = 'promotion-assets';
  static const _cacheDuration = Duration(minutes: 1);
  static final Map<String, _PromotionCacheEntry> _cache = {};
  static final Stopwatch _cacheClock = Stopwatch()..start();

  static Future<List<DisplayPromotionBanner>> getActiveBanners({
    bool forceRefresh = false,
  }) {
    return _getActiveCreatives(
      'active_promotion_banners',
      forceRefresh: forceRefresh,
    );
  }

  static Future<List<DisplayPromotionBanner>> getActiveCards({
    bool forceRefresh = false,
  }) {
    return _getActiveCreatives(
      'active_promotion_cards',
      forceRefresh: forceRefresh,
    );
  }

  static Future<List<DisplayPromotionBanner>> _getActiveCreatives(
    String viewName, {
    required bool forceRefresh,
  }) async {
    final cached = _cache[viewName];
    if (!forceRefresh &&
        cached != null &&
        _cacheClock.elapsed - cached.loadedAt < _cacheDuration) {
      return cached.items;
    }

    final response = await _db.from(viewName).select('*').order('priority');

    final creatives = <DisplayPromotionBanner>[];
    for (final row in response as List) {
      final banner = PromotionBanner.fromJson(row as Map<String, dynamic>);
      final asset = banner.selectedAsset;
      final imageUrl = _resolveImageUrl(asset);
      if (asset == null || imageUrl == null) {
        debugPrint(
          '[PromotionBannerService] Creativo ${banner.creativeId} '
          'omitido porque no tiene una imagen pública utilizable.',
        );
        continue;
      }
      creatives.add(
        DisplayPromotionBanner(
          banner: banner,
          imageUrl: imageUrl,
          assetRole: asset.role,
        ),
      );
    }
    final result = List<DisplayPromotionBanner>.unmodifiable(creatives);
    _cache[viewName] = _PromotionCacheEntry(_cacheClock.elapsed, result);
    return result;
  }

  static String? _resolveImageUrl(PromotionBannerAsset? asset) {
    if (asset == null) return null;

    final publicUrl = UiHelpers.sanitizeTrustedRemoteUrl(asset.publicUrl);
    if (publicUrl != null) return publicUrl;

    final path = asset.storagePath?.trim();
    if (path == null || path.isEmpty) return null;
    final bucket = asset.storageBucket?.trim().isNotEmpty == true
        ? asset.storageBucket!.trim()
        : _defaultBucket;
    return UiHelpers.sanitizeTrustedRemoteUrl(
      _db.storage.from(bucket).getPublicUrl(path),
    );
  }

  static Uri? validateExternalUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }
}

class _PromotionCacheEntry {
  const _PromotionCacheEntry(this.loadedAt, this.items);

  final Duration loadedAt;
  final List<DisplayPromotionBanner> items;
}
