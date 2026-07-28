import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
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

  double get subtotal => (product?.unitPriceMxn ?? 0) * quantity;
  double get subtotalWithIva => subtotal * 1.16;
  double get ivaAmount => subtotal * 0.16;
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

  /// Get client ID linked to user profile, with fallback to userId
  static Future<String> _getClientId(String userId) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('client_id')
          .eq('id', userId)
          .maybeSingle();
      if (profile != null && profile['client_id'] != null) {
        return profile['client_id'] as String;
      }
    } catch (_) {
      // Ignorar errores al buscar perfil
    }
    return userId;
  }

  /// Ensure a client record exists for the current user.
  /// Users registered before the auto-create trigger was set up may be missing one.
  static Future<void> _ensureClientExists(String userId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final email = (user.email ?? '').trim().toLowerCase();

    // 1. Intentar obtener el perfil del usuario actual para ver su client_id
    Map<String, dynamic>? profile;
    try {
      profile = await _client
          .from('profiles')
          .select('client_id, full_name, email, phone')
          .eq('id', userId)
          .maybeSingle();
    } catch (_) {
      // Ignorar errores al leer perfil
    }

    String? linkedClientId = profile?['client_id'];

    if (linkedClientId != null && linkedClientId.isNotEmpty) {
      // El perfil ya tiene un client_id vinculado.
      // Verificamos si ese registro de cliente existe en la tabla clients.
      try {
        final clientRecord = await _client
            .from('clients')
            .select('id')
            .eq('id', linkedClientId)
            .maybeSingle();

        if (clientRecord != null) {
          // Todo correcto: el cliente existe y está vinculado.
          return;
        }
      } catch (_) {
        // Ignorar error al verificar existencia del cliente
      }
    }

    // 2. Si no tiene client_id o el cliente no existe, buscamos por correo normalizado
    String? clientIdToLink = linkedClientId;

    if (email.isNotEmpty) {
      try {
        final existingClient = await _client
            .from('clients')
            .select('id')
            .eq('email', email)
            .maybeSingle();

        if (existingClient != null) {
          clientIdToLink = existingClient['id'] as String;
          // Actualizar acceso a la app del cliente existente
          await _client
              .from('clients')
              .update({
                'has_app_access': true,
                'app_registered_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', clientIdToLink);
        }
      } catch (_) {
        // Ignorar error al buscar cliente existente
      }
    }

    // 3. Si no se encontró cliente por correo, creamos uno nuevo
    if (clientIdToLink == null || clientIdToLink.isEmpty) {
      final name =
          user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String? ??
          email;
      final phone = user.phone ?? '';

      try {
        // Insertamos un nuevo cliente y dejamos que la base genere el UUID
        final newClient = await _client
            .from('clients')
            .insert({
              'client_type': 'otro',
              'status': 'active',
              'business_name': name.isNotEmpty ? name : email,
              'contact_name': name,
              'email': email,
              'phone': phone,
              'is_active': true,
              'preferred_currency': 'MXN',
              'country': 'México',
              'source': 'mobile_app',
              'has_app_access': true,
              'profile_completed': false,
              'app_registered_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();

        clientIdToLink = newClient['id'] as String;
      } catch (e) {
        // En caso de que se haya insertado en paralelo o haya restricción unique, re-buscamos por email
        if (email.isNotEmpty) {
          try {
            final retryClient = await _client
                .from('clients')
                .select('id')
                .eq('email', email)
                .maybeSingle();
            if (retryClient != null) {
              clientIdToLink = retryClient['id'] as String;
            }
          } catch (_) {}
        }
        if (clientIdToLink == null) rethrow;
      }
    }

    // 4. Crear o actualizar el perfil vinculándolo con el clientIdToLink
    final fullName =
        user.userMetadata?['full_name'] as String? ??
        user.userMetadata?['name'] as String? ??
        'Sin especificar';
    final phone = user.phone ?? '';

    try {
      await _client.from('profiles').upsert({
        'id': userId,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'role': 'client',
        'client_id': clientIdToLink,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Ignorar errores al guardar/actualizar perfiles
    }
  }

  /// Get or create active cart for current user, populating profile details
  static Future<String> getOrCreateActiveCart() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');

    // Ensure client record exists (handles legacy users without one)
    await _ensureClientExists(userId);

    final clientId = await _getClientId(userId);

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

  /// Get all items in the active cart with product details
  static Future<List<CartItem>> getCartItems() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final clientId = await _getClientId(userId);

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
            'unit_price': product?.unitPriceMxn ?? 0.0,
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

    final clientId = await _getClientId(userId);

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

    final clientId = await _getClientId(userId);

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

  /// Checks if a normalized phone number is already registered in clients with has_app_access = true.
  /// Bypasses RLS using custom database RPC or does a selective fallback query.
  static Future<bool> isPhoneRegistered(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.isEmpty) return false;

    try {
      // 1. Try invoking the RPC function (most secure and accurate, bypasses RLS)
      final bool exists = await _client.rpc(
        'check_phone_exists',
        params: {'p_phone': normalized},
      );
      return exists;
    } catch (e) {
      // 2. Fallback to direct query if RPC doesn't exist yet
      try {
        final List<dynamic> result = await _client
            .from('clients')
            .select('id')
            .eq('has_app_access', true)
            .or('phone.eq.$normalized,phone.eq.+52$normalized');
        return result.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  /// Get item count in cart
  static Future<int> getCartCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    final clientId = await _getClientId(userId);

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
}
