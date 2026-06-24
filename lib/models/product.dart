import 'package:flutter/material.dart';

/// Product model matching the REAL Supabase `products` table schema.
///
/// Categories (ENUM): equipo_medico, ultrasonido_humano, consumible, refaccion, servicio
/// Application (ENUM): humano, ambos, general
class Product {
  final String id;
  final String sku;
  final String name;
  final String category;
  final String application;
  final String? commercialBrand;
  final String? description;
  final String? brand;
  final String? model;
  final double unitPriceMxn;
  final double? referencePriceUsd;
  final double costPriceMxn;
  final double? oldPrice;
  final String currency;
  final String unit;
  final bool isActive;
  final bool requiresSerial;
  final bool trackInventory;
  final int? leadTimeDays;
  final String? warrantyText;
  final String? shippingInfo;
  final String? availabilityStatus;
  final String? subcategory;
  final DateTime createdAt;

  // Joined data
  final String? mainImageUrl;
  final List<ProductMedia> images;
  final List<ProductSpec> specs;
  final int? currentStock;
  final int? minimumStock;
  final ActiveProductPromotion? activePromotion;

  Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    required this.application,
    this.commercialBrand,
    this.description,
    this.brand,
    this.model,
    required this.unitPriceMxn,
    this.referencePriceUsd,
    required this.costPriceMxn,
    this.oldPrice,
    required this.currency,
    required this.unit,
    required this.isActive,
    required this.requiresSerial,
    required this.trackInventory,
    this.leadTimeDays,
    this.warrantyText,
    this.shippingInfo,
    this.availabilityStatus,
    this.subcategory,
    required this.createdAt,
    this.mainImageUrl,
    this.images = const [],
    this.specs = const [],
    this.currentStock,
    this.minimumStock,
    this.activePromotion,
  });

  /// Expose stock as currentStock for backward compatibility
  int? get stock => currentStock;

  /// Getters for stock status and color according to business rules
  String get stockStatusLabel {
    final cur = currentStock ?? 0;
    if (currentStock == null || cur <= 0) {
      return 'Sin stock';
    }
    if (minimumStock != null && cur <= minimumStock!) {
      return 'Bajo stock';
    }
    return 'Disponible';
  }

  Color get stockStatusColor {
    final status = stockStatusLabel;
    if (status == 'Sin stock') {
      return const Color(0xFFEF4444); // _kRed
    } else if (status == 'Bajo stock') {
      return const Color(0xFFD97706); // Orange-800
    } else {
      return const Color(0xFF16A34A); // _kGreen
    }
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final mediaList = <ProductMedia>[];
    if (json['product_media'] != null && json['product_media'] is List) {
      for (final m in json['product_media']) {
        mediaList.add(ProductMedia.fromJson(m));
      }
    }

    final specsList = <ProductSpec>[];
    if (json['product_specs'] != null && json['product_specs'] is List) {
      for (final s in json['product_specs']) {
        specsList.add(ProductSpec.fromJson(s));
      }
    }

    String? primaryImage;
    for (final m in mediaList) {
      if (m.isPrimary) { primaryImage = m.filePath; break; }
    }
    if (primaryImage == null && mediaList.isNotEmpty) {
      primaryImage = mediaList.first.filePath;
    }

    int? currentStockVal;
    int? minimumStockVal;

    if (json['track_inventory'] == true) {
      final stockData = json['product_inventory'];
      if (stockData is List && stockData.isNotEmpty) {
        final first = stockData.first;
        if (first is Map) {
          currentStockVal = _toInt(first['current_stock']);
          minimumStockVal = _toInt(first['minimum_stock']);
        }
      } else if (stockData is Map) {
        currentStockVal = _toInt(stockData['current_stock']);
        minimumStockVal = _toInt(stockData['minimum_stock']);
      }
    }

    // Parse active promotion if present
    final promoList = json['active_product_promotions'] as List?;
    ActiveProductPromotion? activePromo;
    double calculatedUnitPrice = _toDouble(json['unit_price_mxn']);
    double? calculatedOldPrice = json['old_price'] != null ? _toDouble(json['old_price']) : null;

    if (promoList != null && promoList.isNotEmpty) {
      activePromo = ActiveProductPromotion.fromJson(promoList.first as Map<String, dynamic>);
      calculatedOldPrice = calculatedUnitPrice; // the original price becomes the old price to cross out
      
      final val = activePromo.discountValue;
      if (activePromo.discountType == 'percentage') {
        calculatedUnitPrice = calculatedUnitPrice * (1 - val / 100);
      } else if (activePromo.discountType == 'fixed_amount') {
        calculatedUnitPrice = calculatedUnitPrice - val;
      } else if (activePromo.discountType == 'promotional_price') {
        calculatedUnitPrice = val;
      }
      if (calculatedUnitPrice < 0) calculatedUnitPrice = 0.0;
    }

    return Product(
      id: json['id'] as String,
      sku: json['sku'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      application: json['application'] as String? ?? 'general',
      commercialBrand: json['commercial_brand'] as String?,
      description: json['description'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      unitPriceMxn: calculatedUnitPrice,
      referencePriceUsd: json['reference_price_usd'] != null ? _toDouble(json['reference_price_usd']) : null,
      costPriceMxn: _toDouble(json['cost_price_mxn']),
      oldPrice: calculatedOldPrice,
      currency: json['currency'] as String? ?? 'MXN',
      unit: json['unit'] as String? ?? 'pieza',
      isActive: json['is_active'] as bool? ?? true,
      requiresSerial: json['requires_serial'] as bool? ?? false,
      trackInventory: json['track_inventory'] as bool? ?? true,
      leadTimeDays: json['lead_time_days'] as int?,
      warrantyText: json['warranty_text'] as String?,
      shippingInfo: json['shipping_info'] as String?,
      availabilityStatus: json['availability_status'] as String?,
      subcategory: json['subcategory'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      mainImageUrl: primaryImage,
      images: mediaList,
      specs: specsList,
      currentStock: currentStockVal,
      minimumStock: minimumStockVal,
      activePromotion: activePromo,
    );
  }

  /// Has discount?
  bool get hasDiscount => oldPrice != null && oldPrice! > unitPriceMxn;

  /// Discount percentage
  int get discountPercent {
    if (!hasDiscount) return 0;
    return ((1 - unitPriceMxn / oldPrice!) * 100).round();
  }

  /// Human-readable category label
  String get categoryLabel {
    switch (category) {
      case 'equipo_medico': return 'Equipos Médicos';
      case 'ultrasonido_humano': return 'Ultrasonido Humano';
      case 'ultrasonido_veterinario': return 'Ultrasonido Veterinario';
      case 'consumible': return 'Consumibles';
      case 'refaccion': return 'Refacciones';
      case 'servicio': return 'Mantenimiento';
      case 'accesorio': return 'Accesorios';
      default: return category;
    }
  }

  /// Formatted price
  String get formattedPrice => '\$${_formatMoney(unitPriceMxn)}';

  /// Formatted old price
  String get formattedOldPrice => oldPrice != null ? '\$${_formatMoney(oldPrice!)}' : '';

  /// Shipping text with icon
  bool get hasFreeShipping => shippingInfo?.toLowerCase().contains('gratis') ?? false;

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null ? parsed.round() : null;
    }
    return null;
  }

  static String _formatMoney(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '$buffer.$decPart';
  }
}

