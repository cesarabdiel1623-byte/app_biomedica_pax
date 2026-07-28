import 'dart:convert';

class PromotionBannerAsset {
  const PromotionBannerAsset({
    required this.isPrimary,
    required this.sortOrder,
    this.id,
    this.publicUrl,
    this.storagePath,
    this.storageBucket,
    this.role,
    this.altText,
    this.width,
    this.height,
    this.deviceScope,
  });

  final String? id;
  final String? publicUrl;
  final String? storagePath;
  final String? storageBucket;
  final String? role;
  final String? altText;
  final int? width;
  final int? height;
  final String? deviceScope;
  final bool isPrimary;
  final int sortOrder;

  bool get hasLocation =>
      (publicUrl?.trim().isNotEmpty ?? false) ||
      (storagePath?.trim().isNotEmpty ?? false);

  factory PromotionBannerAsset.fromJson(Map<String, dynamic> json) {
    return PromotionBannerAsset(
      id: json['id']?.toString(),
      publicUrl:
          (json['public_url'] ?? json['url'] ?? json['asset_url']) as String?,
      storagePath:
          (json['storage_path'] ?? json['file_path'] ?? json['path'])
              as String?,
      storageBucket: (json['storage_bucket'] ?? json['bucket']) as String?,
      role: (json['role'] ?? json['asset_role']) as String?,
      altText: (json['alt_text'] ?? json['altText']) as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      deviceScope: (json['device_scope'] ?? json['deviceScope']) as String?,
      isPrimary: (json['is_primary'] ?? json['isPrimary']) as bool? ?? false,
      sortOrder:
          ((json['sort_order'] ?? json['sortOrder']) as num?)?.toInt() ?? 0,
    );
  }

  double? get aspectRatio {
    if (width == null || height == null || height == 0) return null;
    return width! / height!;
  }
}

class PromotionBanner {
  const PromotionBanner({
    required this.creativeId,
    required this.priority,
    required this.assets,
    this.productPromotionId,
    this.campaignKey,
    this.placement,
    this.designMode,
    this.publishStatus,
    this.headline,
    this.subheadline,
    this.badgeText,
    this.ctaText,
    this.ctaAction,
    this.ctaTarget,
    this.productId,
    this.promotionId,
    this.promotionName,
    this.promotionDescription,
    this.discountType,
    this.discountValue,
    this.currency,
    this.effectiveStartsAt,
    this.effectiveEndsAt,
    this.templateId,
    this.templateKey,
    this.templateName,
    this.rendererType,
    this.templateConfig,
    this.primaryColor,
    this.secondaryColor,
    this.textColor,
    this.accentColor,
    this.layoutConfig,
  });

  final String creativeId;
  final String? productPromotionId;
  final String? campaignKey;
  final String? placement;
  final String? designMode;
  final String? publishStatus;
  final String? headline;
  final String? subheadline;
  final String? badgeText;
  final String? ctaText;
  final String? ctaAction;
  final String? ctaTarget;
  final int priority;
  final String? productId;
  final String? promotionId;
  final String? promotionName;
  final String? promotionDescription;
  final String? discountType;
  final double? discountValue;
  final String? currency;
  final DateTime? effectiveStartsAt;
  final DateTime? effectiveEndsAt;
  final String? templateId;
  final String? templateKey;
  final String? templateName;
  final String? rendererType;
  final Map<String, dynamic>? templateConfig;
  final String? primaryColor;
  final String? secondaryColor;
  final String? textColor;
  final String? accentColor;
  final Map<String, dynamic>? layoutConfig;
  final List<PromotionBannerAsset> assets;

  factory PromotionBanner.fromJson(Map<String, dynamic> json) {
    return PromotionBanner(
      creativeId: (json['creative_id'] ?? json['id'] ?? '').toString(),
      productPromotionId: json['product_promotion_id'] as String?,
      campaignKey: json['campaign_key'] as String?,
      placement: json['placement'] as String?,
      designMode: json['design_mode'] as String?,
      publishStatus: json['publish_status'] as String?,
      headline: json['headline'] as String?,
      subheadline: json['subheadline'] as String?,
      badgeText: json['badge_text'] as String?,
      ctaText: json['cta_text'] as String?,
      ctaAction: json['cta_action'] as String?,
      ctaTarget: json['cta_target']?.toString(),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      productId: json['product_id'] as String?,
      promotionId: json['promotion_id'] as String?,
      promotionName: json['promotion_name'] as String?,
      promotionDescription: json['promotion_description'] as String?,
      discountType: json['discount_type'] as String?,
      discountValue: _asDouble(json['discount_value']),
      currency: json['currency'] as String?,
      effectiveStartsAt: _asDateTime(json['effective_starts_at']),
      effectiveEndsAt: _asDateTime(json['effective_ends_at']),
      templateId: json['template_id'] as String?,
      templateKey: json['template_key'] as String?,
      templateName: json['template_name'] as String?,
      rendererType: json['renderer_type'] as String?,
      templateConfig: _asMap(json['template_config']),
      primaryColor: json['primary_color'] as String?,
      secondaryColor: json['secondary_color'] as String?,
      textColor: json['text_color'] as String?,
      accentColor: json['accent_color'] as String?,
      layoutConfig: _asMap(json['layout_config']),
      assets: _parseAssets(json['assets']),
    );
  }

  PromotionBannerAsset? get selectedAsset {
    final usable = assets.where((asset) => asset.hasLocation).toList();
    if (usable.isEmpty) return null;

    usable.sort((a, b) {
      final deviceComparison = _deviceRank(
        a.deviceScope,
      ).compareTo(_deviceRank(b.deviceScope));
      if (deviceComparison != 0) return deviceComparison;
      if (a.isPrimary != b.isPrimary) {
        return a.isPrimary ? -1 : 1;
      }
      final roleComparison = _roleRank(a.role).compareTo(_roleRank(b.role));
      if (roleComparison != 0) return roleComparison;
      final orderComparison = a.sortOrder.compareTo(b.sortOrder);
      if (orderComparison != 0) return orderComparison;
      return 0;
    });
    return usable.first;
  }

  bool get isFinalRender {
    final role = selectedAsset?.role?.toLowerCase();
    return role == 'final_render' ||
        rendererType?.toLowerCase() == 'raster' ||
        rendererType?.toLowerCase() == 'final_render';
  }

  static int _deviceRank(String? scope) {
    switch (scope?.toLowerCase()) {
      case 'mobile':
        return 0;
      case 'all':
      case 'universal':
      case null:
        return 1;
      default:
        return 2;
    }
  }

  static int _roleRank(String? role) {
    switch (role?.toLowerCase()) {
      case 'final_render':
        return 0;
      case 'background':
        return 1;
      case 'thumbnail':
        return 2;
      default:
        return 3;
    }
  }

  static List<PromotionBannerAsset> _parseAssets(dynamic rawAssets) {
    dynamic value = rawAssets;
    if (value is String && value.trim().isNotEmpty) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      for (final key in const ['assets', 'items', 'data']) {
        if (map[key] is List) {
          value = map[key];
          break;
        }
      }
      if (value is Map) value = [value];
    }

    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (asset) =>
              PromotionBannerAsset.fromJson(Map<String, dynamic>.from(asset)),
        )
        .toList();
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class DisplayPromotionBanner {
  const DisplayPromotionBanner({
    required this.banner,
    required this.imageUrl,
    required this.assetRole,
  });

  final PromotionBanner banner;
  final String imageUrl;
  final String? assetRole;
}
