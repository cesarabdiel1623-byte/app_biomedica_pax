import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'Physical Checkout TTL, Post-Payment Finalization, Outbox Consumer and App Return Contracts',
    () {
      final migration = File(
        'supabase/migrations/20260821120000_fix_physical_checkout_ttl_and_post_payment_finalization.sql',
      ).readAsStringSync();
      final createMpPreference = File(
        'supabase/functions/create-mp-test-preference/index.ts',
      ).readAsStringSync();
      final fulfillment = File(
        'supabase/functions/process-paid-order-fulfillment/index.ts',
      ).readAsStringSync();
      final outboxWorker = File(
        'supabase/functions/process-order-fulfillment-jobs/index.ts',
      ).readAsStringSync();
      final mpWebhook = File(
        'supabase/functions/mercado-pago-webhook/index.ts',
      ).readAsStringSync();
      final verifyPayment = File(
        'supabase/functions/verify-mp-order-payment/index.ts',
      ).readAsStringSync();
      final iosInfoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final androidManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      test(
        '1. Self-contained preference columns guarantee in order_payments',
        () {
          expect(migration, contains('ALTER TABLE public.order_payments'));
          expect(
            migration,
            contains('ADD COLUMN IF NOT EXISTS preference_id TEXT'),
          );
          expect(
            migration,
            contains('ADD COLUMN IF NOT EXISTS checkout_url TEXT'),
          );
          expect(
            migration,
            contains(
              'ADD COLUMN IF NOT EXISTS preference_expires_at TIMESTAMPTZ',
            ),
          );
        },
      );

      test(
        '2. Zero mock fallback: MP API failure fails closed without synthetic preference',
        () {
          expect(createMpPreference, isNot(contains('TEST-PREF-')));
          expect(createMpPreference, isNot(contains('TEST-MOCK-TOKEN')));
          expect(createMpPreference, contains('mercado_pago_token_missing'));
          expect(
            createMpPreference,
            contains('mercado_pago_preference_failed'),
          );
          expect(createMpPreference, contains('mercado_pago_network_error'));
        },
      );

      test('3. Preference persistence is fail-closed in order_payments', () {
        expect(createMpPreference, contains('.from("order_payments")'));
        expect(createMpPreference, contains('preference_id: preferenceId'));
        expect(createMpPreference, contains('checkout_url: checkoutUrl'));
        expect(
          createMpPreference,
          contains('preference_expires_at: preferenceExpiresAt'),
        );
        expect(createMpPreference, contains('preference_persistence_failed'));
      });

      test(
        '4. pending order <= 60 min is reused only when cart and pricing match',
        () {
          expect(
            migration,
            contains(
              "v_existing_order.created_at >= now() - interval '60 minutes'",
            ),
          );
          expect(migration, contains("v_reused := true;"));
          expect(migration, contains("v_mismatch"));
        },
      );

      test(
        '5. pending order > 60 min is canceled and superseded, generating new order',
        () {
          expect(
            migration,
            contains(
              "v_existing_order.created_at >= now() - interval '60 minutes'",
            ),
          );
          expect(
            migration,
            contains("status_detail = 'superseded_by_ttl_expiry'"),
          );
          expect(migration, contains("status = 'canceled'"));
          expect(
            migration,
            contains("status = 'cancelled'::public.payment_record_status"),
          );
          expect(
            migration,
            contains("v_order_number := 'ORD-' || to_char(now(), 'YYYYMMDD')"),
          );
        },
      );

      test(
        '6. Payment approved with available stock deducts inventory and enqueues fulfillment with idempotent upsert',
        () {
          expect(
            migration,
            contains(
              "v_post_payment_result := public.apply_paid_order_post_payment(v_order.id);",
            ),
          );
          expect(
            migration,
            contains(
              "v_stock_success := coalesce((v_post_payment_result->>'success')::boolean, false);",
            ),
          );
          expect(migration, contains("IF v_stock_success THEN"));
          expect(
            migration,
            contains(
              "INSERT INTO public.order_fulfillment_jobs (order_id, status, next_attempt_at)",
            ),
          );
          expect(migration, contains("ON CONFLICT (order_id) DO UPDATE"));
          expect(
            migration,
            contains(
              "WHERE public.order_fulfillment_jobs.status NOT IN ('completed', 'processing');",
            ),
          );
          expect(migration, contains("stock_status = 'deducted'"));
        },
      );

      test(
        '7. Payment approved with insufficient stock preserves payment approval and flags review without enqueuing shipment',
        () {
          expect(migration, contains("supply_status = 'pending_review'"));
          expect(
            migration,
            contains("stock_status = 'stock_deduction_failed'"),
          );
          expect(
            migration,
            contains(
              "status_detail = left(concat_ws(' | ', status_detail, 'stock_finalization_failed'), 200)",
            ),
          );
          expect(migration, contains("status = 'converted_to_order'"));
        },
      );

      test(
        '8. Double finalization / reconcile retry is idempotent with no double deduction and does not revive completed jobs',
        () {
          expect(migration, contains("v_stock_already_deducted := true;"));
          expect(migration, contains("v_duplicate_approved"));
          expect(
            migration,
            contains(
              "WHERE public.order_fulfillment_jobs.status NOT IN ('completed', 'processing');",
            ),
          );
        },
      );

      test(
        '9. Single authoritative fulfillment path: Webhook and Verify do not call fulfillment directly',
        () {
          final webhookContent = File(
            'supabase/functions/mercado-pago-webhook/index.ts',
          ).readAsStringSync();
          final verifyContent = File(
            'supabase/functions/verify-mp-order-payment/index.ts',
          ).readAsStringSync();
          expect(
            webhookContent,
            isNot(contains('triggerPaidOrderFulfillment')),
          );
          expect(verifyContent, isNot(contains('triggerPaidOrderFulfillment')));
        },
      );

      test(
        '10. Outbox claim RPC uses FOR UPDATE SKIP LOCKED to prevent race conditions',
        () {
          expect(
            migration,
            contains(
              "CREATE OR REPLACE FUNCTION public.claim_next_fulfillment_job()",
            ),
          );
          expect(migration, contains("FOR UPDATE SKIP LOCKED;"));
          expect(migration, contains("attempts = attempts + 1"));
          expect(migration, contains("status = 'processing'"));
        },
      );

      test(
        '11. Outbox failure updates attempts, exponential backoff and terminal state',
        () {
          expect(
            migration,
            contains("CREATE OR REPLACE FUNCTION public.fail_fulfillment_job"),
          );
          expect(
            migration,
            contains(
              "attempts >= max_attempts THEN now() + interval '100 years'",
            ),
          );
          expect(
            migration,
            contains(
              "now() + (greatest(coalesce(p_backoff_minutes, 5), 1) || ' minutes')::interval",
            ),
          );
        },
      );

      test(
        '12. Outbox worker consumer processes claimed jobs and marks completion or failure with full auth headers',
        () {
          expect(outboxWorker, contains("claim_next_fulfillment_job"));
          expect(outboxWorker, contains("complete_fulfillment_job"));
          expect(outboxWorker, contains("fail_fulfillment_job"));
          expect(outboxWorker, contains("jwtRole !== \"service_role\""));
          expect(
            outboxWorker,
            contains(r'"Authorization": `Bearer ${authToken}`'),
          );
          expect(outboxWorker, contains('"apikey": authToken'));
          expect(outboxWorker, isNot(contains("internal_fulfillment_secret")));
          expect(fulfillment, contains('jwtRole !== "service_role"'));
        },
      );

      test('13. Service-only check runs BEFORE physical guards', () {
        final serviceIndex = fulfillment.indexOf(
          'isServiceQuote === true && !hasPhysicalItems && !hasShippingRate',
        );
        final stockGuardIndex = fulfillment.indexOf(
          'stockStatus !== "deducted"',
        );
        expect(serviceIndex, isNonNegative);
        expect(stockGuardIndex, isNonNegative);
        expect(serviceIndex, lessThan(stockGuardIndex));
      });

      test(
        '14. Physical order authoritative guard requires positive stock_status === "deducted"',
        () {
          expect(
            fulfillment,
            contains('const stockStatus = getString(order, "stock_status");'),
          );
          expect(fulfillment, contains('if (stockStatus !== "deducted")'));
          expect(fulfillment, contains('error: "inventory_not_finalized"'));
          expect(
            fulfillment,
            isNot(contains('supplyStatus === "pending_review"')),
          );
        },
      );

      test(
        '15. Scheduler definition in migration is fail-closed, uses Vault, no localhost or internal secret fallback',
        () {
          expect(migration, contains("CREATE EXTENSION IF NOT EXISTS pg_net;"));
          expect(
            migration,
            contains("CREATE EXTENSION IF NOT EXISTS pg_cron;"),
          );
          expect(migration, contains("PERFORM cron.schedule("));
          expect(migration, contains("'process-order-fulfillment-jobs'"));
          expect(migration, contains("'* * * * *'"));
          expect(migration, contains("DEPLOY_PRECONDITION_MISSING"));
          expect(
            migration,
            contains("Vault secret \"edge_function_base_url\" is required"),
          );
          expect(
            migration,
            contains("Vault secret \"service_role_key\" is required"),
          );
          expect(migration, isNot(contains("localhost:54321")));
          expect(migration, isNot(contains("internal_fulfillment_secret")));
        },
      );

      test('16. Cart finalization preserves cart_items without deletion', () {
        expect(migration, contains("status = 'converted_to_order'"));
        expect(migration, contains("converted_order_id = v_order.id"));
        expect(migration, isNot(contains("DELETE FROM public.cart_items")));
      });

      test(
        '17. Mercado Pago preference configures canonical app return URLs and auto_return',
        () {
          expect(
            createMpPreference,
            contains('success: "gomedical://payment/success"'),
          );
          expect(
            createMpPreference,
            contains('pending: "gomedical://payment/pending"'),
          );
          expect(
            createMpPreference,
            contains('failure: "gomedical://payment/failure"'),
          );
          expect(createMpPreference, contains('auto_return: "approved"'));
        },
      );

      test('18. Android and iOS deep link URL schemes are configured', () {
        expect(androidManifest, contains('android:scheme="gomedical"'));
        expect(androidManifest, contains('android:host="payment"'));
        expect(iosInfoPlist, contains('<key>CFBundleURLTypes</key>'));
        expect(iosInfoPlist, contains('<string>gomedical</string>'));
      });
    },
  );
}
