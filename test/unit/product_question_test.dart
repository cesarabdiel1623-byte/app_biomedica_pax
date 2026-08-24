import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/services/question_service.dart';

void main() {
  group('ProductQuestion.fromJson', () {
    test('preserves a historical question when its product is unavailable', () {
      final question = ProductQuestion.fromJson({
        'id': 'question-1',
        'client_id': 'client-1',
        'product_id': 'removed-product-1',
        'question_text': '¿Qué incluye el equipo?',
        'status': 'answered',
        'is_public': true,
        'created_at': '2026-08-01T12:00:00Z',
        'products': null,
        'product_answers': [
          {
            'id': 'answer-1',
            'answer_text': 'Incluye todos sus cables.',
            'is_public': true,
            'created_at': '2026-08-02T12:00:00Z',
          },
        ],
      });

      expect(question.product, isNull);
      expect(question.productId, 'removed-product-1');
      expect(question.questionText, '¿Qué incluye el equipo?');
      expect(question.answerText, 'Incluye todos sus cables.');
      expect(question.answers, hasLength(1));
    });
  });
}
