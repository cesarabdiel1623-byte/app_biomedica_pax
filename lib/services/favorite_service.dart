import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'auth_identity_service.dart';
import 'product_service.dart';

/// Service for managing user favorites in `client_favorites` table.
class FavoriteService {
  static final _client = Supabase.instance.client;

  /// Resolves candidate client IDs for the authenticated user.
  /// Handles both auth UID (`auth.users.id` / `profiles.id`) and linked business client ID (`profiles.client_id`).
  static Future<List<String>> _resolveClientIds() async {
    final ids = <String>{};
    final user = _client.auth.currentUser;
    if (user != null && user.id.trim().isNotEmpty) {
      ids.add(user.id.trim());
    }
    try {
      final linkedClientId = await AuthIdentityService.getEffectiveClientId();
      if (linkedClientId != null && linkedClientId.trim().isNotEmpty) {
        ids.add(linkedClientId.trim());
      }
    } catch (_) {
      // Ignored: If profile has no linked client, auth.uid() is used.
    }
    return ids.toList();
  }

  /// Fetches all favorites for the current client, including product details.
  static Future<List<Product>> getFavorites() async {
    final clientIds = await _resolveClientIds();
    if (clientIds.isEmpty) return [];

    final dynamic favoriteRows;
    if (clientIds.length == 1) {
      favoriteRows = await _client
          .from('client_favorites')
          .select('product_id')
          .eq('client_id', clientIds.first);
    } else {
      favoriteRows = await _client
          .from('client_favorites')
          .select('product_id')
          .inFilter('client_id', clientIds);
    }

    final productIds = <String>[];
    for (final row in favoriteRows as List) {
      if (row is! Map) continue;
      final productId = row['product_id'];
      if (productId is String && productId.trim().isNotEmpty) {
        final trimmed = productId.trim();
        if (!productIds.contains(trimmed)) {
          productIds.add(trimmed);
        }
      }
    }

    if (productIds.isEmpty) return [];

    // Load products directly so a missing/deleted relation cannot invalidate
    // the complete favorites response.
    final dynamic productRows = await _client
        .from('products')
        .select(ProductService.publicProductSelect)
        .inFilter('id', productIds);

    final productsById = <String, Product>{};
    for (final row in productRows as List) {
      if (row is! Map) continue;
      try {
        final product = Product.fromJson(Map<String, dynamic>.from(row));
        productsById[product.id] = product;
      } catch (e) {
        debugPrint('Error al deserializar producto favorito: $e');
      }
    }

    return productIds
        .map((id) => productsById[id])
        .whereType<Product>()
        .toList();
  }

  /// Checks if a product is in the user's favorites list.
  static Future<bool> isFavorite(String productId) async {
    final clientIds = await _resolveClientIds();
    if (clientIds.isEmpty) return false;

    try {
      final dynamic existing;
      if (clientIds.length == 1) {
        existing = await _client
            .from('client_favorites')
            .select('id')
            .eq('client_id', clientIds.first)
            .eq('product_id', productId)
            .maybeSingle();
      } else {
        existing = await _client
            .from('client_favorites')
            .select('id')
            .inFilter('client_id', clientIds)
            .eq('product_id', productId)
            .maybeSingle();
      }

      return existing != null;
    } catch (_) {
      return false;
    }
  }

  /// Toggles favorite status for a product.
  /// Returns `true` if added, `false` if removed.
  static Future<bool> toggleFavorite(String productId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final clientIds = await _resolveClientIds();

    final dynamic existing;
    if (clientIds.length == 1) {
      existing = await _client
          .from('client_favorites')
          .select('id')
          .eq('client_id', clientIds.first)
          .eq('product_id', productId)
          .maybeSingle();
    } else {
      existing = await _client
          .from('client_favorites')
          .select('id')
          .inFilter('client_id', clientIds)
          .eq('product_id', productId)
          .maybeSingle();
    }

    if (existing != null) {
      await _client
          .from('client_favorites')
          .delete()
          .eq('id', existing['id'] as String);
      return false;
    } else {
      await _client.from('client_favorites').insert({
        'client_id': user.id,
        'product_id': productId,
      });
      return true;
    }
  }
}