class ProductMedia {
  final String id;
  final String productId;
  final String filePath;
  final String? fileName;
  final String documentType;
  final bool isPrimary;
  final int sortOrder;

  ProductMedia({
    required this.id, required this.productId, required this.filePath,
    this.fileName, required this.documentType, required this.isPrimary, required this.sortOrder,
  });

  factory ProductMedia.fromJson(Map<String, dynamic> json) => ProductMedia(
    id: json['id'] as String,
    productId: json['product_id'] as String,
    filePath: json['file_path'] as String,
    fileName: json['file_name'] as String?,
    documentType: json['document_type'] as String? ?? 'imagen',
    isPrimary: json['is_primary'] as bool? ?? false,
    sortOrder: json['sort_order'] as int? ?? 0,
  );
}

class ProductSpec {
  final String id;
  final String productId;
  final String? specGroup;
  final String specKey;
  final String specValue;
  final int sortOrder;

  ProductSpec({
    required this.id, required this.productId, this.specGroup,
    required this.specKey, required this.specValue, required this.sortOrder,
  });

  factory ProductSpec.fromJson(Map<String, dynamic> json) => ProductSpec(
    id: json['id'] as String,
    productId: json['product_id'] as String,
    specGroup: json['spec_group'] as String?,
    specKey: json['spec_key'] as String,
    specValue: json['spec_value'] as String,
    sortOrder: json['sort_order'] as int? ?? 0,
  );
}

class ActiveProductPromotion {
  final String productId;
  final String discountType; // percentage, fixed_amount, promotional_price
  final double discountValue;
  final String? campaignName;
  final DateTime? endsAt;

  ActiveProductPromotion({
    required this.productId,
    required this.discountType,
    required this.discountValue,
    this.campaignName,
    this.endsAt,
  });

  factory ActiveProductPromotion.fromJson(Map<String, dynamic> json) {
    return ActiveProductPromotion(
      productId: json['product_id'] as String,
      discountType: json['discount_type'] as String,
      discountValue: _toDouble(json['discount_value']),
      campaignName: (json['campaign_name'] ?? json['promotion_name']) as String?,
      endsAt: json['ends_at'] != null ? DateTime.parse(json['ends_at'] as String) : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
