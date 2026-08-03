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
  final int? stock;
  final String? stockStatus;

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
    this.stock,
    this.stockStatus,
  });
  Product copyWith({
    int? stock,
    String? stockStatus,
  }) {
    return Product(
      id: this.id,
      sku: this.sku,
      name: this.name,
      category: this.category,
      application: this.application,
      commercialBrand: this.commercialBrand,
      description: this.description,
      brand: this.brand,
      model: this.model,
      unitPriceMxn: this.unitPriceMxn,
      referencePriceUsd: this.referencePriceUsd,
      costPriceMxn: this.costPriceMxn,
      oldPrice: this.oldPrice,
      currency: this.currency,
      unit: this.unit,
      isActive: this.isActive,
      requiresSerial: this.requiresSerial,
      trackInventory: this.trackInventory,
      leadTimeDays: this.leadTimeDays,
      warrantyText: this.warrantyText,
      shippingInfo: this.shippingInfo,
      availabilityStatus: this.availabilityStatus,
      subcategory: this.subcategory,
      createdAt: this.createdAt,
      mainImageUrl: this.mainImageUrl,
      images: this.images,
      specs: this.specs,
      stock: stock ?? this.stock,
      stockStatus: stockStatus ?? this.stockStatus,
    );
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

    int? stockVal;
    if (json['track_inventory'] == true) {
      final stockList = json['inventory_stock'] as List?;
      if (stockList != null) {
        double sum = 0.0;
        for (final s in stockList) {
          sum += _toDouble(s['quantity']);
        }
        stockVal = sum.round();
      }
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
      unitPriceMxn: _toDouble(json['unit_price_mxn']),
      referencePriceUsd: json['reference_price_usd'] != null ? _toDouble(json['reference_price_usd']) : null,
      costPriceMxn: _toDouble(json['cost_price_mxn']),
      oldPrice: json['old_price'] != null ? _toDouble(json['old_price']) : null,
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
      stock: stockVal,
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
