import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'auth_identity_service.dart';
import 'product_service.dart';
import '../utils/ui_helpers.dart';

/// Product Review model containing rating, comment and images.
class ProductReview {
  final String id;
  final String productId;
  final String clientId;
  final String clientName;
  final int rating;
  final String? comment;
  final List<String> images;
  final List<String> videos;
  final DateTime createdAt;
  final Product? product;

  ProductReview({
    required this.id,
    required this.productId,
    required this.clientId,
    required this.clientName,
    required this.rating,
    this.comment,
    required this.images,
    this.videos = const [],
    required this.createdAt,
    this.product,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    // Joins with profiles table to get full_name
    final profileData = json['profiles'] as Map<String, dynamic>?;
    final clientName = profileData != null
        ? (profileData['full_name'] as String? ?? 'Usuario')
        : 'Usuario';

    final rawMedia = json['images'] as List? ?? [];
    final mediaUrls = rawMedia
        .map((i) => UiHelpers.sanitizeTrustedRemoteUrl(i.toString()))
        .whereType<String>()
        .toList();
    final images = mediaUrls
        .where((url) => !ReviewService.isVideoUrl(url))
        .toList();
    final videos = mediaUrls.where(ReviewService.isVideoUrl).toList();

    final productData = json['products'] as Map<String, dynamic>?;
    final product = productData != null ? Product.fromJson(productData) : null;

    return ProductReview(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      clientId: json['client_id'] as String,
      clientName: clientName,
      rating: json['rating'] as int? ?? 5,
      comment: json['comment'] as String?,
      images: images,
      videos: videos,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      product: product,
    );
  }
}

/// Service for managing product reviews.
class ReviewService {
  static final _client = Supabase.instance.client;
  static const _videoExtensions = {'mp4', 'mov', 'm4v', 'webm'};
  static const maxReviewVideoBytes = 40 * 1024 * 1024;

  static bool isVideoUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    final extension = path.contains('.') ? path.split('.').last : '';
    return _videoExtensions.contains(extension);
  }

  /// Get all reviews for a product.
  static Future<List<ProductReview>> getReviews(String productId) async {
    final response = await _client
        .from('product_reviews')
        .select('*, profiles:profiles!client_id ( full_name )')
        .eq('product_id', productId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((j) => ProductReview.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Get all reviews written by the current client.
  static Future<List<ProductReview>> getClientReviews() async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) return [];

    try {
      final response = await _client
          .from('product_reviews')
          .select('*, products(${ProductService.publicProductSelect})')
          .eq('client_id', clientId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((j) => ProductReview.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error al obtener opiniones: $e');
      return [];
    }
  }

  /// Add a new product review.
  static Future<void> addReview({
    required String productId,
    required int rating,
    required String comment,
    required List<String> imageUrls,
    List<String> videoUrls = const [],
  }) async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) throw Exception('Usuario no autenticado');

    await _client.from('product_reviews').insert({
      'product_id': productId,
      'client_id': clientId,
      'rating': rating,
      'comment': comment,
      'images': [...imageUrls, ...videoUrls],
    });
  }

  /// Upload review photo and return public url.
  static Future<String> uploadReviewPhoto(
    String productId,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) throw Exception('Usuario no autenticado');

    UiHelpers.validateImageUpload(fileBytes, fileName);
    final extension = UiHelpers.requireAllowedImageExtension(fileName);
    final uniqueName =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}.$extension';
    final filePath = '$productId/$clientId/$uniqueName';

    await _client.storage
        .from('review-assets')
        .uploadBinary(
          filePath,
          fileBytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );

