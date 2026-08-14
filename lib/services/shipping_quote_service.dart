import 'package:supabase_flutter/supabase_flutter.dart';

class ShippingRate {
  final String rateId;
  final String carrier;
  final String service;
  final int days;
  final double actualShippingCost;
  final double customerShippingAmount;
  final double shippingDiscountAmount;
  final String label;

  ShippingRate({
    required this.rateId,
    required this.carrier,
    required this.service,
    required this.days,
    required this.actualShippingCost,
    required this.customerShippingAmount,
    required this.shippingDiscountAmount,
    required this.label,
  });

  factory ShippingRate.fromJson(Map<String, dynamic> json) {
    return ShippingRate(
      rateId: json['rate_id']?.toString() ?? '',
      carrier: json['carrier']?.toString() ?? 'Carrier',
      service: json['service']?.toString() ?? 'Estándar',
      days: (json['days'] as num?)?.toInt() ?? 3,
      actualShippingCost:
          (json['actual_shipping_cost'] as num?)?.toDouble() ?? 0.0,
      customerShippingAmount:
          (json['customer_shipping_amount'] as num?)?.toDouble() ?? 0.0,
      shippingDiscountAmount:
          (json['shipping_discount_amount'] as num?)?.toDouble() ?? 0.0,
      label: json['label']?.toString() ?? 'GRATIS',
    );
  }
}

class ShippingQuoteResult {
  final bool ok;
  final bool shippable;
  final String? error;
  final String? message;
  final String? productId;
  final String? productName;
  final double productSubtotal;
  final double freeShippingThreshold;
  final bool freeShippingUnlocked;
  final double cheapestValidRateTotal;
  final String quotationId;
  final List<ShippingRate> rates;

  ShippingQuoteResult({
    required this.ok,
    required this.shippable,
    this.error,
    this.message,
    this.productId,
    this.productName,
    this.productSubtotal = 0.0,
    this.freeShippingThreshold = 5000.0,
    this.freeShippingUnlocked = false,
    this.cheapestValidRateTotal = 0.0,
    this.quotationId = '',
    this.rates = const [],
  });

  factory ShippingQuoteResult.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true;
    final shippable = json['shippable'] == true;
    final rawRates = json['rates'] as List<dynamic>? ?? [];

    return ShippingQuoteResult(
      ok: ok,
      shippable: shippable,
      error: json['error']?.toString(),
      message: json['message']?.toString(),
      productId: json['product_id']?.toString(),
      productName: json['product_name']?.toString(),
      productSubtotal: (json['product_subtotal'] as num?)?.toDouble() ?? 0.0,
      freeShippingThreshold:
          (json['free_shipping_threshold'] as num?)?.toDouble() ?? 5000.0,
      freeShippingUnlocked: json['free_shipping_unlocked'] == true,
      cheapestValidRateTotal:
          (json['cheapest_valid_rate_total'] as num?)?.toDouble() ?? 0.0,
      quotationId: json['quotation_id']?.toString() ?? '',
      rates: rawRates
          .whereType<Map<String, dynamic>>()
          .map(ShippingRate.fromJson)
          .toList(),
    );
  }
}

class ShippingQuoteService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<ShippingQuoteResult> fetchQuote({
    required String cartId,
    String? addressId,
  }) async {
    final response = await _supabase.functions.invoke(
      'skydropx-mobile-quote',
      body: {
        'cart_id': cartId,
        if (addressId != null && addressId.isNotEmpty) 'address_id': addressId,
      },
    );

    if (response.status >= 400 && response.data is Map<String, dynamic>) {
      return ShippingQuoteResult.fromJson(
        response.data as Map<String, dynamic>,
      );
    }

    if (response.data is Map<String, dynamic>) {
      return ShippingQuoteResult.fromJson(
        response.data as Map<String, dynamic>,
      );
    }

    throw Exception(
      'Error al comunicarse con el servicio de cotización de envío.',
    );
  }
}
