import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/services/coupon_service.dart';
import 'package:gomedical_app/services/product_service.dart';

void main() {
  group('T3A.3 — Coupon Eligible Products & Security Definer RPC Contracts', () {
    const validUuid1 = 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d';
    const validUuid2 = 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e';
    const validUuid3 = 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f';

    group('1. CouponEligibleProductsResult Strict JSON & UUID Parsing (A - K)', () {
      test('A. Valid full JSON object contract parses correctly', () {
        final json = {
          'product_ids': [validUuid1, validUuid2],
          'total_count': 12,
          'is_full_catalog': false,
        };

        final result = CouponEligibleProductsResult.fromRpc(json);
        expect(result.productIds, [validUuid1, validUuid2]);
        expect(result.totalCount, 12);
        expect(result.isFullCatalog, isFalse);
      });

      test('A. Valid empty result contract parses correctly', () {
        final json = {
          'product_ids': [],
          'total_count': 0,
          'is_full_catalog': false,
        };

        final result = CouponEligibleProductsResult.fromRpc(json);
        expect(result.productIds, isEmpty);
        expect(result.totalCount, 0);
        expect(result.isFullCatalog, isFalse);
      });

      test(
        'Canonicalizes uppercase UUID and trims whitespace in product_ids',
        () {
          final json = {
            'product_ids': ['  ${validUuid1.toUpperCase()}  '],
            'total_count': 1,
            'is_full_catalog': false,
          };

          final result = CouponEligibleProductsResult.fromRpc(json);
          expect(result.productIds, [validUuid1.toLowerCase()]);
          expect(result.totalCount, 1);
          expect(result.isFullCatalog, isFalse);
        },
      );

      test(
        'Preserves total_count and is_full_catalog when page is empty (offset past end)',
        () {
          final json = {
            'product_ids': [],
            'total_count': 17,
            'is_full_catalog': true,
          };

          final result = CouponEligibleProductsResult.fromRpc(json);
          expect(result.productIds, isEmpty);
          expect(result.totalCount, 17);
          expect(result.isFullCatalog, isTrue);
        },
      );

      test('B. null response throws FormatException', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc(null),
          throwsA(isA<FormatException>()),
        );
      });

      test(
        'C. Empty map {} throws FormatException (missing required keys)',
        () {
          expect(
            () => CouponEligibleProductsResult.fromRpc({}),
            throwsA(isA<FormatException>()),
          );
        },
      );

      test('D. Raw string response throws FormatException', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc('unexpected_string'),
          throwsA(isA<FormatException>()),
        );
      });

      test('E. Raw list [] response throws FormatException (not map)', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc([]),
          throwsA(isA<FormatException>()),
        );
      });

      test('F. Error map {"error": "..."} throws FormatException', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc({'error': 'server_error'}),
          throwsA(isA<FormatException>()),
        );
      });

      test('G. Missing product_ids throws FormatException', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc({
            'total_count': 5,
            'is_full_catalog': true,
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('H. Missing total_count throws FormatException', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc({
            'product_ids': [validUuid1],
            'is_full_catalog': false,
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('I. Missing is_full_catalog throws FormatException', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc({
            'product_ids': [validUuid1],
            'total_count': 1,
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('J. Negative total_count throws FormatException', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc({
            'product_ids': [],
            'total_count': -1,
            'is_full_catalog': false,
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test(
        'K. is_full_catalog of invalid type (non-bool) throws FormatException',
        () {
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [],
              'total_count': 0,
              'is_full_catalog': 'true', // string instead of bool
            }),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [],
              'total_count': 0,
              'is_full_catalog': 1, // int instead of bool
            }),
            throwsA(isA<FormatException>()),
          );
        },
      );

      test(
        'L. product_ids containing non-string elements throws FormatException',
        () {
          // Integer in product_ids
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [123],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );

          // Boolean true in product_ids
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [true],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );

          // Boolean false in product_ids
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [false],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );

          // Map in product_ids
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [{}],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );

          // List in product_ids
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [[]],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );

          // null in product_ids
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [null],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );
        },
      );

      test(
        'M. product_ids containing invalid UUID strings throws FormatException',
        () {
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': ['abc'],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );

          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': ['12345'],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );
        },
      );

      test('N. Mixed valid + invalid elements invalidates entire contract', () {
        expect(
          () => CouponEligibleProductsResult.fromRpc({
            'product_ids': [validUuid1, 123],
            'total_count': 2,
            'is_full_catalog': false,
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => CouponEligibleProductsResult.fromRpc({
            'product_ids': [validUuid1, 'invalid-uuid-string'],
            'total_count': 2,
            'is_full_catalog': false,
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test(
        'O. Consistency: total_count = 0 with elements or elements > total_count throws FormatException',
        () {
          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [validUuid1],
              'total_count': 0,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );

          expect(
            () => CouponEligibleProductsResult.fromRpc({
              'product_ids': [validUuid1, validUuid2],
              'total_count': 1,
              'is_full_catalog': false,
            }),
            throwsA(isA<FormatException>()),
          );
        },
      );
    });

    group(
      '2. ProductService UUID validation, Lowercase Canonicalization & Deduplication',
      () {
        test(
          'ProductService.isValidUuid validates 36-char canonical UUID format with case-insensitivity',
          () {
            expect(ProductService.isValidUuid(validUuid1), isTrue);
            expect(
              ProductService.isValidUuid(validUuid1.toUpperCase()),
              isTrue,
            );
            expect(ProductService.isValidUuid('  $validUuid2  '), isTrue);
            expect(
              ProductService.isValidUuid(
                '00000000-0000-0000-0000-000000000000',
              ),
              isTrue,
            );

            expect(ProductService.isValidUuid(''), isFalse);
            expect(ProductService.isValidUuid('   '), isFalse);
            expect(ProductService.isValidUuid('invalid-uuid'), isFalse);
            expect(
              ProductService.isValidUuid('a1b2c3d4e5f67a8b9c0d1e2f3a4b5c6d'),
              isFalse,
            ); // missing dashes
            expect(ProductService.isValidUuid('12345'), isFalse);
          },
        );

        test(
          'ProductService.getProductsByIds returns [] without network call when ids are empty or invalid',
          () async {
            final resEmpty = await ProductService.getProductsByIds([]);
            expect(resEmpty, isEmpty);

            final resWhitespace = await ProductService.getProductsByIds([
              '',
              '   ',
              '\t',
            ]);
            expect(resWhitespace, isEmpty);

            final resInvalid = await ProductService.getProductsByIds([
              'invalid-1',
              'not-a-uuid',
              'abc',
            ]);
            expect(resInvalid, isEmpty);
          },
        );

        test(
          'UUID canonicalization to lowercase and post-lowercase deduplication preserving first order',
          () {
            final rawList = [
              '  ${validUuid1.toUpperCase()}  ',
              validUuid2.toLowerCase(),
              validUuid1.toLowerCase(), // duplicate in lowercase
              'invalid-id',
              validUuid3.toUpperCase(),
              validUuid2.toUpperCase(), // duplicate in uppercase
            ];

            final cleanIds = <String>[];
            final seen = <String>{};

            for (final rawId in rawList) {
              final trimmed = rawId.trim();
              if (trimmed.isNotEmpty && ProductService.isValidUuid(trimmed)) {
                final canonicalId = trimmed.toLowerCase();
                if (seen.add(canonicalId)) {
                  cleanIds.add(canonicalId);
                }
              }
            }

            expect(cleanIds, [
              validUuid1.toLowerCase(),
              validUuid2.toLowerCase(),
              validUuid3.toLowerCase(),
            ]);
          },
        );
      },
    );

    group('3. Migration Contract & SQL Rules Verification (A - R)', () {
      late final String sql;

      setUpAll(() {
        final file = File(
          'supabase/migrations/20260828110000_t3a_coupon_eligible_products_rpc.sql',
        );
        expect(file.existsSync(), isTrue, reason: 'Migration file must exist');
        sql = file.readAsStringSync();
      });

      test(
        'A & B. Privacy: helper call uses explicit named parameters (p_coupon_id, p_client_id) and fail-closed handling',
        () {
          expect(sql, contains('public.coupon_is_available_to_client('));
          expect(sql, contains('p_coupon_id := p_coupon_id'));
          expect(sql, contains('p_client_id := v_client_id'));
          expect(sql, contains('v_is_available := false;'));
          expect(sql, contains('if v_is_available is distinct from true then'));

          // Permissive fallback must NOT be present
          expect(
            sql,
            isNot(contains("v_coupon.distribution_scope = 'all_clients'")),
          );
        },
      );

      test('C & D. Status check: explicit active check and NULL blocking', () {
        expect(
          sql,
          contains("v_coupon.status is null or v_coupon.status != 'active'"),
        );
      });

      test(
        'E & F. Channel check: explicit mobile / all check and NULL blocking',
        () {
          expect(
            sql,
            contains(
              "v_coupon.channel is null or v_coupon.channel not in ('mobile', 'all')",
            ),
          );
        },
      );

      test(
        'G, H, I, J. Application scope check: purchase and both allowed, service blocked',
        () {
          expect(
            sql,
            contains(
              "v_coupon.application_scope is null or v_coupon.application_scope not in ('purchase', 'both')",
            ),
          );
        },
      );

      test(
        'K & L. Validity dates check: expired and future coupons blocked',
        () {
          expect(
            sql,
            contains(
              'v_coupon.starts_at is not null and now() < v_coupon.starts_at',
            ),
          );
          expect(
            sql,
            contains(
              'v_coupon.ends_at is not null and now() > v_coupon.ends_at',
            ),
          );
        },
      );

      test(
        'Usage Limits: Global limit (usage_limit_total) check against coupon_redemptions',
        () {
          expect(
            sql,
            contains('if v_coupon.usage_limit_total is not null then'),
          );
          expect(sql, contains('from public.coupon_redemptions cr'));
          expect(sql, contains('where cr.coupon_id = p_coupon_id;'));
          expect(
            sql,
            contains('if v_global_uses >= v_coupon.usage_limit_total then'),
          );
        },
      );

      test(
        'Usage Limits: Per-client limit (usage_limit_per_client) check against client_id',
        () {
          expect(
            sql,
            contains('if v_coupon.usage_limit_per_client is not null then'),
          );
          expect(
            sql,
            contains(
              'where cr.coupon_id = p_coupon_id and cr.client_id = v_client_id;',
            ),
          );
          expect(
            sql,
            contains(
              'if v_client_uses >= v_coupon.usage_limit_per_client then',
            ),
          );
        },
      );

      test(
        'M & N. Contract response returns JSONB object with total_count and product_ids',
        () {
          expect(sql, contains('RETURNS jsonb'));
          expect(
            sql,
            contains("'product_ids', coalesce(v_product_ids, '[]'::jsonb)"),
          );
          expect(sql, contains("'total_count', v_total_count"));
          expect(sql, contains("'is_full_catalog', v_is_full_catalog"));
        },
      );

      test('O. Total count calculated before limit and offset', () {
        expect(
          sql,
          contains(
            'select count(*) into v_total_count from eligible_products;',
          ),
        );
        expect(sql, contains('limit v_limit'));
        expect(sql, contains('offset v_offset'));
      });

      test(
        'P & Q. is_full_catalog determined by catalog_scope = all and absence of exclusion rules',
        () {
          expect(sql, contains("v_coupon.catalog_scope = 'all'"));
          expect(sql, contains("rule_type = 'exclude'"));
        },
      );

      test('R. Exclude rule takes absolute precedence over Include', () {
        expect(sql, contains("rule_type = 'include'"));
        expect(sql, contains("rule_type = 'exclude'"));
      });

      test(
        'SQL Aggregate Order: jsonb_agg has explicit ORDER BY matching pagination',
        () {
          expect(
            sql,
            contains(
              'jsonb_agg(prod_id::text order by prod_name asc, prod_id asc)',
            ),
          );
        },
      );

      test('Security Definitive: search_path and Grants', () {
        expect(sql, contains('SECURITY DEFINER'));
        expect(sql, contains("SET search_path TO 'pg_catalog', 'public'"));
        expect(
          sql,
          contains(
            'REVOKE ALL ON FUNCTION public.get_coupon_eligible_product_ids(uuid, text, integer, integer) FROM PUBLIC, anon;',
          ),
        );
        expect(
          sql,
          contains(
            'GRANT EXECUTE ON FUNCTION public.get_coupon_eligible_product_ids(uuid, text, integer, integer) TO authenticated;',
          ),
        );
        expect(
          sql,
          contains(
            'GRANT EXECUTE ON FUNCTION public.get_coupon_eligible_product_ids(uuid, text, integer, integer) TO service_role;',
          ),
        );
      });
    });
  });
}