    final publicUrl = _client.storage
        .from('review-assets')
        .getPublicUrl(filePath);
    final trustedUrl = UiHelpers.sanitizeTrustedRemoteUrl(publicUrl);
    if (trustedUrl == null) {
      throw Exception('No se pudo generar una URL segura para la imagen.');
    }
    return trustedUrl;
  }

  /// Upload a short review video and return its public URL.
  static Future<String> uploadReviewVideo(
    String productId,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) throw Exception('Usuario no autenticado');
    if (fileBytes.isEmpty) throw Exception('El video está vacío.');
    if (fileBytes.length > maxReviewVideoBytes) {
      throw Exception('El video supera el límite de 40 MB.');
    }

    final cleanName = fileName.split('?').first;
    final extension = cleanName.contains('.')
        ? cleanName.split('.').last.toLowerCase()
        : '';
    if (!_videoExtensions.contains(extension)) {
      throw Exception('Formato de video no permitido.');
    }

    final contentType = switch (extension) {
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'm4v' => 'video/x-m4v',
      _ => 'video/mp4',
    };
    final uniqueName =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}.$extension';
    final filePath = '$productId/$clientId/$uniqueName';

    await _client.storage
        .from('review-assets')
        .uploadBinary(
          filePath,
          fileBytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: contentType,
          ),
        );

    final publicUrl = _client.storage
        .from('review-assets')
        .getPublicUrl(filePath);
    final trustedUrl = UiHelpers.sanitizeTrustedRemoteUrl(publicUrl);
    if (trustedUrl == null) {
      await _client.storage.from('review-assets').remove([filePath]);
      throw Exception('No se pudo generar una URL segura para el video.');
    }
    return trustedUrl;
  }

  /// Verifies if the client has purchased a specific product.
  static Future<bool> hasPurchasedProduct(String productId) async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) return false;

    try {
      final response = await _client
          .from('orders')
          .select('id')
          .eq('client_id', clientId)
          .neq('status', 'draft')
          .neq('status', 'canceled');

      if (response.isEmpty) return false;

      final orderIds = response.map((o) => o['id'] as String).toList();

      final itemsResponse = await _client
          .from('order_items')
          .select('id')
          .inFilter('order_id', orderIds)
          .eq('product_id', productId)
          .limit(1);

      return itemsResponse.isNotEmpty;
    } catch (e) {
      print('Error al verificar compra del producto: $e');
      return false;
    }
  }

  /// Checks if the client has already reviewed a specific product and returns it.
  static Future<ProductReview?> getProductReviewByClient(
    String productId,
  ) async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) return null;

    try {
      final response = await _client
          .from('product_reviews')
          .select('*, products(${ProductService.publicProductSelect})')
          .eq('client_id', clientId)
          .eq('product_id', productId)
          .maybeSingle();

      if (response == null) return null;
      return ProductReview.fromJson(response);
    } catch (e) {
      print('Error al obtener reseña del cliente: $e');
      return null;
    }
  }

  /// Updates an existing review.
  static Future<void> updateReview({
    required String reviewId,
    required int rating,
    required String comment,
    required List<String> imageUrls,
    List<String> videoUrls = const [],
  }) async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) throw Exception('Usuario no autenticado');

    await _client
        .from('product_reviews')
        .update({
          'rating': rating,
          'comment': comment,
          'images': [...imageUrls, ...videoUrls],
        })
        .eq('id', reviewId)
        .eq('client_id', clientId);
  }

  /// Delete one review owned by the authenticated client.
  static Future<void> deleteReview(String reviewId) async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) throw Exception('Usuario no autenticado');

    final current = await _client
        .from('product_reviews')
        .select('images')
        .eq('id', reviewId)
        .eq('client_id', clientId)
        .maybeSingle();
    final mediaUrls = (current?['images'] as List? ?? [])
        .map((value) => value.toString())
        .toList();

    final deleted = await _client
        .from('product_reviews')
        .delete()
        .eq('id', reviewId)
        .eq('client_id', clientId)
        .select('id');
    if (deleted.isEmpty) {
      throw Exception('No se pudo eliminar la opinión.');
    }

    for (final url in mediaUrls) {
      try {
        await deleteUploadedAsset(url);
      } catch (_) {
        // The review is already deleted; stale storage is cleaned best-effort.
      }
    }
  }

  static Future<void> deleteUploadedAsset(String publicUrl) async {
    final uri = Uri.tryParse(publicUrl);
    if (uri == null) return;
    const marker = '/storage/v1/object/public/review-assets/';
    final markerIndex = uri.path.indexOf(marker);
    if (markerIndex < 0) return;

    final encodedPath = uri.path.substring(markerIndex + marker.length);
    final filePath = Uri.decodeComponent(encodedPath);
    if (filePath.isEmpty) return;
    await _client.storage.from('review-assets').remove([filePath]);
  }

  /// Get all unique products purchased by the user that have NOT been reviewed yet.
  static Future<List<Map<String, dynamic>>> getPendingReviews() async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) return [];

    try {
      // 1. Get already reviewed product IDs
      final clientReviews = await getClientReviews();
      final reviewedIds = clientReviews.map((r) => r.productId).toSet();

      // 2. Get user orders
      final ordersResponse = await _client
          .from('orders')
          .select('id, created_at')
          .eq('client_id', clientId)
          .neq('status', 'draft')
          .neq('status', 'canceled')
          .order('created_at', ascending: false);

      if (ordersResponse.isEmpty) return [];

      final orderDataMap = {
        for (var o in ordersResponse)
          o['id'] as String: o['created_at'] as String?,
      };
      final orderIds = orderDataMap.keys.toList();

      // 3. Get order items for these orders
      final itemsResponse = await _client
          .from('order_items')
          .select(
            'product_id, product_name_snapshot, order_id, products(${ProductService.publicProductSelect})',
          )
          .inFilter('order_id', orderIds);

      if (itemsResponse.isEmpty) return [];

      final pending = <Map<String, dynamic>>[];
      final seenProductIds = <String>{};

      for (var item in itemsResponse) {
        final productId = item['product_id'] as String?;
        if (productId == null) continue;

        // Skip if already reviewed or if we already processed this product in this list
        if (reviewedIds.contains(productId) ||
            seenProductIds.contains(productId)) {
          continue;
        }

        seenProductIds.add(productId);

        final productJson = item['products'] as Map<String, dynamic>?;
        final product = productJson != null
            ? Product.fromJson(productJson)
            : null;
        if (product == null) continue;

        final orderId = item['order_id'] as String;
        final dateStr = orderDataMap[orderId];
        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;

        pending.add({'product': product, 'purchasedAt': date});
      }

      return pending;
    } catch (e) {
      print('Error al obtener opiniones pendientes: $e');
      return [];
    }
  }
}
