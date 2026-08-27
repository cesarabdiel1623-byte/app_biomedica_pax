import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../utils/price_formatter.dart';
import 'auth_identity_service.dart';
import 'product_service.dart';
import 'quote_service.dart';

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

  double get subtotal => roundFinancialAmount(
    roundFinancialAmount(product?.unitPriceMxn ?? 0) * quantity,
  );
  double get subtotalWithIva => subtotal * 1.16;
  double get ivaAmount => subtotal * 0.16;
}

class CartPricingAmounts {
  final double itemsSubtotal;
  final double productDiscount;
  final double eligibleSubtotal;
  final double couponDiscount;
  final double tax;
  final double total;
  final String currency;

  const CartPricingAmounts({
    required this.itemsSubtotal,
    required this.productDiscount,
    required this.eligibleSubtotal,
    required this.couponDiscount,
    required this.tax,
    required this.total,
    required this.currency,
  });

  double get effectiveItemsSubtotal => roundFinancialAmount(
    (itemsSubtotal - productDiscount).clamp(0.0, double.infinity),
  );

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
  }

  static CartPricingAmounts? fromRpc(dynamic response) {
    dynamic normalized = response;
    if (normalized is List && normalized.isNotEmpty) {
      normalized = normalized.first;
    }

    if (normalized is! Map) return null;

    final root = Map<String, dynamic>.from(normalized);
    final rawAmounts = root['amounts'];
    final amounts = rawAmounts is Map
        ? Map<String, dynamic>.from(rawAmounts)
        : root;

    if (!amounts.containsKey('total')) return null;

    return CartPricingAmounts(
      itemsSubtotal: roundFinancialAmount(_toDouble(amounts['items_subtotal'])),
      productDiscount: roundFinancialAmount(
        _toDouble(amounts['product_discount']),
      ),
      eligibleSubtotal: roundFinancialAmount(
        _toDouble(amounts['eligible_subtotal']),
      ),
      couponDiscount: roundFinancialAmount(
        _toDouble(amounts['coupon_discount']),
      ),
      tax: roundFinancialAmount(_toDouble(amounts['tax'])),
      total: roundFinancialAmount(_toDouble(amounts['total'])),
      currency: amounts['currency']?.toString().trim().isNotEmpty == true
          ? amounts['currency'].toString().trim()
          : 'MXN',
    );
  }
}

class CartCouponResult {
  final bool valid;
  final String? reason;
  final String message;
  final Map<String, dynamic> data;
  final CartPricingAmounts? amounts;

  const CartCouponResult({
    required this.valid,
    required this.message,
    this.reason,
    this.data = const {},
    this.amounts,
  });

  factory CartCouponResult.fromRpc(dynamic response) {
    dynamic normalized = response;
    if (normalized is List && normalized.isNotEmpty) {
      normalized = normalized.first;
    }

    if (normalized is! Map) {
      return const CartCouponResult(
        valid: false,
        message: 'El servidor devolvió una respuesta de cupón inválida.',
      );
    }

    final data = Map<String, dynamic>.from(normalized);
    final valid = data['valid'] == true;
    final reason = data['reason']?.toString().trim();
    final serverMessage = data['message']?.toString().trim();
    final message = serverMessage != null && serverMessage.isNotEmpty
        ? serverMessage
        : valid
        ? 'Cupón aplicado correctamente.'
        : (reason != null && reason.isNotEmpty
              ? reason
              : 'No fue posible aplicar el cupón.');

    return CartCouponResult(
      valid: valid,
      reason: reason == null || reason.isEmpty ? null : reason,
      message: message,
      data: data,
      amounts: CartPricingAmounts.fromRpc(data),
    );
  }

  CartCouponResult withAmounts(CartPricingAmounts? nextAmounts) {
    return CartCouponResult(
      valid: valid,
      reason: reason,
      message: message,
      data: data,
      amounts: nextAmounts ?? amounts,
    );
  }
}

