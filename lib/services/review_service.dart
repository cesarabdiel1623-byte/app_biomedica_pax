import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'product_service.dart';

/// Product Review model containing rating, comment and images.
class ProductReview {
  final String id;
  final String productId;
  final String clientId;
  final String clientName;
  final int rating;
  final String? comment;
  final List<String> images;
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
    required this.createdAt,
    this.product,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    // Joins with profiles table to get full_name
    final profileData = json['profiles'] as Map<String, dynamic>?;
    final clientName = profileData != null ? (profileData['full_name'] as String? ?? 'Usuario') : 'Usuario';
    
    final rawImgs = json['images'] as List? ?? [];
    final images = List<String>.from(rawImgs.map((i) => i.toString()));

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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      product: product,
    );
  }
}

/// Service for managing product reviews.
class ReviewService {
  static final _client = Supabase.instance.client;

  /// Get all reviews for a product.
  static Future<List<ProductReview>> getReviews(String productId) async {
    final response = await _client
        .from('product_reviews')
        .select('*, profiles:profiles!client_id ( full_name )')
        .eq('product_id', productId)
        .order('created_at', ascending: false);

    return (response as List).map((j) => ProductReview.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Get all reviews written by the current client.
  static Future<List<ProductReview>> getClientReviews() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('product_reviews')
          .select('*, products(${ProductService.publicProductColumns}, product_media(*), product_specs(*), product_inventory(*), active_product_promotions(*))')
          .eq('client_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((j) => ProductReview.fromJson(j as Map<String, dynamic>)).toList();
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
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuario no autenticado');

    await _client.from('product_reviews').insert({
      'product_id': productId,
      'client_id': userId,
      'rating': rating,
      'comment': comment,
      'images': imageUrls,
    });
  }

  /// Upload review photo and return public url.
  static Future<String> uploadReviewPhoto(String productId, Uint8List fileBytes, String fileName) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuario no autenticado');

    final extension = fileName.split('.').last;
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}.$extension';
    final filePath = '$productId/$userId/$uniqueName';

    await _client.storage.from('review-assets').uploadBinary(
          filePath,
          fileBytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );

    final publicUrl = _client.storage.from('review-assets').getPublicUrl(filePath);
    return publicUrl;
  }
}
