import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'auth_identity_service.dart';
import 'product_service.dart';

class ProductAnswer {
  final String id;
  final String answerText;
  final bool isPublic;
  final DateTime createdAt;

  ProductAnswer({
    required this.id,
    required this.answerText,
    required this.isPublic,
    required this.createdAt,
  });

  factory ProductAnswer.fromJson(Map<String, dynamic> json) {
    return ProductAnswer(
      id: json['id'] as String,
      answerText: json['answer_text'] as String? ?? '',
      isPublic: json['is_public'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class ProductQuestion {
  final String id;
  final String? clientId;
  final String productId;
  final String questionText;
  final String status;
  final bool isPublic;
  final DateTime createdAt;
  final Product? product;
  final List<ProductAnswer> answers;

  ProductQuestion({
    required this.id,
    this.clientId,
    required this.productId,
    required this.questionText,
    required this.status,
    required this.isPublic,
    required this.createdAt,
    this.product,
    required this.answers,
  });

  /// Getter for backward compatibility with existing screens accessing answerText directly.
  String? get answerText => answers.isNotEmpty ? answers.first.answerText : null;

  factory ProductQuestion.fromJson(Map<String, dynamic> json) {
    final productData = json['products'] as Map<String, dynamic>?;
    final product = productData != null ? Product.fromJson(productData) : null;

    final answersList = <ProductAnswer>[];
    if (json['product_answers'] != null) {
      if (json['product_answers'] is List) {
        for (final a in json['product_answers']) {
          answersList.add(ProductAnswer.fromJson(a as Map<String, dynamic>));
        }
      } else if (json['product_answers'] is Map) {
        answersList.add(ProductAnswer.fromJson(json['product_answers'] as Map<String, dynamic>));
      }
    }

    return ProductQuestion(
      id: json['id'] as String,
      clientId: json['client_id'] as String?,
      productId: json['product_id'] as String,
      questionText: json['question_text'] as String,
      status: json['status'] as String? ?? 'pending',
      isPublic: json['is_public'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      product: product,
      answers: answersList,
    );
  }
}

class QuestionService {
  static final _client = Supabase.instance.client;

  /// Fetches all questions asked by the current client.
  static Future<List<ProductQuestion>> getClientQuestions() async {
    final clientId = await AuthIdentityService.getEffectiveClientId();
    if (clientId == null) return [];

    try {
      final res = await _client
          .from('product_questions')
          .select('*, product_answers(*), products(${ProductService.publicProductSelect})')
          .eq('client_id', clientId)
          .order('created_at', ascending: false);

      return (res as List)
          .map((e) => ProductQuestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error al obtener preguntas: $e');
      return [];
    }
  }

  static Future<List<ProductQuestion>> getProductQuestions(String productId) async {
    try {
      final res = await _client
          .from('product_questions')
          .select('*, product_answers(*), products(${ProductService.publicProductColumns})')
          .eq('product_id', productId)
          .eq('is_public', true)
          .order('created_at', ascending: false);

      return (res as List)
          .map((e) => ProductQuestion.fromJson(e as Map<String, dynamic>))
          .where((q) => (q.status == 'answered' || q.status == 'pending') && q.isPublic == true)
          .toList();
    } catch (e) {
      print('Error al obtener preguntas de producto: $e');
      return [];
    }
  }

  /// Submits a new question for a product using a secure RPC.
  static Future<void> askQuestion(String productId, String text) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuario no autenticado');

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _client.rpc(
      'submit_product_question',
      params: {
        'p_product_id': productId,
        'p_question_text': trimmed,
      },
    );
  }

  /// Deletes a question by its ID.
  static Future<void> deleteQuestion(String questionId) async {
    await _client
        .from('product_questions')
        .delete()
        .eq('id', questionId);
  }
}
