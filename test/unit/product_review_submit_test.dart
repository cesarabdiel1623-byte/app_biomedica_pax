import 'dart:io';

import 'package:gomedical_app/services/review_service.dart';
import 'package:gomedical_app/services/ticket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product review submission', () {
    final reviewServiceSource = File(
      'lib/services/review_service.dart',
    ).readAsStringSync();
    final writeReviewSource = File(
      'lib/screens/product/write_review_screen.dart',
    ).readAsStringSync();
    final migrationSource = File(
      'supabase/migrations/20260816200000_fix_product_reviews_fk_and_security.sql',
    ).readAsStringSync();

    test('Flutter submits product reviews through the Cloud RPC signature', () {
      expect(
        reviewServiceSource,
        contains(".rpc(\n      'submit_product_review'"),
      );
      expect(reviewServiceSource, contains("'p_comment': comment"));
      expect(reviewServiceSource, contains("'p_product_id': productId"));
      expect(reviewServiceSource, contains("'p_rating': rating"));
      expect(
        reviewServiceSource,
        contains("'p_title': _titleForRating(rating)"),
      );
      expect(reviewServiceSource, contains("'p_images': sanitizedUrls"));
      expect(reviewServiceSource, isNot(contains('jsonEncode')));
      expect(
        reviewServiceSource,
        isNot(contains("from('product_reviews').insert")),
      );
    });

    test('editing a review keeps product_id available for the RPC upsert', () {
      expect(
        reviewServiceSource,
        contains('static Future<void> updateReview({'),
      );
      expect(reviewServiceSource, contains('required String productId,'));
      expect(writeReviewSource, contains('productId: widget.product.id,'));
    });

    test('migration defines and protects submit_product_review', () {
      expect(
        migrationSource,
        contains(
          'REVOKE EXECUTE ON FUNCTION public.submit_product_review(uuid, integer, text, text) FROM PUBLIC',
        ),
      );
      expect(
        migrationSource,
        contains(
          'GRANT EXECUTE ON FUNCTION public.submit_product_review(uuid, integer, text, text) TO authenticated',
        ),
      );
      expect(
        migrationSource,
        contains(
          'GRANT EXECUTE ON FUNCTION public.submit_product_review(uuid, integer, text, text) TO service_role',
        ),
      );
    });

    test('TicketService identifies video files by allowed extensions', () {
      expect(TicketService.isVideoFile('video.mp4'), isTrue);
      expect(TicketService.isVideoFile('clip.MOV'), isTrue);
      expect(TicketService.isVideoFile('demo.webm'), isTrue);
      expect(TicketService.isVideoFile('screen.m4v'), isTrue);
      expect(TicketService.isVideoFile('photo.jpg'), isFalse);
      expect(TicketService.isVideoFile('image.png'), isFalse);
    });

    test('ProductReview parses images and videos properly from JSON', () {
      final review = ProductReview.fromJson({
        'id': '73b91d0a-fae9-4905-b23d-90cfd23b6fbf',
        'product_id': '8daf1dc5-8ee0-4cdb-9952-3a12c06af412',
        'client_id': '4996994f-5ee0-4ad9-872f-f210768bd14f',
        'rating': 4,
        'comment': 'Buen producto',
        'images': [
          'https://hdxrlmknrkkagsfzncnb.supabase.co/storage/v1/object/public/review-assets/1786992316233_7029.jpg',
          'https://hdxrlmknrkkagsfzncnb.supabase.co/storage/v1/object/public/review-assets/1786992326898_3096.mp4',
        ],
        'status': 'published',
        'created_at': '2026-08-17T18:46:46.630Z',
      });

      expect(review.images.length, equals(1));
      expect(review.videos.length, equals(1));
      expect(review.images.first, contains('.jpg'));
      expect(review.videos.first, contains('.mp4'));
    });

    test('write_review_screen limits text to 100 chars and uses onChanged handler', () {
      expect(writeReviewSource, contains('maxLength: 100'));
      expect(writeReviewSource, contains('onChanged: (_)'));
    });

    test('reviews_screen includes Mercado Libre card presentation with price and actions', () {
      final reviewsScreenSource = File('lib/screens/quotes/reviews_screen.dart').readAsStringSync();
      expect(reviewsScreenSource, contains('product.formattedPrice'));
      expect(reviewsScreenSource, contains('PopupMenuButton'));
      expect(reviewsScreenSource, contains('Eliminar opinión'));
      expect(reviewsScreenSource, contains('Editar opinión'));
    });
  });
}
