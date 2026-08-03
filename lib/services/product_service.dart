import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

/// Service for querying the REAL Supabase `products` table.
/// Joins with `product_media` and `product_specs` for complete data.
class ProductService {
  static final _client = Supabase.instance.client;

  /// The select query that includes media, specs, and stock via PostgREST joins
  static const _fullSelect = '''
    *,
    product_media(*),
    product_specs(*)
  ''';

  static Future<List<Product>> _attachStock(List<Product> products) async {
    if (products.isEmpty) return products;

    try {
      final productIds = products.map((p) => p.id).toList();
      
      List<dynamic> stockResponse = [];
      
      try {
        stockResponse = await _client
            .from('product_inventory_availability')
            .select('product_id, available_stock, stock_status')
            .inFilter('product_id', productIds);
      } catch (e) {
        // Fallback or ignore if the view fails, though it shouldn't
      }

      final stockMap = <String, Map<String, dynamic>>{};
      for (final row in stockResponse) {
        final pid = row['product_id'] as String?;
        if (pid == null) continue;
        
        stockMap[pid] = {
          'available_stock': row['available_stock'],
          'stock_status': row['stock_status'],
        };
      }

      return products.map((p) {
        if (!p.trackInventory) return p;
        if (!stockMap.containsKey(p.id)) return p; // Mantiene null

        final stockData = stockMap[p.id]!;
        final availableStockStr = stockData['available_stock']?.toString() ?? '0';
        final stockVal = double.tryParse(availableStockStr)?.round() ?? 0;
        final stockStatus = stockData['stock_status'] as String?;

        return p.copyWith(stock: stockVal, stockStatus: stockStatus);
      }).toList();
    } catch (e) {
      // In case of error, just return the products safely
      return products;
    }
  }

  /// Get all active products with their images and specs
  static Future<List<Product>> getAllProducts({String? category, String? application}) async {
    var query = _client
        .from('products')
        .select(_fullSelect)
        .eq('is_active', true);

    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (application != null && application.isNotEmpty) {
      query = query.eq('application', application);
    }

    final response = await query.order('name');
    final rawProducts = (response as List).map((json) => Product.fromJson(json)).toList();
    return _attachStock(rawProducts);
  }

  /// Get a single product by ID with full details
  static Future<Product?> getProductById(String productId) async {
    final response = await _client
        .from('products')
        .select(_fullSelect)
        .eq('id', productId)
        .eq('is_active', true)
        .maybeSingle();

    if (response == null) return null;
    final product = Product.fromJson(response);
    final productsWithStock = await _attachStock([product]);
    return productsWithStock.isNotEmpty ? productsWithStock.first : product;
  }

  /// Search products by text (name, description, brand, sku)
  static Future<List<Product>> searchProducts(String query) async {
    final response = await _client
        .from('products')
        .select(_fullSelect)
        .eq('is_active', true)
        .or('name.ilike.%$query%,description.ilike.%$query%,brand.ilike.%$query%,sku.ilike.%$query%,commercial_brand.ilike.%$query%')
        .order('name');
    final rawProducts = (response as List).map((json) => Product.fromJson(json)).toList();
    return _attachStock(rawProducts);
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
}
