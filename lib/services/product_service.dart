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
      final stockResponse = await _client
          .from('inventory_stock')
          .select('product_id, quantity, current_stock, stock')
          .inFilter('product_id', productIds);

      final stockMap = <String, double>{};
      for (final row in stockResponse as List) {
        final pid = row['product_id'] as String?;
        if (pid == null) continue;
        
        final quantityStr = row['quantity']?.toString() ?? row['current_stock']?.toString() ?? row['stock']?.toString() ?? '0';
        final quantity = double.tryParse(quantityStr) ?? 0.0;
        
        stockMap[pid] = (stockMap[pid] ?? 0.0) + quantity;
      }

      return products.map((p) {
        if (!p.trackInventory) return p;
        final stockVal = stockMap[p.id]?.round() ?? 0;
        return p.copyWith(stock: stockVal);
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
