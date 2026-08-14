import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

/// Service for querying the REAL Supabase `products` table.
/// Joins with `product_media` and `product_specs` for complete data.
class ProductService {
  static final _client = Supabase.instance.client;

  /// Public product columns consumed by the mobile app.
  /// Intentionally excludes internal pricing fields such as cost_price_mxn.
  static const publicProductColumns = '''
    id,
    sku,
    name,
    category_id,
    category,
    application,
    commercial_brand,
    description,
    brand,
    model,
    unit_price_mxn,
    reference_price_usd,
    old_price,
    currency,
    unit,
    is_active,
    requires_serial,
    track_inventory,
    lead_time_days,
    warranty_text,
    shipping_info,
    availability_status,
    subcategory_id,
    subcategory,
    product_condition,
    created_at,
    sales_count
  ''';

  static const publicMediaColumns = '''
    id,
    product_id,
    file_path,
    file_name,
    document_type,
    is_primary,
    sort_order
  ''';

  static const publicSpecColumns = '''
    id,
    product_id,
    spec_group,
    spec_key,
    spec_value,
    sort_order
  ''';

  static const publicInventoryColumns = '''
    current_stock,
    minimum_stock
  ''';

  static const publicPromotionColumns = '''
    product_id,
    original_price_mxn,
    promotional_price_mxn,
    discount_type,
    discount_value,
    computed_status,
    campaign_name,
    ends_at
  ''';

  /// Public product contract used by mobile screens.
  /// Reads only stock counters needed by the app; Supabase remains authoritative.
  static const publicProductSelect =
      '''
    $publicProductColumns,
    product_media($publicMediaColumns),
    product_specs($publicSpecColumns),
    product_inventory($publicInventoryColumns),
    active_product_promotions($publicPromotionColumns)
  ''';

  /// Get all active products with their images and specs
  static Future<List<Product>> getAllProducts({
    String? categoryId,
    String? category,
    String? application,
  }) async {
    var query = _client
        .from('products')
        .select(publicProductSelect)
        .eq('is_active', true);

    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.eq('category_id', categoryId);
    } else if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (application != null && application.isNotEmpty) {
      query = query.eq('application', application);
    }

