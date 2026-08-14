import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('T2.10 paid order fulfillment contracts', () {
    final migration = File(
      'supabase/migrations/20260813180000_t2_10_paid_order_fulfillment.sql',
    ).readAsStringSync();
    final inventoryLockFixMigration = File(
      'supabase/migrations/20260813190000_t2_10_1_fix_paid_order_inventory_lock.sql',
    ).readAsStringSync();
    final packageTypeMigration = File(
      'supabase/migrations/20260813200000_t2_11_7_product_logistics_package_type_code.sql',
    ).readAsStringSync();
    final fulfillment = File(
      'supabase/functions/process-paid-order-fulfillment/index.ts',
    ).readAsStringSync();
    final fulfillmentHelper = File(
      'supabase/functions/_shared/paid_order_fulfillment.ts',
    ).readAsStringSync();
    final webhook = File(
      'supabase/functions/skydropx-shipment-webhook/index.ts',
    ).readAsStringSync();
    final mpWebhook = File(
      'supabase/functions/mercado-pago-webhook/index.ts',
    ).readAsStringSync();
    final verifyPayment = File(
      'supabase/functions/verify-mp-order-payment/index.ts',
    ).readAsStringSync();

    test('order not approved is rejected before fulfillment', () {
      expect(migration, contains('order_not_approved'));
      expect(fulfillment, contains('order_not_approved'));
    });

    test('approved order deducts stock once with inventory movement', () {
      expect(migration, contains("stock_status = 'deducted'"));
      expect(migration, contains("movement_type,"));
      expect(migration, contains("'exit'::public.inventory_movement_type"));
      expect(migration, contains('-v_item.qty'));
      expect(migration, contains("'order'::public.reference_type"));
      expect(migration, contains('Salida automatica por orden pagada'));
    });

    test('stock failures do not partially deduct or change payment status', () {
      expect(migration, contains('insufficient_stock'));
      expect(migration, isNot(contains("payment_status = 'pending'")));
      expect(migration, isNot(contains("payment_status = 'pending_payment'")));
    });

    test('cart is converted idempotently to the paid order', () {
      expect(migration, contains("status = 'converted_to_order'"));
      expect(migration, contains('converted_order_id = v_order.id'));
      expect(migration, contains('cart_converted_to_different_order'));
    });

    test('shipment creation is idempotent and uses SkyDropX protections', () {
      expect(migration, contains('idx_order_shipments_skydropx_id_unique'));
      expect(fulfillment, contains('unique_shipment: true'));
      expect(fulfillment, contains('shipment_created: false'));
      expect(fulfillment, contains('shipment_reused: true'));
      expect(fulfillment, contains('order_shipments'));
      expect(fulfillment, contains('.not("skydropx_shipment_id", "is", null)'));
    });

    test('auto advance is enabled only for sandbox', () {
      expect(fulfillment, contains('environment === "sandbox"'));
      expect(fulfillment, contains('auto_advance: autoAdvance'));
    });

    test(
      'shipping origin comes from warehouses with sandbox-only fallback',
      () {
        expect(fulfillment, contains('.from("warehouses")'));
        expect(fulfillment, contains('.eq("is_active", true)'));
        expect(fulfillment, contains('.eq("is_shipping_origin", true)'));
        expect(fulfillment, contains('warehouses.length === 0'));
        expect(fulfillment, contains('environment === "sandbox"'));
        expect(fulfillment, contains('SKYDROPX_SANDBOX_ORIGIN_JSON'));
        expect(fulfillment, contains('skydropx_origin_not_configured'));
        expect(fulfillment, contains('multiple_shipping_origins'));
        expect(fulfillment, contains('invalid_shipping_origin'));
        expect(fulfillment, isNot(contains('97392')));
      },
    );

    test('warehouse fields are mapped to SkyDropX address_from', () {
      expect(fulfillment, contains('mapWarehouseToOrigin'));
      expect(
        fulfillment,
        contains('country_code: getString(warehouse, "country_code")'),
      );
      expect(
        fulfillment,
        contains('postal_code: getString(warehouse, "postal_code")'),
      );
      expect(
        fulfillment,
        contains('area_level1: getString(warehouse, "state")'),
      );
      expect(
        fulfillment,
        contains('area_level2: getString(warehouse, "city")'),
      );
      expect(
        fulfillment,
        contains('area_level3: getString(warehouse, "neighborhood")'),
      );
      expect(
        fulfillment,
        contains('name: getString(warehouse, "contact_name")'),
      );
      expect(fulfillment, contains('street1: getString(warehouse, "street1")'));
      expect(fulfillment, contains('company: getString(warehouse, "company")'));
      expect(fulfillment, contains('phone: getString(warehouse, "phone")'));
      expect(fulfillment, contains('email: getString(warehouse, "email")'));
      expect(
        fulfillment,
        contains('reference: getString(warehouse, "reference")'),
      );
    });

    test('expired SkyDropX rate is refreshed before shipment creation', () {
      expect(fulfillment, contains('refreshShippingRateForShipment'));
      expect(fulfillment, contains('GET'));
      expect(fulfillment, contains('/api/v1/quotations/'));
      expect(fulfillment, contains('/api/v1/quotations'));
      expect(fulfillment, contains('await sleep(QUOTATION_POLL_INTERVAL_MS)'));
      expect(
        fulfillment,
        contains(
          'for (let attempt = 0; attempt < QUOTATION_MAX_POLL_ATTEMPTS; attempt++)',
        ),
      );
      expect(fulfillment, contains('rate_refreshed: true'));
    });

    test(
      'old rate metadata selects same carrier and service when available',
      () {
        expect(fulfillment, contains('old_rate_metadata_found: true'));
        expect(
          fulfillment,
          contains('selection_reason: "same_carrier_service"'),
        );
        expect(
          fulfillment,
          contains('normalizeForRateMatch(rate.carrier) === oldCarrier'),
        );
        expect(
          fulfillment,
          contains('normalizeForRateMatch(rate.service) === oldService'),
        );
      },
    );

    test(
      'legacy free shipping falls back to cheapest valid refreshed rate',
      () {
        expect(
          fulfillment,
          contains('Math.round(params.customerShippingAmount * 100) === 0'),
        );
        expect(fulfillment, contains('rate: validRates[0]'));
        expect(
          fulfillment,
          contains('selection_reason: "free_shipping_cheapest"'),
        );
      },
    );

    test(
      'paid premium shipping without old rate metadata requires manual selection',
      () {
        expect(
          fulfillment,
          contains('shipping_rate_refresh_requires_manual_selection'),
        );
        expect(
          fulfillment,
          contains(
            'errorName === "shipping_rate_refresh_requires_manual_selection"',
          ),
        );
      },
    );

    test('refreshed rates are filtered using mobile quote safety rules', () {
      expect(fulfillment, contains('extractValidRates'));
      expect(fulfillment, contains('status === "no_coverage"'));
      expect(fulfillment, contains('status === "not_applicable"'));
      expect(fulfillment, contains('total <= 0'));
      expect(fulfillment, contains('currency !== "MXN"'));
      expect(fulfillment, contains('no_valid_shipping_rates'));
    });

    test('package_type_code migration adds nullable catalog code only', () {
      expect(
        packageTypeMigration,
        contains(
          'ALTER TABLE public.product_logistics_data\nADD COLUMN IF NOT EXISTS package_type_code text',
        ),
      );
      expect(
        packageTypeMigration,
        contains(
          'COMMENT ON COLUMN public.product_logistics_data.package_type_code',
        ),
      );
      expect(packageTypeMigration, isNot(contains("DEFAULT '4G'")));
      expect(
        packageTypeMigration,
        isNot(contains('package_type_code text NOT NULL')),
      );
    });

    test('package_type_code migration backfills only validated REFA1114', () {
      expect(packageTypeMigration, contains("SET package_type_code = '4G'"));
      expect(
        packageTypeMigration,
        contains("'8daf1dc5-8ee0-4cdb-9952-3a12c06af412'::uuid"),
      );
      expect(
        packageTypeMigration,
        contains("AND packaging_type = 'Caja reforzada mediana'"),
      );
      expect(packageTypeMigration, contains('AND package_type_code IS NULL'));
      expect(
        RegExp(
          r"SET\s+package_type_code\s*=\s*'4G'",
        ).allMatches(packageTypeMigration).length,
        1,
      );
    });

    test('shipping units read logistics and fiscal metadata per product', () {
      expect(fulfillment, contains('type ShippingUnit'));
      expect(fulfillment, contains('async function buildShippingUnits'));
      expect(fulfillment, contains('.from("order_items")'));
      expect(fulfillment, contains('.from("product_logistics_data")'));
      expect(
        fulfillment,
        contains(
          '.select("package_length, package_width, package_height, package_weight, package_type_code")',
        ),
      );
      expect(fulfillment, contains('.from("product_fiscal_data")'));
      expect(fulfillment, contains('.select("sat_product_service_code")'));
      expect(fulfillment, isNot(contains('sat_unit_code')));
    });

    test('shipping units reject missing package type and consignment note', () {
      expect(
        fulfillment,
        contains(
          'const packageTypeCode = getString(logistics, "package_type_code")',
        ),
      );
      expect(
        fulfillment,
        contains(
          'const consignmentNote = getString(fiscal, "sat_product_service_code")',
        ),
      );
      expect(
        fulfillment,
        contains('throw new Error("missing_package_type_code")'),
      );
      expect(
        fulfillment,
        contains('throw new Error("missing_consignment_note")'),
      );
      expect(
        fulfillment,
        contains(
          'error instanceof Error ? error.message : "invalid_order_parcels"',
        ),
      );
    });

    test('shipping units preserve quantity and product metadata per unit', () {
      expect(
        fulfillment,
        contains(
          'const quantity = Math.max(1, Math.trunc(getNumber(item, "quantity") ?? 1))',
        ),
      );
      expect(fulfillment, contains('for (let i = 0; i < quantity; i++)'));
      expect(fulfillment, contains('shippingUnits.push({'));
      expect(
        fulfillment,
        contains('parcel: { length, width, height, weight }'),
      );
      expect(fulfillment, contains('packageTypeCode,'));
      expect(fulfillment, contains('consignmentNote,'));
      expect(fulfillment, contains('.eq("product_id", productId)'));
    });

    test('requotation polling uses extended bounded attempts', () {
      expect(fulfillment, contains('const QUOTATION_POLL_INTERVAL_MS = 3000'));
      expect(fulfillment, contains('const QUOTATION_MAX_POLL_ATTEMPTS = 20'));
      expect(fulfillment, isNot(contains('attempt < 5')));
      expect(fulfillment, isNot(contains('sleep(2000)')));
      expect(fulfillment, isNot(contains('while (')));
      expect(fulfillment, isNot(contains('for (;;)')));
      expect(fulfillment, contains('attempt < QUOTATION_MAX_POLL_ATTEMPTS'));
      expect(fulfillment, contains('await sleep(QUOTATION_POLL_INTERVAL_MS)'));
    });

    test('requotation keeps polling while quotation is incomplete', () {
      final createFreshStart = fulfillment.indexOf(
        'async function createFreshQuotation',
      );
      expect(createFreshStart, isNonNegative);
      final createFreshEnd = fulfillment.indexOf(
        'async function refreshShippingRateForShipment',
        createFreshStart,
      );
      expect(createFreshEnd, isNonNegative);
      final createFreshQuotation = fulfillment.substring(
        createFreshStart,
        createFreshEnd,
      );

      expect(
        createFreshQuotation,
        contains('if (pollQuotation.is_completed !== true)'),
      );
      expect(createFreshQuotation, contains('continue;'));
    });

    test('requotation returns completed quotation only with valid rates', () {
      final createFreshStart = fulfillment.indexOf(
        'async function createFreshQuotation',
      );
      expect(createFreshStart, isNonNegative);
      final createFreshEnd = fulfillment.indexOf(
        'async function refreshShippingRateForShipment',
        createFreshStart,
      );
      expect(createFreshEnd, isNonNegative);
      final createFreshQuotation = fulfillment.substring(
        createFreshStart,
        createFreshEnd,
      );

      expect(
        createFreshQuotation,
        contains('if (createdQuotation.is_completed === true)'),
      );
      expect(
        createFreshQuotation,
        contains('extractValidRates(createdQuotation).length === 0'),
      );
      expect(
        createFreshQuotation,
        contains('throw new Error("no_valid_shipping_rates")'),
      );
      expect(
        createFreshQuotation,
        contains('extractValidRates(pollQuotation).length === 0'),
      );
      expect(createFreshQuotation, contains('return pollQuotation;'));
    });

    test('requotation timeout is only after bounded attempts are exhausted', () {
      final createFreshStart = fulfillment.indexOf(
        'async function createFreshQuotation',
      );
      expect(createFreshStart, isNonNegative);
      final createFreshEnd = fulfillment.indexOf(
        'async function refreshShippingRateForShipment',
        createFreshStart,
      );
      expect(createFreshEnd, isNonNegative);
      final createFreshQuotation = fulfillment.substring(
        createFreshStart,
        createFreshEnd,
      );

      expect(
        createFreshQuotation,
        contains(
          'for (let attempt = 0; attempt < QUOTATION_MAX_POLL_ATTEMPTS; attempt++)',
        ),
      );
      expect(
        createFreshQuotation.trimRight(),
        endsWith('throw new Error("skydropx_requotation_timeout");\n}'),
      );
    });

    test('address_to is completed from order snapshot and clients table', () {
      expect(fulfillment, contains('.from("clients")'));
      expect(fulfillment, contains('.select("email, business_name")'));
      expect(
        fulfillment,
        contains('const recipientEmail = getString(client, "email")'),
      );
      expect(
        fulfillment,
        contains('const businessName = getString(client, "business_name")'),
      );
      expect(fulfillment, contains('company: businessName ?? receiverName'));
      expect(fulfillment, contains('email: recipientEmail'));
      expect(fulfillment, contains('invalid_recipient_shipping_data'));
    });

    test('address_to street1 includes interior when present', () {
      expect(
        fulfillment,
        contains(
          'const interior = readTaggedValue(snapshot, ["interior", "numero interior", "número interior"])',
        ),
      );
      expect(
        fulfillment,
        contains(
          r'const street1 = interior ? `${street}, Interior ${interior}` : street',
        ),
      );
      expect(fulfillment, contains('street1,'));
    });

    test('quotation uses parcels but shipment uses packages', () {
      expect(fulfillment, contains('function buildParcels'));
      expect(fulfillment, contains('function buildShipmentPackages'));
      expect(fulfillment, contains('parcels,'));
      expect(fulfillment, contains('function buildQuotationAddress'));
      expect(
        fulfillment,
        contains('quotationAddressFrom = buildQuotationAddress(addressFrom)'),
      );
      expect(
        fulfillment,
        contains('quotationAddressTo = buildQuotationAddress(addressTo)'),
      );

      final shipmentStart = fulfillment.indexOf('const shipmentPayload = {');
      expect(shipmentStart, isNonNegative);
      final shipmentEnd = fulfillment.indexOf('};', shipmentStart);
      expect(shipmentEnd, isNonNegative);
      final shipmentPayload = fulfillment.substring(shipmentStart, shipmentEnd);

      expect(shipmentPayload, contains('rate_id: refreshedRate.rate.rate_id'));
      expect(shipmentPayload, contains('address_from: shipmentAddressFrom'));
      expect(shipmentPayload, contains('address_to: shipmentAddressTo'));
      expect(shipmentPayload, contains('packages,'));
      expect(shipmentPayload, contains('unique_shipment: true'));
      expect(shipmentPayload, contains('auto_advance: autoAdvance'));
      expect(shipmentPayload, isNot(contains('parcels')));
      expect(shipmentPayload, isNot(contains('quotation_id')));
      expect(shipmentPayload, isNot(contains('carrier_name')));
      expect(shipmentPayload, isNot(contains('declared_value')));
      expect(shipmentPayload, isNot(contains('products')));
      expect(shipmentPayload, isNot(contains('sat_unit_code')));
      expect(shipmentPayload, isNot(contains('sat_product_service_code')));
    });

    test('quotation addresses are sanitized to geographic fields only', () {
      final quotationHelperStart = fulfillment.indexOf(
        'function buildQuotationAddress',
      );
      expect(quotationHelperStart, isNonNegative);
      final quotationHelperEnd = fulfillment.indexOf(
        'const SKYDROPX_SHIPMENT_REFERENCE_MAX_CHARS',
        quotationHelperStart,
      );
      expect(quotationHelperEnd, isNonNegative);
      final quotationHelper = fulfillment.substring(
        quotationHelperStart,
        quotationHelperEnd,
      );

      expect(quotationHelper, contains('"country_code"'));
      expect(quotationHelper, contains('"postal_code"'));
      expect(quotationHelper, contains('"area_level1"'));
      expect(quotationHelper, contains('"area_level2"'));
      expect(quotationHelper, contains('"area_level3"'));
      expect(quotationHelper, isNot(contains('"name"')));
      expect(quotationHelper, isNot(contains('"street1"')));
      expect(quotationHelper, isNot(contains('"company"')));
      expect(quotationHelper, isNot(contains('"phone"')));
      expect(quotationHelper, isNot(contains('"email"')));
      expect(quotationHelper, isNot(contains('"reference"')));
      expect(quotationHelper, contains('invalid_quotation_address'));
    });

    test('create quotation sends sanitized addresses and parcels', () {
      final quotationStart = fulfillment.indexOf(
        'body: JSON.stringify({\n'
        '          quotation: {',
      );
      expect(quotationStart, isNonNegative);
      final quotationEnd = fulfillment.indexOf('}),', quotationStart);
      expect(quotationEnd, isNonNegative);
      final quotationPayload = fulfillment.substring(
        quotationStart,
        quotationEnd,
      );

      expect(quotationPayload, contains('address_from: quotationAddressFrom'));
      expect(quotationPayload, contains('address_to: quotationAddressTo'));
      expect(quotationPayload, contains('parcels,'));
      expect(quotationPayload, isNot(contains('address_from: addressFrom')));
      expect(quotationPayload, isNot(contains('address_to: addressTo')));
      expect(quotationPayload, isNot(contains('packages')));
    });

    test('shipment limits only reference on copied full address objects', () {
      final shipmentStart = fulfillment.indexOf('const shipmentPayload = {');
      expect(shipmentStart, isNonNegative);
      final shipmentEnd = fulfillment.indexOf('};', shipmentStart);
      expect(shipmentEnd, isNonNegative);
      final shipmentPayload = fulfillment.substring(shipmentStart, shipmentEnd);

      expect(shipmentPayload, contains('address_from: shipmentAddressFrom'));
      expect(shipmentPayload, contains('address_to: shipmentAddressTo'));
      expect(shipmentPayload, contains('packages,'));
      expect(shipmentPayload, isNot(contains('quotationAddressFrom')));
      expect(shipmentPayload, isNot(contains('quotationAddressTo')));
      expect(shipmentPayload, isNot(contains('parcels')));
    });

    test(
      'shipment reference helper trims and preserves values up to 30 chars',
      () {
        final helperStart = fulfillment.indexOf(
          'const SKYDROPX_SHIPMENT_REFERENCE_MAX_CHARS = 30',
        );
        expect(helperStart, isNonNegative);
        final helperEnd = fulfillment.indexOf(
          'function readTaggedValue',
          helperStart,
        );
        expect(helperEnd, isNonNegative);
        final helper = fulfillment.substring(helperStart, helperEnd);

        expect(helper, contains('const characters = Array.from(value.trim())'));
        expect(helper, contains('characters.length <= maxLength'));
        expect(helper, contains('? characters.join("")'));
        expect(helper, contains('characters.length === 0'));
      },
    );

    test('shipment reference helper truncates by Unicode characters', () {
      expect(
        fulfillment,
        contains('const SKYDROPX_SHIPMENT_REFERENCE_MAX_CHARS = 30'),
      );
      expect(fulfillment, contains('Array.from(value.trim())'));
      expect(fulfillment, contains('characters.slice(0, maxLength).join("")'));
    });

    test('shipment addresses are copies and original references stay intact', () {
      expect(
        fulfillment,
        contains(
          'const shipmentAddressFrom = buildShipmentAddress(originResult.origin)',
        ),
      );
      expect(
        fulfillment,
        contains('const shipmentAddressTo = buildShipmentAddress(addressTo)'),
      );
      expect(fulfillment, contains('return {\n    ...address,'));
      expect(
        fulfillment,
        contains('addressFrom: originResult.origin,\n      addressTo,'),
      );
      expect(fulfillment, isNot(contains('originResult.origin.reference =')));
      expect(fulfillment, isNot(contains('addressTo.reference =')));
    });

    test('shipment address adaptation changes reference only', () {
      final helperStart = fulfillment.indexOf('function buildShipmentAddress');
      final helperEnd = fulfillment.indexOf(
        'function readTaggedValue',
        helperStart,
      );
      final helper = fulfillment.substring(helperStart, helperEnd);

      expect(helper, contains('...address,'));
      expect(helper, contains('reference: truncateToMaxChars('));
      expect(helper, isNot(contains('street1:')));
      expect(helper, isNot(contains('name:')));
      expect(helper, isNot(contains('company:')));
      expect(helper, isNot(contains('phone:')));
      expect(helper, isNot(contains('email:')));
      expect(helper, isNot(contains('postal_code:')));
      expect(helper, isNot(contains('area_level1:')));
      expect(helper, isNot(contains('area_level2:')));
      expect(helper, isNot(contains('area_level3:')));
    });

    test(
      'quotation remains independent from shipment reference adaptation',
      () {
        final quotationStart = fulfillment.indexOf(
          'async function createFreshQuotation',
        );
        final quotationEnd = fulfillment.indexOf(
          'async function refreshShippingRateForShipment',
          quotationStart,
        );
        expect(quotationStart, isNonNegative);
        expect(quotationEnd, isNonNegative);
        final quotationFlow = fulfillment.substring(
          quotationStart,
          quotationEnd,
        );

        expect(quotationFlow, contains('buildQuotationAddress(addressFrom)'));
        expect(quotationFlow, contains('buildQuotationAddress(addressTo)'));
        expect(quotationFlow, isNot(contains('buildShipmentAddress')));
        expect(quotationFlow, isNot(contains('truncateToMaxChars')));
      },
    );

    test('shipment reference fix has no warehouse or client-specific value', () {
      expect(
        fulfillment,
        isNot(
          contains(
            'Address from reference es demasiado largo (30 caracteres máximo)',
          ),
        ),
      );
    });

    test('shipment packages include SkyDropX metadata from shipping units', () {
      expect(
        fulfillment,
        contains('return shippingUnits.map((unit, index) => ({'),
      );
      expect(fulfillment, contains('package_number: String(index + 1)'));
      expect(fulfillment, contains('package_protected: false'));
      expect(fulfillment, contains('package_type: unit.packageTypeCode'));
      expect(fulfillment, contains('consignment_note: unit.consignmentNote'));
      expect(fulfillment, isNot(contains('declared_value:')));
      expect(fulfillment, isNot(contains('products:')));
    });

    test('shipment response parser accepts flat and JSON API payloads', () {
      expect(fulfillment, contains('function sanitizeShipment'));
      expect(fulfillment, contains('isRecord(data.shipment)'));
      expect(fulfillment, contains('isRecord(data.data)'));
      expect(
        fulfillment,
        contains('const attributes = isRecord(shipment.attributes)'),
      );
      expect(fulfillment, contains('getString(attributes, "tracking_number")'));
      expect(
        fulfillment,
        contains('getString(attributes, "tracking_url_provider")'),
      );
      expect(fulfillment, contains('getString(attributes, "label_url")'));
      expect(fulfillment, contains('getString(attributes, "status")'));
      expect(fulfillment, contains('??\n      "created"'));
    });

    test('rate refresh updates only logistic fields on the order', () {
      expect(
        fulfillment,
        contains('skydropx_quotation_id: refreshedRate.quotation_id'),
      );
      expect(
        fulfillment,
        contains('skydropx_rate_id: refreshedRate.rate.rate_id'),
      );
      expect(
        fulfillment,
        contains('skydropx_shipping_cost: refreshedRate.rate.total'),
      );
      expect(fulfillment, isNot(contains('orders.total')));
      expect(fulfillment, isNot(contains('order_payments')));
      expect(fulfillment, isNot(contains('payment_id:')));
      expect(fulfillment, isNot(contains('payment_status:')));
      expect(fulfillment, isNot(contains('customer_shipping_amount:')));
      expect(fulfillment, isNot(contains('shipping_discount_amount:')));
      expect(fulfillment, isNot(contains('coupon_discount_amount:')));
    });

    test(
      'Carta Porte data is read from DB without hardcoded provider values',
      () {
        expect(fulfillment, contains('skydropx_consignment_note_required'));
        expect(fulfillment, isNot(contains('Caja reforzada mediana')));
        expect(fulfillment, isNot(contains('package_type: "4G"')));
        expect(fulfillment, isNot(contains("package_type: '4G'")));
        expect(fulfillment, isNot(contains('?? "4G"')));
        expect(fulfillment, isNot(contains("?? '4G'")));
        expect(fulfillment, isNot(contains('26111700')));
      },
    );

    test(
      'shipment provider errors preserve only safe diagnostic text fields',
      () {
        final providerHelperStart = fulfillment.indexOf(
          'const PROVIDER_DETAIL_TEXT_FIELDS',
        );
        expect(providerHelperStart, isNonNegative);
        final providerHelperEnd = fulfillment.indexOf(
          'async function buildShippingUnits',
          providerHelperStart,
        );
        expect(providerHelperEnd, isNonNegative);
        final providerHelper = fulfillment.substring(
          providerHelperStart,
          providerHelperEnd,
        );

        expect(providerHelper, contains('"error"'));
        expect(providerHelper, contains('"error_description"'));
        expect(providerHelper, contains('"errors"'));
        expect(providerHelper, contains('"message"'));
        expect(providerHelper, contains('"detail"'));
        expect(providerHelper, contains('"details"'));
        expect(providerHelper, contains('"code"'));
        expect(providerHelper, contains('"error_detail"'));
        expect(providerHelper, contains('validation_errors'));
        expect(providerHelper, contains('sanitizeProviderDiagnostic'));
        expect(providerHelper, isNot(contains('shipmentPayload')));
        expect(providerHelper, isNot(contains('headers')));
      },
    );

    test('provider diagnostic captures errors strings and scalar codes', () {
      expect(fulfillment, contains('"errors",'));
      expect(
        fulfillment,
        contains(
          'typeof value !== "string" &&\n'
          '    typeof value !== "number" &&\n'
          '    typeof value !== "boolean"',
        ),
      );
      expect(fulfillment, contains('return sanitizeProviderDetailText(value)'));
    });

    test('provider diagnostic preserves nested errors objects safely', () {
      expect(fulfillment, contains('if (isRecord(value))'));
      expect(
        fulfillment,
        contains(
          'for (\n      const [key, entry] of Object.entries(value).slice(',
        ),
      );
      expect(
        fulfillment,
        contains('sanitizeProviderDiagnostic(entry, depth + 1)'),
      );
      expect(fulfillment, contains('sanitizedObject[key] = sanitized'));
    });

    test('provider diagnostic captures bounded errors arrays', () {
      expect(fulfillment, contains('if (Array.isArray(value))'));
      expect(
        fulfillment,
        contains('.slice(0, PROVIDER_DIAGNOSTIC_MAX_ARRAY_ITEMS)'),
      );
      expect(
        fulfillment,
        contains(
          '.map((entry) => sanitizeProviderDiagnostic(entry, depth + 1))',
        ),
      );
    });

    test('provider error and description extraction remain supported', () {
      expect(fulfillment, contains('"error",'));
      expect(fulfillment, contains('"error_description",'));
      expect(fulfillment, contains('isRecord(data.error) ? data.error : null'));
    });

    test('provider error detail extraction is supported safely', () {
      expect(fulfillment, contains('"error_detail",'));
      expect(
        fulfillment,
        contains('const sanitized = sanitizeProviderDiagnostic(source[field])'),
      );
    });

    test('provider shape contains top-level names and types only', () {
      final shapeStart = fulfillment.indexOf('function describeProviderShape');
      expect(shapeStart, isNonNegative);
      final shapeEnd = fulfillment.indexOf(
        'async function buildShippingUnits',
        shapeStart,
      );
      expect(shapeEnd, isNonNegative);
      final shapeHelper = fulfillment.substring(shapeStart, shapeEnd);

      expect(shapeHelper, contains('body_type: getProviderValueType(data)'));
      expect(shapeHelper, contains('providerShape.top_level_keys = safeKeys'));
      expect(
        shapeHelper,
        contains('topLevelTypes[key] = getProviderValueType(data[key])'),
      );
      expect(
        shapeHelper,
        contains('providerShape.top_level_types = topLevelTypes'),
      );
      expect(shapeHelper, isNot(contains('top_level_values')));
      expect(shapeHelper, isNot(contains('providerShape[key] = data[key]')));
    });

    test('provider shape is returned for rejected shipment responses', () {
      expect(
        fulfillment,
        contains('const providerShape = describeProviderShape(shipmentData)'),
      );
      expect(fulfillment, contains('provider_shape: providerShape'));
    });

    test('shipment provider diagnostics block sensitive keys and values', () {
      final providerHelperStart = fulfillment.indexOf(
        'const PROVIDER_DETAIL_TEXT_FIELDS',
      );
      expect(providerHelperStart, isNonNegative);
      final providerHelperEnd = fulfillment.indexOf(
        'async function buildShippingUnits',
        providerHelperStart,
      );
      expect(providerHelperEnd, isNonNegative);
      final providerHelper = fulfillment.substring(
        providerHelperStart,
        providerHelperEnd,
      );

      expect(providerHelper, contains('SENSITIVE_PROVIDER_DETAIL_PATTERN'));
      expect(providerHelper, contains('authorization'));
      expect(providerHelper, contains('token'));
      expect(providerHelper, contains('secret'));
      expect(providerHelper, contains('service[_-]?role'));
      expect(providerHelper, contains('api[_-]?key'));
      expect(providerHelper, contains('apikey'));
      expect(providerHelper, contains('password'));
      expect(providerHelper, contains('isBlockedProviderDetailKey(key)'));
      expect(
        providerHelper,
        contains('SENSITIVE_PROVIDER_DETAIL_PATTERN.test(text)'),
      );
    });

    test('shipment provider diagnostics block request PII keys', () {
      final providerHelperStart = fulfillment.indexOf(
        'const PROVIDER_DETAIL_TEXT_FIELDS',
      );
      final providerHelperEnd = fulfillment.indexOf(
        'async function buildShippingUnits',
        providerHelperStart,
      );
      final providerHelper = fulfillment.substring(
        providerHelperStart,
        providerHelperEnd,
      );

      expect(providerHelper, contains('PROVIDER_PII_KEY_PATTERN'));
      expect(providerHelper, contains('email'));
      expect(providerHelper, contains('phone'));
      expect(providerHelper, contains('street1'));
      expect(providerHelper, contains('name'));
      expect(providerHelper, contains('company'));
      expect(providerHelper, contains('reference'));
      expect(providerHelper, contains('PROVIDER_PII_KEY_PATTERN.test(key)'));
    });

    test('provider diagnostic recursion and collection sizes are bounded', () {
      expect(fulfillment, contains('const PROVIDER_DIAGNOSTIC_MAX_DEPTH = 4'));
      expect(
        fulfillment,
        contains('const PROVIDER_DIAGNOSTIC_MAX_ARRAY_ITEMS = 10'),
      );
      expect(
        fulfillment,
        contains('const PROVIDER_DIAGNOSTIC_MAX_OBJECT_FIELDS = 20'),
      );
      expect(
        fulfillment,
        contains('const PROVIDER_DIAGNOSTIC_MAX_STRING_LENGTH = 500'),
      );
      expect(
        fulfillment,
        contains('if (depth > PROVIDER_DIAGNOSTIC_MAX_DEPTH) return null'),
      );
    });

    test('shipment rejection returns sanitized provider details only', () {
      expect(
        fulfillment,
        contains(
          'const providerDetails = extractProviderErrorDetails(shipmentData)',
        ),
      );
      expect(fulfillment, contains('const providerDiagnostic = {'));
      expect(
        fulfillment,
        contains('...(Object.keys(providerDetails).length > 0'),
      );
      expect(fulfillment, contains('provider_details: providerDetails'));
      expect(fulfillment, contains('provider_shape: providerShape'));
      expect(
        fulfillment,
        contains(
          'error: shipmentResponse.status === 422\n          ? "skydropx_shipment_rejected"',
        ),
      );
      expect(fulfillment, contains('provider_status: shipmentResponse.status'));
      expect(fulfillment, isNot(contains('provider_details: shipmentData')));
      expect(fulfillment, isNot(contains('console.log(shipmentPayload')));
      expect(fulfillment, isNot(contains('console.error(shipmentPayload')));
    });

    test('consignment detector keeps specific error with provider details', () {
      expect(
        fulfillment,
        contains('providerErrorText.includes("consignment")'),
      );
      expect(
        fulfillment,
        contains('providerErrorText.includes("package_type")'),
      );
      expect(
        fulfillment,
        contains('providerErrorText.includes("carta porte")'),
      );
      expect(
        fulfillment,
        contains('error: "skydropx_consignment_note_required"'),
      );
      expect(fulfillment, contains('...providerDiagnostic'));
    });

    test('fulfillment edge function is backend-only', () {
      expect(fulfillment, contains('SUPABASE_SERVICE_ROLE_KEY'));
      expect(fulfillment, contains('unauthorized'));
      expect(fulfillmentHelper, contains('"edge_function"'));
      expect(fulfillmentHelper, contains('process-paid-order-fulfillment'));
    });

    test('shared fulfillment helper sends service role JWT bearer', () {
      expect(
        fulfillmentHelper,
        contains(
          'const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim()',
        ),
      );
      expect(
        fulfillmentHelper,
        contains(r'"Authorization": `Bearer ${serviceRoleKey}`'),
      );
      expect(fulfillmentHelper, isNot(contains('X-GoMedical-Internal-Secret')));
      expect(
        fulfillmentHelper,
        isNot(contains('PAID_ORDER_FULFILLMENT_INTERNAL_SECRET')),
      );
      expect(
        fulfillmentHelper,
        isNot(contains('paid_order_fulfillment_helper_diag')),
      );
    });

    test('fulfillment process authorizes only service_role JWT claims', () {
      expect(fulfillment, contains('function getBearerToken'));
      expect(fulfillment, contains('request.headers.get("Authorization")'));
      expect(fulfillment, contains('function getJwtRoleFromBearerToken'));
      expect(fulfillment, contains('decodeBase64UrlJson(parts[1])'));
      expect(
        fulfillment,
        contains('const jwtRole = getJwtRoleFromBearerToken(bearerToken)'),
      );
      expect(fulfillment, contains('jwtRole !== "service_role"'));
      expect(
        fulfillment,
        contains('return jsonResponse({ ok: false, error: "forbidden" }, 403)'),
      );
      expect(
        fulfillment,
        contains(
          'return jsonResponse({ ok: false, error: "unauthorized" }, 401)',
        ),
      );
    });

    test(
      'anon and authenticated JWT roles are forbidden by the service_role guard',
      () {
        expect(fulfillment, contains('return getString(payload, "role")'));
        expect(fulfillment, contains('jwtRole !== "service_role"'));
        expect(
          fulfillment,
          contains(
            'return jsonResponse({ ok: false, error: "forbidden" }, 403)',
          ),
        );
        expect(fulfillment, isNot(contains('jwtRole === "authenticated"')));
        expect(fulfillment, isNot(contains('jwtRole === "anon"')));
      },
    );

    test('fulfillment no longer uses custom internal secret auth', () {
      expect(
        fulfillment,
        isNot(contains('PAID_ORDER_FULFILLMENT_INTERNAL_SECRET')),
      );
      expect(fulfillment, isNot(contains('X-GoMedical-Internal-Secret')));
      expect(fulfillment, isNot(contains('x-gomedical-internal-secret')));
      expect(fulfillment, isNot(contains('timingSafeEqualStrings')));
      expect(
        fulfillment,
        isNot(contains('process_paid_order_fulfillment_auth_diag')),
      );
      expect(
        fulfillmentHelper,
        isNot(contains('paid_order_fulfillment_helper_diag')),
      );
      expect(
        fulfillment,
        isNot(contains(r'authHeader !== `Bearer ${serviceRoleKey}`')),
      );
    });

    test('service role remains private and only used for admin client', () {
      expect(
        fulfillment,
        contains(
          'const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY")',
        ),
      );
      expect(fulfillment, contains('createClient(supabaseUrl, serviceRoleKey'));
      expect(
        fulfillment,
        isNot(contains('SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? ""')),
      );
    });

    test('SkyDropX webhook verifies HMAC and maps statuses', () {
      expect(webhook, contains('SKYDROPX_SANDBOX_WEBHOOK_SECRET'));
      expect(webhook, contains('HMAC'));
      expect(webhook, contains('SHA-512'));
      expect(webhook, contains('startsWith("HMAC ")'));
      expect(webhook, contains('authorization.slice("HMAC ".length)'));
      expect(webhook, contains('invalid_signature'));
      expect(webhook, isNot(contains('hmac_diagnostic_v1')));
      expect(webhook, isNot(contains('replace(/^Bearer')));
      expect(webhook, contains('getNestedRecord(data, "data")'));
      expect(webhook, contains('getNestedRecord(resource, "attributes")'));
      expect(
        webhook,
        contains(
          'getNestedString(resource, ["relationships", "shipment", "data", "id"])',
        ),
      );
      expect(webhook, contains('tracking_url_provider'));
      expect(webhook, contains('missing_shipment_id'));
      expect(migration, contains("WHEN 'created' THEN 'label_created'"));
      expect(migration, contains("WHEN 'picked_up' THEN 'picked_up'"));
      expect(migration, contains("WHEN 'in_transit' THEN 'in_transit'"));
      expect(migration, contains("WHEN 'last_mile' THEN 'out_for_delivery'"));
      expect(migration, contains("WHEN 'delivered' THEN 'delivered'"));
      expect(migration, contains("public.sync_order_status_from_shipping"));
    });

    test('shipment events are deduplicated with a deterministic key', () {
      expect(migration, contains('idx_shipment_events_event_key_unique'));
      expect(migration, contains('md5('));
      expect(migration, contains('ON CONFLICT (shipment_id, event_key)'));
    });

    test(
      'customer shipment events view preserves the existing Cloud signature',
      () {
        final viewStart = migration.indexOf(
          'CREATE OR REPLACE VIEW public.customer_shipment_events',
        );
        expect(viewStart, isNonNegative);

        final viewEnd = migration.indexOf(
          'FROM public.shipment_events e;',
          viewStart,
        );
        expect(viewEnd, isNonNegative);

        final viewSql = migration.substring(viewStart, viewEnd);
        expect(
          viewSql,
          contains(
            'e.id,\n'
            '  e.shipment_id,\n'
            '  e.status,\n'
            '  e.description,\n'
            '  e.location,\n'
            '  e.event_at,\n'
            '  e.created_at',
          ),
        );
        expect(viewSql, isNot(contains('e.provider_status')));
        expect(viewSql, isNot(contains('e.event_key')));
      },
    );

    test('payment paths trigger fulfillment after approved reconciliation', () {
      expect(mpWebhook, contains('triggerPaidOrderFulfillment'));
      expect(verifyPayment, contains('triggerPaidOrderFulfillment'));
      expect(mpWebhook, contains('reconciledPaymentStatus === "approved"'));
      expect(verifyPayment, contains('reconciledPaymentStatus === "approved"'));
    });

    test(
      'Mercado Pago webhook accepts status or payment_status from reconciliation RPC',
      () {
        expect(mpWebhook, contains('function getReconciledPaymentStatus'));
        expect(
          mpWebhook,
          contains(
            'getString(result, "payment_status") ?? getString(result, "status")',
          ),
        );
        expect(
          mpWebhook,
          contains(
            'const reconciledPaymentStatus = getReconciledPaymentStatus(reconciliationResult)',
          ),
        );
        expect(mpWebhook, contains('reconciledPaymentStatus === "approved"'));
        expect(mpWebhook, contains('isUuidLike(reconciledOrderId)'));
      },
    );

    test(
      'approved idempotent reconciliation is allowed to trigger fulfillment',
      () {
        final triggerStart = mpWebhook.indexOf(
          'if (\n'
          '      reconciledOrderId &&',
        );
        expect(triggerStart, isNonNegative);
        final triggerEnd = mpWebhook.indexOf(
          'return jsonResponse({ received: true, reconciled: true });',
          triggerStart,
        );
        expect(triggerEnd, isNonNegative);
        final triggerBlock = mpWebhook.substring(triggerStart, triggerEnd);

        expect(
          triggerBlock,
          contains('reconciledPaymentStatus === "approved"'),
        );
        expect(triggerBlock, contains('triggerPaidOrderFulfillment'));
        expect(triggerBlock, isNot(contains('idempotent')));
        expect(triggerBlock, isNot(contains('duplicate_approved')));
      },
    );

    test('non-approved reconciliation statuses do not trigger fulfillment', () {
      expect(
        mpWebhook,
        isNot(contains('reconciledPaymentStatus !== "rejected"')),
      );
      expect(
        mpWebhook,
        isNot(contains('reconciledPaymentStatus !== "pending"')),
      );
      expect(mpWebhook, contains('reconciledPaymentStatus === "approved"'));
      expect(verifyPayment, contains('reconciledPaymentStatus === "approved"'));
    });

    test('verify payment uses the same reconciliation result contract', () {
      expect(verifyPayment, contains('function getReconciledPaymentStatus'));
      expect(
        verifyPayment,
        contains(
          'getString(result, "payment_status") ?? getString(result, "status")',
        ),
      );
      expect(
        verifyPayment,
        contains('const { data: reconciliationResult, error: rpcError }'),
      );
      expect(
        verifyPayment,
        contains(
          'const reconciledPaymentStatus = getReconciledPaymentStatus(reconciliationResult)',
        ),
      );
      expect(verifyPayment, contains('isUuidLike(reconciledOrderId)'));
    });

    test('Flutter clears local cart cache after payment return', () {
      final mainFile = File('lib/main.dart').readAsStringSync();
      final cartService = File(
        'lib/services/cart_service.dart',
      ).readAsStringSync();
      expect(cartService, contains('clearLocalCartCache'));
      expect(mainFile, contains('CartService.clearLocalCartCache'));
    });

    test(
      'T2.10.1 locks inventory rows without GROUP BY in FOR UPDATE query',
      () {
        expect(
          inventoryLockFixMigration,
          contains(
            'CREATE OR REPLACE FUNCTION public.apply_paid_order_post_payment',
          ),
        );

        final lockStart = inventoryLockFixMigration.indexOf(
          'PERFORM 1\n'
          '    FROM public.product_inventory pi\n'
          '    WHERE pi.product_id IN (',
        );
        expect(lockStart, isNonNegative);

        final lockEnd = inventoryLockFixMigration.indexOf(
          'FOR UPDATE;',
          lockStart,
        );
        expect(lockEnd, isNonNegative);

        final lockSql = inventoryLockFixMigration.substring(lockStart, lockEnd);
        expect(lockSql, contains('SELECT DISTINCT oi.product_id'));
        expect(lockSql, contains('ORDER BY pi.product_id'));
        expect(lockSql, isNot(contains('GROUP BY')));
        expect(lockSql, isNot(contains('sum(')));
      },
    );

    test('T2.10.1 still aggregates duplicate order_items per product', () {
      expect(
        inventoryLockFixMigration,
        contains('sum(greatest(coalesce(oi.quantity, 0), 0)) AS qty'),
      );
      expect(inventoryLockFixMigration, contains('GROUP BY oi.product_id'));
    });

    test('T2.10.1 validates all stock before any deduction', () {
      final validationIndex = inventoryLockFixMigration.indexOf(
        'INTO v_stock_errors',
      );
      final insufficientIndex = inventoryLockFixMigration.indexOf(
        'IF v_stock_errors IS NOT NULL THEN',
      );
      final loopIndex = inventoryLockFixMigration.indexOf('FOR v_item IN');
      final updateInventoryIndex = inventoryLockFixMigration.indexOf(
        'UPDATE public.product_inventory',
      );

      expect(validationIndex, isNonNegative);
      expect(insufficientIndex, greaterThan(validationIndex));
      expect(loopIndex, greaterThan(insufficientIndex));
      expect(updateInventoryIndex, greaterThan(loopIndex));
      expect(inventoryLockFixMigration, contains('insufficient_stock'));
    });

    test('T2.10.1 remains idempotent for stock and movements', () {
      expect(
        inventoryLockFixMigration,
        contains("COALESCE(v_order.stock_status, '') = 'deducted'"),
      );
      expect(inventoryLockFixMigration, contains('stock_already_deducted'));
      expect(inventoryLockFixMigration, contains("stock_status = 'deducted'"));
      expect(
        inventoryLockFixMigration,
        contains('INSERT INTO public.inventory_movements'),
      );
      expect(inventoryLockFixMigration, contains('-v_item.qty'));
      expect(
        inventoryLockFixMigration,
        contains("'exit'::public.inventory_movement_type"),
      );
      expect(
        inventoryLockFixMigration,
        contains("'order'::public.reference_type"),
      );
    });

    test('T2.10.1 converts the source cart only once', () {
      expect(
        inventoryLockFixMigration,
        contains("status = 'converted_to_order'"),
      );
      expect(
        inventoryLockFixMigration,
        contains('converted_order_id = v_order.id'),
      );
      expect(inventoryLockFixMigration, contains("status = 'active'"));
      expect(inventoryLockFixMigration, contains('converted_order_id IS NULL'));
    });

    test('T2.10.1 preserves backend-only RPC permissions', () {
      expect(inventoryLockFixMigration, contains('SECURITY DEFINER'));
      expect(
        inventoryLockFixMigration,
        contains("SET search_path TO 'pg_catalog', 'public'"),
      );
      expect(
        inventoryLockFixMigration,
        contains(
          'REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM PUBLIC',
        ),
      );
      expect(
        inventoryLockFixMigration,
        contains(
          'REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM anon',
        ),
      );
      expect(
        inventoryLockFixMigration,
        contains(
          'REVOKE EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) FROM authenticated',
        ),
      );
      expect(
        inventoryLockFixMigration,
        contains(
          'GRANT EXECUTE ON FUNCTION public.apply_paid_order_post_payment(uuid) TO service_role',
        ),
      );
    });
  });
}