class StaleCartCouponCleanupResult {
  final bool removed;
  final String? code;
  final String? reason;
  final String? message;
  final CartPricingAmounts? amounts;

  const StaleCartCouponCleanupResult({
    required this.removed,
    this.code,
    this.reason,
    this.message,
    this.amounts,
  });
}

/// Service for managing server-side cart using `carts` + `cart_items` tables
class CartService {
  static final _client = Supabase.instance.client;
  static final Set<String> _addingProductIds = {};
  static final Map<String, int> _cartQuantitiesLocalCache = {};

  /// Get cached quantity for a product in the cart
  static int getProductQtyInCart(String productId) {
    return _cartQuantitiesLocalCache[productId] ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null ? parsed.round() : 0;
    }
    return 0;
  }

  /// Get or create active cart for current user, populating profile details
  static Future<String> getOrCreateActiveCart() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');

    final clientId = await AuthIdentityService.requireLinkedClientId();

    // Try to find active cart
    final existing = await _client
        .from('carts')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')
        .maybeSingle();

    if (existing != null) return existing['id'] as String;

    // Fetch user details from profile to populate contact info in carts
    final profile = await _client
        .from('profiles')
        .select('full_name, email, phone')
        .eq('id', userId)
        .maybeSingle();

    try {
      // Create new cart with lead details
      final newCart = await _client
          .from('carts')
          .insert({
            'client_id': clientId,
            'status': 'active',
            'source': 'mobile_app',
            'lead_name':
                profile?['full_name'] ??
                _client.auth.currentUser?.email ??
                'Cliente',
            'lead_email': profile?['email'] ?? _client.auth.currentUser?.email,
            'lead_phone': profile?['phone'],
          })
          .select('id')
          .single();
      return newCart['id'] as String;
    } catch (e) {
      // If concurrent insert occurred, the active cart might now exist. Try fetching again.
      final retry = await _client
          .from('carts')
          .select('id')
          .eq('client_id', clientId)
          .eq('status', 'active')
          .maybeSingle();
      if (retry != null) {
        return retry['id'] as String;
      }
      rethrow;
    }
  }

  /// Comprueba de forma no intrusiva si el usuario actual tiene un carrito activo.
  static Future<bool> hasActiveCart() async {
    try {
      final clientId = await AuthIdentityService.getEffectiveClientId();
      if (clientId == null) return false;
      final cart = await _client
          .from('carts')
          .select('id')
          .eq('client_id', clientId)
          .eq('status', 'active')
          .maybeSingle();
      return cart != null;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _requireActiveCartId() async {
    final clientId = await AuthIdentityService.requireLinkedClientId();
    final cart = await _client
        .from('carts')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')
        .maybeSingle();

    if (cart == null) {
      throw Exception('No tienes un carrito activo.');
    }
    return cart['id'] as String;
  }

  static String? _readCouponCode(Map<String, dynamic> cart) {
    final code = cart['applied_coupon_code']?.toString().trim();
    if (code != null && code.isNotEmpty) return code;
    return null;
  }

  /// Validates and applies a coupon exclusively through the backend contract.
  static Future<CartCouponResult> applyCartCoupon(String code) async {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      throw Exception('Escribe un código de cupón.');
    }

    final cartId = await _requireActiveCartId();
    final response = await _client.rpc(
      'apply_cart_coupon',
      params: {'p_cart_id': cartId, 'p_code': normalizedCode},
    );
    var result = CartCouponResult.fromRpc(response);
    if (result.valid && result.amounts == null) {
      result = result.withAmounts(await getCartPricingAmounts());
    }
    return result;
  }

  /// Requests the authoritative cart pricing without calculating backend
  /// totals on the device.
  static Future<dynamic> getCartPricing() async {
    final cartId = await _requireActiveCartId();
    return _client.rpc('get_cart_pricing', params: {'p_cart_id': cartId});
  }

  static Future<CartPricingAmounts?> getCartPricingAmounts() async {
    return CartPricingAmounts.fromRpc(await getCartPricing());
  }

  static Future<CartPricingAmounts?> removeCartCoupon() async {
    final cartId = await _requireActiveCartId();
    await _client.rpc('remove_cart_coupon', params: {'p_cart_id': cartId});
    return getCartPricingAmounts();
  }

  static Future<StaleCartCouponCleanupResult>
  clearInvalidPersistedCouponIfAny() async {
    final cartId = await _requireActiveCartId();
    final cart = await _client
        .from('carts')
        .select('applied_coupon_id, applied_coupon_code')
        .eq('id', cartId)
        .maybeSingle();

    if (cart == null) {
      return const StaleCartCouponCleanupResult(removed: false);
    }

    final persistedCode = _readCouponCode(Map<String, dynamic>.from(cart));
    final hasPersistedCoupon =
        persistedCode != null || cart['applied_coupon_id'] != null;
    if (!hasPersistedCoupon) {
      return const StaleCartCouponCleanupResult(removed: false);
    }

    final pricingResponse = await getCartPricing();
    final pricingResult = CartCouponResult.fromRpc(pricingResponse);
    if (pricingResult.valid) {
      return StaleCartCouponCleanupResult(
        removed: false,
        code: persistedCode,
        amounts: pricingResult.amounts,
      );
    }

    await _client.rpc('remove_cart_coupon', params: {'p_cart_id': cartId});
    final refreshedAmounts = await getCartPricingAmounts();
    return StaleCartCouponCleanupResult(
      removed: true,
      code: persistedCode,
      reason: pricingResult.reason,
      message: pricingResult.message,
      amounts: refreshedAmounts,
    );
  }

  /// Get all items in the active cart with product details
  static Future<List<CartItem>> getCartItems() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final clientId = await AuthIdentityService.requireLinkedClientId();

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) return [];

    final cartId = cartData['id'] as String;
    final items = await _client
        .from('cart_items')
        .select('id, cart_id, product_id, quantity')
        .eq('cart_id', cartId);

    final cartItems = <CartItem>[];
    _cartQuantitiesLocalCache.clear();
    for (final item in items as List) {
      final product = await ProductService.getProductById(
        item['product_id'] as String,
      );
      final cartItem = CartItem(
        id: item['id'] as String,
        cartId: item['cart_id'] as String,
        productId: item['product_id'] as String,
        quantity: _toInt(item['quantity']),
        product: product,
      );
      cartItems.add(cartItem);
      _cartQuantitiesLocalCache[cartItem.productId] = cartItem.quantity;
    }
    return cartItems;
  }

  /// Add product to cart (or increment if exists)
  static Future<void> addToCart(String productId, {int quantity = 1}) async {
    if (_addingProductIds.contains(productId)) return;
    _addingProductIds.add(productId);

    try {
      // Garantizar exclusión mutua: si se añade al carrito, se remueve de cotizaciones
      await QuoteService.removeFromQuote(productId);

      final cartId = await getOrCreateActiveCart();

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
        final currentQty = _cartQuantitiesLocalCache[productId] ?? 0;
        if (currentQty + quantity > product.stock!) {
          throw Exception('stock_limit_reached:${product.stock}');
        }
      }

      if (existing != null) {
        final newQty = _toInt(existing['quantity']) + quantity;
        if (product != null &&
            product.stock != null &&
            newQty > product.stock!) {
          throw Exception('stock_limit_reached:${product.stock}');
        }
        // Increment quantity
        await _client
            .from('cart_items')
            .update({'quantity': newQty})
            .eq('id', existing['id']);
        _cartQuantitiesLocalCache[productId] = newQty;
      } else {
        if (product != null &&
            product.stock != null &&
            quantity > product.stock!) {
          throw Exception('stock_limit_reached:${product.stock}');
        }
        // Insert new item
        try {
          await _client.from('cart_items').insert({
            'cart_id': cartId,
            'product_id': productId,
            'quantity': quantity,
            'product_name_snapshot': product?.name ?? 'Producto',
            'sku_snapshot': product?.sku,
            'product_category_snapshot': product?.category,
          });
          _cartQuantitiesLocalCache[productId] = quantity;
        } catch (e) {
          // If concurrent insert occurred, update the existing item instead
          final retry = await _client
              .from('cart_items')
              .select('id, quantity')
              .eq('cart_id', cartId)
              .eq('product_id', productId)
              .maybeSingle();
          if (retry != null) {
            final newQty = _toInt(retry['quantity']) + quantity;
            if (product != null &&
                product.stock != null &&
                newQty > product.stock!) {
              throw Exception('stock_limit_reached:${product.stock}');
            }
            await _client
                .from('cart_items')
                .update({'quantity': newQty})
                .eq('id', retry['id']);
            _cartQuantitiesLocalCache[productId] = newQty;
            return;
          }
          rethrow;
        }
      }
    } finally {
      _addingProductIds.remove(productId);
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

    String? productId;
    if (item != null) {
      productId = item['product_id'] as String;
      final product = await ProductService.getProductById(productId);
      if (product != null && product.stock != null) {
        if (quantity > product.stock!) {
          throw Exception(
            'No puedes exceder el stock disponible de ${product.stock} unidades',
          );
        }
      }
    }

    await _client
        .from('cart_items')
        .update({'quantity': quantity})
        .eq('id', cartItemId);

    if (productId != null) {
      _cartQuantitiesLocalCache[productId] = quantity;
    }
  }

  /// Remove item from cart
  static Future<void> removeFromCart(String cartItemId) async {
    try {
      final item = await _client
          .from('cart_items')
          .select('product_id')
          .eq('id', cartItemId)
          .maybeSingle();
      if (item != null) {
        final productId = item['product_id'] as String;
        _cartQuantitiesLocalCache.remove(productId);
      }
    } catch (_) {}
    await _client.from('cart_items').delete().eq('id', cartItemId);
  }

  /// Remove product from cart by product ID
  static Future<void> removeProductFromCart(String productId) async {
    _cartQuantitiesLocalCache.remove(productId);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final clientId = await AuthIdentityService.requireLinkedClientId();

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) return;
    final cartId = cartData['id'] as String;

    await _client
        .from('cart_items')
        .delete()
        .eq('cart_id', cartId)
        .eq('product_id', productId);
  }

  /// Request a quote for the active cart and return the generated quote ID
  static Future<String> requestQuote({String notes = ''}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');

    final clientId = await AuthIdentityService.requireLinkedClientId();

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) throw Exception('No tienes un carrito activo');
    final cartId = cartData['id'] as String;

    final quoteId = await _client.rpc(
      'process_cart_quote',
      params: {'p_cart_id': cartId, 'p_notes': notes},
    );

    return quoteId as String;
  }

  /// Checks if a normalized phone number is already registered.
  ///
  /// The lookup stays behind the backend RPC so the mobile client cannot use
  /// the `clients` table to enumerate registered phone numbers.
  static Future<bool> isPhoneRegistered(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.isEmpty) return false;

    try {
      final bool exists = await _client.rpc(
        'check_phone_exists',
        params: {'p_phone': normalized},
      );
      return exists;
    } catch (_) {
      return false;
    }
  }

  /// Get item count in cart
  static Future<int> getCartCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    final clientId = await AuthIdentityService.requireLinkedClientId();

    final cartData = await _client
        .from('carts')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')
        .maybeSingle();

    if (cartData == null) return 0;

    final items = await _client
        .from('cart_items')
        .select('quantity')
        .eq('cart_id', cartData['id']);

    int total = 0;
    for (final item in items as List) {
      total += _toInt(item['quantity']);
    }
    return total;
  }

  static void clearLocalCartCache() {
    _cartQuantitiesLocalCache.clear();
  }
}