    final response = await query.order('name');
    return (response as List).map((json) => Product.fromJson(json)).toList();
  }

  /// Get a single product by ID with full details
  static Future<Product?> getProductById(String productId) async {
    final response = await _client
        .from('products')
        .select(publicProductSelect)
        .eq('id', productId)
        .eq('is_active', true)
        .maybeSingle();

    if (response == null) return null;
    return Product.fromJson(response);
  }

  /// Search products by text (name, description, brand, sku)
  static Future<List<Product>> searchProducts(String query) async {
    final response = await _client
        .from('products')
        .select(publicProductSelect)
        .eq('is_active', true)
        .or(
          'name.ilike.%$query%,description.ilike.%$query%,brand.ilike.%$query%,sku.ilike.%$query%,commercial_brand.ilike.%$query%',
        )
        .order('name');
    return (response as List).map((json) => Product.fromJson(json)).toList();
  }

  /// Get products by category ENUM
  static Future<List<Product>> getProductsByCategory(String category) async {
    return getAllProducts(category: category);
  }

  static Future<List<Product>> getProductsByCatalogCategory({
    required String categoryId,
    String? legacyCategory,
  }) async {
    final officialProducts = await getAllProducts(categoryId: categoryId);
    if (legacyCategory == null || legacyCategory.isEmpty) {
      return officialProducts;
    }

    final legacyResponse = await _client
        .from('products')
        .select(publicProductSelect)
        .eq('is_active', true)
        .isFilter('category_id', null)
        .eq('category', legacyCategory)
        .order('name');
    final legacyProducts = (legacyResponse as List)
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
    return _mergeProducts(officialProducts, legacyProducts);
  }

  static Future<List<Product>> getProductsByCatalogSubcategory({
    required String categoryId,
    required String subcategoryId,
    String? legacyCategory,
    String? legacySubcategory,
  }) async {
    final response = await _client
        .from('products')
        .select(publicProductSelect)
        .eq('is_active', true)
        .eq('category_id', categoryId)
        .eq('subcategory_id', subcategoryId)
        .order('name');

    final officialProducts = (response as List)
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
    if (legacyCategory == null ||
        legacyCategory.isEmpty ||
        legacySubcategory == null ||
        legacySubcategory.isEmpty) {
      return officialProducts;
    }

    final fallback = await _client
        .from('products')
        .select(publicProductSelect)
        .eq('is_active', true)
        .eq('category', legacyCategory)
        .eq('subcategory', legacySubcategory)
        .isFilter('subcategory_id', null)
        .order('name');
    final legacyProducts = (fallback as List)
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
    return _mergeProducts(officialProducts, legacyProducts);
  }

  static Future<List<Product>> getProductsByPromotion(
    String promotionId,
  ) async {
    final response = await _client
        .from('products')
        .select('''$publicProductColumns,
          product_media($publicMediaColumns),
          product_specs($publicSpecColumns),
          product_inventory($publicInventoryColumns),
          active_product_promotions!inner($publicPromotionColumns)''')
        .eq('is_active', true)
        .eq('active_product_promotions.id', promotionId)
        .order('name');
    return (response as List)
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  static List<Product> _mergeProducts(
    List<Product> officialProducts,
    List<Product> legacyProducts,
  ) {
    final productsById = <String, Product>{
      for (final product in officialProducts) product.id: product,
      for (final product in legacyProducts) product.id: product,
    };
    final products = productsById.values.toList();
    products.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return products;
  }

  /// Get all unique categories that have active products
  static Future<List<String>> getActiveCategories() async {
    final response = await _client
        .from('products')
        .select('category')
        .eq('is_active', true);

    final categories = <String>{};
    for (final row in response as List) {
      categories.add(row['category'] as String);
    }
    return categories.toList()..sort();
  }

  /// Application ENUM values with display labels
  static const applicationInfo = {
    'humano': {'label': 'Humano', 'icon': 'person'},
    'veterinario': {'label': 'Veterinario', 'icon': 'pets'},
    'ambos': {'label': 'Humano y Vet', 'icon': 'groups'},
    'general': {'label': 'General', 'icon': 'category'},
  };

  /// Get similar/related products (same subcategory or category as fallback, then general active)
  static Future<List<Product>> getSimilarProducts(
    String productId,
    String category, {
    String? categoryId,
    String? subcategory,
    String? subcategoryId,
  }) async {
    try {
      // 1. Try matching subcategory (excluding current product)
      if ((subcategoryId != null && subcategoryId.isNotEmpty) ||
          (subcategory != null && subcategory.isNotEmpty)) {
        var query = _client
            .from('products')
            .select(publicProductSelect)
            .eq('is_active', true)
            .neq('id', productId);
        query = subcategoryId != null && subcategoryId.isNotEmpty
            ? query.eq('subcategory_id', subcategoryId)
            : query.eq('subcategory', subcategory!);
        final res = await query.limit(6);
        if (res.isNotEmpty) {
          return (res as List).map((json) => Product.fromJson(json)).toList();
        }
      }

      // 2. Fallback: same category (excluding current product)
      var categoryQuery = _client
          .from('products')
          .select(publicProductSelect)
          .eq('is_active', true)
          .neq('id', productId);
      categoryQuery = categoryId != null && categoryId.isNotEmpty
          ? categoryQuery.eq('category_id', categoryId)
          : categoryQuery.eq('category', category);
      final resCat = await categoryQuery.limit(6);
      if (resCat.isNotEmpty) {
        return (resCat as List).map((json) => Product.fromJson(json)).toList();
      }

      // 3. Ultimate Fallback: any active products (excluding current product)
      final resAny = await _client
          .from('products')
          .select(publicProductSelect)
          .eq('is_active', true)
          .neq('id', productId)
          .limit(6);
      return (resAny as List).map((json) => Product.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }
}
