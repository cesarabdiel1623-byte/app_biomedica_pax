import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

/// Service to handle persistence of search history and recently viewed products.
class SearchService {
  static const String _keyHistory = 'search_history';
  static const String _keyRecentlyViewed = 'recently_viewed_products';

  // --- SEARCH HISTORY ---

  /// Retrieves search history queries, sorted from most to least recent.
  static Future<List<String>> getSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_keyHistory) ?? [];
    } catch (e) {
      print('Error getting search history: $e');
      return [];
    }
  }

  /// Saves a search query to the history list, moving it to the top if duplicate.
  static Future<void> saveSearchQuery(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_keyHistory) ?? [];

      // Remove duplicate if it exists to place it at the top
      history.remove(cleanQuery);
      history.insert(0, cleanQuery);

      // Limit to 10 elements
      if (history.length > 10) {
        history.removeRange(10, history.length);
      }

      await prefs.setStringList(_keyHistory, history);
    } catch (e) {
      print('Error saving search query: $e');
    }
  }

  /// Removes a query from the search history.
  static Future<void> removeSearchQuery(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_keyHistory) ?? [];
      history.remove(query);
      await prefs.setStringList(_keyHistory, history);
    } catch (e) {
      print('Error removing search query: $e');
    }
  }

  // --- RECENTLY VIEWED PRODUCTS ---

  /// Retrieves the list of recently viewed products from SharedPreferences.
  static Future<List<Product>> getRecentlyViewed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyRecentlyViewed) ?? [];
      final products = <Product>[];

      for (final item in list) {
        try {
          final Map<String, dynamic> json = jsonDecode(item);
          products.add(
            Product(
              id: json['id'] as String? ?? '',
              sku: (json['id'] as String? ?? '00000000')
                  .substring(0, 8)
                  .toUpperCase(),
              name: json['name'] as String? ?? '',
              category: json['category'] as String? ?? '',
              application: 'general',
              brand: json['brand'] as String?,
              commercialBrand: json['brand'] as String?,
              model: json['model'] as String?,
              unitPriceMxn: (json['unitPriceMxn'] as num? ?? 0.0).toDouble(),
              costPriceMxn:
                  (json['unitPriceMxn'] as num? ?? 0.0).toDouble() * 0.7,
              oldPrice: json['oldPrice'] != null
                  ? (json['oldPrice'] as num).toDouble()
                  : null,
              currency: 'MXN',
              unit: 'pieza',
              isActive: true,
              requiresSerial: false,
              trackInventory: true,
              currentStock: json['stock'] as int?,
              mainImageUrl: json['mainImageUrl'] as String?,
              shippingInfo: json['shippingInfo'] as String? ?? 'Envío nacional',
              availabilityStatus: json['availabilityStatus'] as String?,
              subcategory: json['subcategory'] as String?,
              createdAt: DateTime.now(),
            ),
          );
        } catch (e) {
          print('Error deserializing recently viewed item: $e');
        }
      }
      return products;
    } catch (e) {
      print('Error loading recently viewed: $e');
      return [];
    }
  }

  /// Adds a product summary to recently viewed list, moving it to the top if duplicate.
  static Future<void> addToRecentlyViewed(Product product) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('history_enabled') ?? true;
      if (!enabled) return;

      final list = prefs.getStringList(_keyRecentlyViewed) ?? [];

      final itemMap = {
        'id': product.id,
        'name': product.name,
        'brand': product.brand,
        'category': product.category,
        'subcategory': product.subcategory,
        'model': product.model,
        'unitPriceMxn': product.unitPriceMxn,
        'oldPrice': product.oldPrice,
        'mainImageUrl': product.mainImageUrl,
        'stock': product.stock,
        'availabilityStatus': product.availabilityStatus,
        'shippingInfo': product.shippingInfo,
      };

      final serialized = jsonEncode(itemMap);

      // Remove duplicate if same ID already exists
      list.removeWhere((item) {
        try {
          final decoded = jsonDecode(item);
          return decoded['id'] == product.id;
        } catch (_) {
          return false;
        }
      });

      list.insert(0, serialized);

      // Limit to 10 elements
      if (list.length > 10) {
        list.removeRange(10, list.length);
      }

      await prefs.setStringList(_keyRecentlyViewed, list);
    } catch (e) {
      print('Error saving recently viewed item: $e');
    }
  }

  /// Removes a product from the recently viewed list.
  static Future<void> removeFromRecentlyViewed(String productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyRecentlyViewed) ?? [];
      list.removeWhere((item) {
        try {
          final decoded = jsonDecode(item);
          return decoded['id'] == productId;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_keyRecentlyViewed, list);
    } catch (e) {
      print('Error removing recently viewed item: $e');
    }
  }
}
