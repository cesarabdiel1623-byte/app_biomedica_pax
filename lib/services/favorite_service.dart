import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'product_service.dart';

/// Service for managing user favorites in `client_favorites` table.
class FavoriteService {
  static final _client = Supabase.instance.client;

  /// Fetches all favorites for the current client, including product details.
  static Future<List<Product>> getFavorites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final res = await _client
          .from('client_favorites')
          .select('product_id, products(${ProductService.publicProductColumns}, product_media(*), product_specs(*), product_inventory(*), active_product_promotions(*))')
          .eq('client_id', userId);

      final list = <Product>[];
      for (final row in res as List) {
        if (row['products'] != null) {
          list.add(Product.fromJson(row['products'] as Map<String, dynamic>));
        }
      }
      return list;
    } catch (e) {
      print('Error al obtener favoritos: $e');
      return [];
    }
  }

  /// Checks if a product is in the user's favorites list.
  static Future<bool> isFavorite(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final existing = await _client
          .from('client_favorites')
          .select('id')
          .eq('client_id', userId)
          .eq('product_id', productId)
          .maybeSingle();

      return existing != null;
    } catch (_) {
      return false;
    }
  }

  /// Toggles favorite status for a product.
  /// Returns `true` if added, `false` if removed.
  static Future<bool> toggleFavorite(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuario no autenticado');

    final existing = await _client
        .from('client_favorites')
        .select('id')
        .eq('client_id', userId)
        .eq('product_id', productId)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('client_favorites')
          .delete()
          .eq('id', existing['id'] as String);
      return false;
    } else {
      await _client
          .from('client_favorites')
          .insert({
            'client_id': userId,
            'product_id': productId,
          });
      return true;
    }
  }
}
