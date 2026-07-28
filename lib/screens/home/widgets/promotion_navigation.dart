import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/catalog_category.dart';
import '../../../models/promotion_banner.dart';
import '../../../services/catalog_service.dart';
import '../../../services/promotion_banner_service.dart';
import '../../product/category_products_screen.dart';
import '../../product/product_detail_screen.dart';
import '../../product/promotion_products_screen.dart';
import '../home_screen.dart';

class PromotionNavigation {
  const PromotionNavigation._();

  static bool hasDestination(
    PromotionBanner creative, {
    bool productAvailable = true,
  }) {
    if (_notEmpty(creative.productId)) return productAvailable;
    final action = creative.ctaAction?.toLowerCase().trim();
    if (action == 'open_support') return true;
    if (action == null || action.isEmpty || action == 'none') return false;
    if (action == 'open_promotion') {
      return _notEmpty(creative.ctaTarget) ||
          _notEmpty(creative.promotionId) ||
          _notEmpty(creative.productPromotionId);
    }
    return _notEmpty(creative.ctaTarget);
  }

  static Future<void> open(
    BuildContext context,
    PromotionBanner creative,
  ) async {
    final productId = creative.productId?.trim();
    if (_notEmpty(productId)) {
      _openProduct(context, productId!);
      return;
    }

    final action = creative.ctaAction?.toLowerCase().trim() ?? 'none';
    final target = creative.ctaTarget?.trim();
    switch (action) {
      case 'open_product':
        if (_notEmpty(target)) _openProduct(context, target!);
        break;
      case 'open_category':
        if (_notEmpty(target)) await _openCategory(context, target!);
        break;
      case 'open_promotion':
        final promotionId = _firstNotEmpty([
          target,
          creative.promotionId,
          creative.productPromotionId,
        ]);
        if (promotionId != null && context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PromotionProductsScreen(
                promotionId: promotionId,
                title: creative.promotionName ?? creative.headline,
              ),
            ),
          );
        }
        break;
      case 'open_service':
        if (_notEmpty(target)) {
          _openProduct(context, target!);
        }
        break;
      case 'open_support':
        HomeScreen.showTab(3);
        break;
      case 'external_url':
        final uri = PromotionBannerService.validateExternalUrl(target);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'none':
      default:
        break;
    }
  }

  static void _openProduct(BuildContext context, String productId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: productId),
      ),
    );
  }

  static Future<void> _openCategory(
    BuildContext context,
    String categoryId,
  ) async {
    try {
      final categories = await CatalogService.getCategories();
      CatalogCategory? selected;
      for (final category in categories) {
        if (category.id == categoryId) {
          selected = category;
          break;
        }
      }
      if (selected == null || !context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CategoryProductsScreen(
            categoryId: selected!.id,
            categoryKey: selected.productCategoryKey,
            categoryLabel: selected.name,
            subcategoryLabel: selected.name,
          ),
        ),
      );
    } catch (_) {
      return;
    }
  }

  static bool _notEmpty(String? value) => value?.trim().isNotEmpty == true;

  static String? _firstNotEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (_notEmpty(value)) return value!.trim();
    }
    return null;
  }
}
