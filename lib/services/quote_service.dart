import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/quote_item.dart';
import 'product_service.dart';
import 'cart_service.dart';


class QuoteService {
  static const String _keyQuote = 'quote_cart_items';
  static final ValueNotifier<int> quoteCountNotifier = ValueNotifier<int>(0);

  /// Initializes the quote count notifier. Should be called at app startup.
  static Future<void> init() async {
    await loadCount();
  }

  /// Calculates the sum of quantities in the quote cart and updates the notifier.
  static Future<int> loadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyQuote) ?? [];
      int count = 0;
      for (final itemStr in list) {
        try {
          final map = jsonDecode(itemStr) as Map<String, dynamic>;
          count += map['quantity'] as int? ?? 1;
        } catch (_) {}
      }
      quoteCountNotifier.value = count;
      return count;
    } catch (_) {
      quoteCountNotifier.value = 0;
      return 0;
    }
  }

  /// Retrieves the list of quote items with populated product details.
  static Future<List<QuoteItem>> getQuoteItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyQuote) ?? [];
      final quoteItems = <QuoteItem>[];

      for (final itemStr in list) {
        try {
          final map = jsonDecode(itemStr) as Map<String, dynamic>;
          final item = QuoteItem.fromJson(map);
          quoteItems.add(item);
        } catch (_) {}
      }

      // Load products in parallel
      await Future.wait(
        quoteItems.map((item) async {
          try {
            item.product = await ProductService.getProductById(item.productId);
          } catch (e) {
            debugPrint('Error loading product ${item.productId} for quote: $e');
          }
        }),
      );

      // Keep only items that have a valid product
      quoteItems.removeWhere((item) => item.product == null);

      return quoteItems;
    } catch (e) {
      debugPrint('Error getting quote items: $e');
      return [];
    }
  }

  /// Adds a product to the quote cart, or increments the quantity if it already exists.
  static Future<void> addToQuote(Product product, {int quantity = 1}) async {
    try {
      // Garantizar exclusión mutua: si se añade a cotizaciones, se remueve del carrito
      await CartService.removeProductFromCart(product.id);

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyQuote) ?? [];
      
      int existingIndex = -1;
      final items = <QuoteItem>[];

      for (int i = 0; i < list.length; i++) {
        try {
          final map = jsonDecode(list[i]) as Map<String, dynamic>;
          final item = QuoteItem.fromJson(map);
          items.add(item);
          if (item.productId == product.id) {
            existingIndex = i;
          }
        } catch (_) {}
      }

      if (existingIndex != -1) {
        items[existingIndex].quantity += quantity;
      } else {
        items.add(QuoteItem(productId: product.id, quantity: quantity, product: product));
      }

      final newListStr = items.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList(_keyQuote, newListStr);
      await loadCount();
    } catch (e) {
      debugPrint('Error adding to quote: $e');
    }
  }

  /// Updates the quantity of a product in the quote cart. Removes if quantity <= 0.
  static Future<void> updateQuantity(String productId, int quantity) async {
    if (quantity <= 0) {
      await removeFromQuote(productId);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyQuote) ?? [];
      final items = <QuoteItem>[];

      for (final itemStr in list) {
        try {
          final map = jsonDecode(itemStr) as Map<String, dynamic>;
          final item = QuoteItem.fromJson(map);
          if (item.productId == productId) {
            item.quantity = quantity;
          }
          items.add(item);
        } catch (_) {}
      }

      final newListStr = items.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList(_keyQuote, newListStr);
      await loadCount();
    } catch (e) {
      debugPrint('Error updating quote quantity: $e');
    }
  }

  /// Removes a product from the quote cart.
  static Future<void> removeFromQuote(String productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyQuote) ?? [];
      final items = <QuoteItem>[];

      for (final itemStr in list) {
        try {
          final map = jsonDecode(itemStr) as Map<String, dynamic>;
          final item = QuoteItem.fromJson(map);
          if (item.productId != productId) {
            items.add(item);
          }
        } catch (_) {}
      }

      final newListStr = items.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList(_keyQuote, newListStr);
      await loadCount();
    } catch (e) {
      debugPrint('Error removing from quote: $e');
    }
  }

  /// Clears the quote cart.
  static Future<void> clearQuote() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyQuote);
      quoteCountNotifier.value = 0;
    } catch (e) {
      debugPrint('Error clearing quote: $e');
    }
  }

  /// Submits the quote request to Supabase in a two-step transaction.
  /// 1. Inserts the header record in `quote_requests`
  /// 2. Inserts all products in `quote_request_items`
  /// returns the request number if successful.
  static Future<String> sendQuoteRequest({
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required String companyName,
    required String message,
  }) async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    final items = await getQuoteItems();

    if (items.isEmpty) {
      throw Exception('La bolsa de cotizaciones está vacía');
    }

    // Generate readable quote request number
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final randStr = (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    final requestNumber = 'RQ-$dateStr-$randStr';

    final requestPayload = {
      'request_number': requestNumber,
      'profile_id': currentUser?.id,
      'source': 'mobile_app',
      'status': 'pending',
      'contact_name': contactName.trim(),
      'contact_email': contactEmail.trim(),
      'contact_phone': contactPhone.trim().isEmpty ? null : contactPhone.trim(),
      'company_name': companyName.trim().isEmpty ? null : companyName.trim(),
      'message': message.trim().isEmpty ? null : message.trim(),
    };

    // Step A: Insert quote_requests header
    final requestData = await client
        .from('quote_requests')
        .insert(requestPayload)
        .select('id')
        .single();

    final quoteRequestId = requestData['id'] as String;

    // Step B: Insert quote_request_items
    final itemsPayload = items.map((item) => {
      'quote_request_id': quoteRequestId,
      'product_id': item.productId,
      'item_name': item.product?.name ?? 'Producto',
      'sku': item.product?.sku,
      'quantity': item.quantity,
      'notes': null,
    }).toList();

    await client.from('quote_request_items').insert(itemsPayload);

    // Clear local quote list on success
    await clearQuote();

    return requestNumber;
  }
}
