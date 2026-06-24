import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'product_service.dart';

/// Cart item model combining cart_items data with product info
class CartItem {
  final String id;
  final String cartId;
  final String productId;
  int quantity;
  final Product? product;

  CartItem({
    required this.id,
    required this.cartId,
    required this.productId,
    required this.quantity,
    this.product,
  });

  double get subtotal => (product?.unitPriceMxn ?? 0) * quantity;
  double get subtotalWithIva => subtotal * 1.16;
  double get ivaAmount => subtotal * 0.16;
}

/// Service for managing server-side cart using `carts` + `cart_items` tables
class CartService {
  static final _client = Supabase.instance.client;

  /// Ensure a client record exists for the current user.
  /// Users registered before the auto-create trigger was set up may be missing one.
  static Future<void> _ensureClientExists(String userId) async {
    final existing = await _client
        .from('clients')
        .select('id')
        .eq('id', userId)
        .maybeSingle();

    if (existing != null) return; // already exists

    final user = _client.auth.currentUser;
    final email = user?.email ?? '';
    final name = user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String? ??
        email;

    await _client.from('clients').upsert({
      'id': userId,
      'client_type': 'otro',
      'status': 'active',
      'business_name': name.isNotEmpty ? name : email,
      'contact_name': name,
      'email': email,
      'is_active': true,
      'preferred_currency': 'MXN',
      'country': 'México',
    }, onConflict: 'id');

    // Also update profiles.client_id so RLS helper functions work correctly
    await _client
        .from('profiles')
        .update({'client_id': userId})
        .eq('id', userId)
        .eq('role', 'client');
  }

  /// Get or create active cart for current user
  static Future<String> _getOrCreateCart() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');

    // Ensure client record exists (handles legacy users without one)
    await _ensureClientExists(userId);

    // Try to find active cart
    final existing = await _client
        .from('carts')
        .select('id')
        .eq('client_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (existing != null) return existing['id'] as String;

    try {
      // Create new cart
      final newCart = await _client
          .from('carts')
          .insert({'client_id': userId, 'status': 'active'})
          .select('id')
          .single();
      return newCart['id'] as String;
    } catch (e) {
      // If concurrent insert occurred, the active cart might now exist. Try fetching again.
      final retry = await _client
          .from('carts')
          .select('id')
          .eq('client_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      if (retry != null) {
        return retry['id'] as String;
      }
      rethrow;
    }
  }

  /// Get all items in the active cart with product details
  static Future<List<CartItem>> getCartItems() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) return [];

    final cartId = cartData['id'] as String;
    final items = await _client
        .from('cart_items')
        .select('id, cart_id, product_id, quantity')
        .eq('cart_id', cartId);

    final cartItems = <CartItem>[];
    for (final item in items as List) {
      final product = await ProductService.getProductById(item['product_id'] as String);
      cartItems.add(CartItem(
        id: item['id'] as String,
        cartId: item['cart_id'] as String,
        productId: item['product_id'] as String,
        quantity: item['quantity'] as int? ?? 1,
        product: product,
      ));
    }
    return cartItems;
  }

  /// Add product to cart (or increment if exists)
  static Future<void> addToCart(String productId, {int quantity = 1}) async {
    final cartId = await _getOrCreateCart();

    // Check if product already in cart
    final existing = await _client
        .from('cart_items')
        .select('id, quantity')
        .eq('cart_id', cartId)
        .eq('product_id', productId)
        .maybeSingle();

    // Check stock limit if tracked
    final product = await ProductService.getProductById(productId);
    if (product != null && product.stock != null) {
      final inCartQty = existing != null ? (existing['quantity'] as int) : 0;
      if (inCartQty + quantity > product.stock!) {
        if (product.stock! <= 0) {
          throw Exception('Producto sin stock disponible');
        }
        throw Exception('No puedes agregar más de este producto. Stock disponible: ${product.stock} (ya tienes $inCartQty en tu carrito)');
      }
    }

    if (existing != null) {
      // Increment quantity
      await _client
          .from('cart_items')
          .update({'quantity': (existing['quantity'] as int) + quantity})
          .eq('id', existing['id']);
    } else {
      // Insert new item
      try {
        await _client
            .from('cart_items')
            .insert({
              'cart_id': cartId,
              'product_id': productId,
              'quantity': quantity,
            });
      } catch (e) {
        // If concurrent insert occurred, update the existing item instead
        final retry = await _client
            .from('cart_items')
            .select('id, quantity')
            .eq('cart_id', cartId)
            .eq('product_id', productId)
            .maybeSingle();
        if (retry != null) {
          await _client
              .from('cart_items')
              .update({'quantity': (retry['quantity'] as int) + quantity})
              .eq('id', retry['id']);
          return;
        }
        rethrow;
      }
    }
  }

  /// Update quantity for a cart item
  static Future<void> updateQuantity(String cartItemId, int quantity) async {
    if (quantity <= 0) {
      await removeFromCart(cartItemId);
      return;
    }

    // Check stock limit before updating quantity
    final item = await _client
        .from('cart_items')
        .select('product_id')
        .eq('id', cartItemId)
        .maybeSingle();

    if (item != null) {
      final productId = item['product_id'] as String;
      final product = await ProductService.getProductById(productId);
      if (product != null && product.stock != null) {
        if (quantity > product.stock!) {
          throw Exception('No puedes exceder el stock disponible de ${product.stock} unidades');
        }
      }
    }

    await _client
        .from('cart_items')
        .update({'quantity': quantity})
        .eq('id', cartItemId);
  }

  /// Remove item from cart
  static Future<void> removeFromCart(String cartItemId) async {
    await _client
        .from('cart_items')
        .delete()
        .eq('id', cartItemId);
  }

  /// Checkout the active cart and return the generated order ID
  static Future<String> checkout({String paymentMethod = 'other', String notes = ''}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) throw Exception('No tienes un carrito activo');
    final cartId = cartData['id'] as String;

    final orderId = await _client.rpc('process_cart_checkout', params: {
      'p_cart_id': cartId,
      'p_payment_method': paymentMethod,
      'p_notes': notes,
    });

    return orderId as String;
  }

  /// Request a quote for the active cart and return the generated quote ID
  static Future<String> requestQuote({String notes = ''}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) throw Exception('No tienes un carrito activo');
    final cartId = cartData['id'] as String;

    final quoteId = await _client.rpc('process_cart_quote', params: {
      'p_cart_id': cartId,
      'p_notes': notes,
    });

    return quoteId as String;
  }

  /// Get item count in cart
  static Future<int> getCartCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) return 0;

    final items = await _client
        .from('cart_items')
        .select('quantity')
        .eq('cart_id', cartData['id']);

    int total = 0;
    for (final item in items as List) {
      total += item['quantity'] as int? ?? 1;
    }
    return total;
  }
}
