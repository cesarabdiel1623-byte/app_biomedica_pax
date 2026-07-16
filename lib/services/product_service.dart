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

  static const publicPromotionColumns = '''
    product_id,
    discount_type,
    discount_value,
    campaign_name,
    ends_at
  ''';

  /// Public product contract used by mobile screens.
  /// Inventory internals are intentionally excluded; use availability_status.
  static const publicProductSelect = '''
    $publicProductColumns,
    product_media($publicMediaColumns),
    product_specs($publicSpecColumns),
    active_product_promotions($publicPromotionColumns)
  ''';

  /// Get all active products with their images and specs
  static Future<List<Product>> getAllProducts({String? category, String? application}) async {
    var query = _client
        .from('products')
        .select(publicProductSelect)
        .eq('is_active', true);

    if (category != null && category.isNotEmpty) {
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
        .or('name.ilike.%$query%,description.ilike.%$query%,brand.ilike.%$query%,sku.ilike.%$query%,commercial_brand.ilike.%$query%')
        .order('name');
    return (response as List).map((json) => Product.fromJson(json)).toList();
  }

  /// Get products by category ENUM
  static Future<List<Product>> getProductsByCategory(String category) async {
    return getAllProducts(category: category);
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

  /// Category ENUM values with display labels and icons
  static const categoryInfo = {
    'equipo_medico': {'label': 'Equipo Médico', 'icon': 'medical_services'},
    'ultrasonido_humano': {'label': 'Ultrasonido', 'icon': 'monitor_heart'},
    'ultrasonido_veterinario': {'label': 'Ultrasonido Vet', 'icon': 'pets'},
    'consumible': {'label': 'Consumibles', 'icon': 'water_drop'},
    'refaccion': {'label': 'Refacciones', 'icon': 'build'},
    'accesorio': {'label': 'Accesorios', 'icon': 'extension'},
    'servicio': {'label': 'Servicios', 'icon': 'engineering'},
  };

  /// Application ENUM values with display labels
  static const applicationInfo = {
    'humano': {'label': 'Humano', 'icon': 'person'},
    'veterinario': {'label': 'Veterinario', 'icon': 'pets'},
    'ambos': {'label': 'Humano y Vet', 'icon': 'groups'},
    'general': {'label': 'General', 'icon': 'category'},
  };

  /// Get similar/related products (same subcategory or category as fallback, then general active)
  static Future<List<Product>> getSimilarProducts(String productId, String category, {String? subcategory}) async {
    try {
      // 1. Try matching subcategory (excluding current product)
      if (subcategory != null && subcategory.isNotEmpty) {
        final res = await _client
            .from('products')
            .select(publicProductSelect)
            .eq('is_active', true)
            .neq('id', productId)
            .eq('subcategory', subcategory)
            .limit(6);
        if (res.isNotEmpty) {
          return (res as List).map((json) => Product.fromJson(json)).toList();
        }
      }

      // 2. Fallback: same category (excluding current product)
      final resCat = await _client
          .from('products')
          .select(publicProductSelect)
          .eq('is_active', true)
          .neq('id', productId)
          .eq('category', category)
          .limit(6);
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
