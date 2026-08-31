import 'package:flutter/material.dart';

/// Modelo tipado seguro para representar un cupón disponible para el cliente,
/// obtenido exclusivamente mediante la función autoritativa `get_my_coupons()`.
class CustomerCoupon {
  final String couponId;
  final String code;
  final String name;
  final String? publicDescription;
  final String? publicTerms;
  final String discountType;
  final double discountValue;
  final double minimumSubtotal;
  final double? maximumDiscount;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String applicationScope;
  final String catalogScope;
  final bool combinableWithPromotions;
  final String distributionScope;
  final int? usageLimit;
  final int? clientUsageLimit;
  final int clientUses;
  final int? remainingUses;
  final String couponState;

  const CustomerCoupon({
    required this.couponId,
    required this.code,
    required this.name,
    this.publicDescription,
    this.publicTerms,
    required this.discountType,
    required this.discountValue,
    this.minimumSubtotal = 0.0,
    this.maximumDiscount,
    this.validFrom,
    this.validUntil,
    this.applicationScope = 'purchase',
    this.catalogScope = 'all',
    this.combinableWithPromotions = false,
    this.distributionScope = 'all_clients',
    this.usageLimit,
    this.clientUsageLimit,
    this.clientUses = 0,
    this.remainingUses,
    required this.couponState,
  });

  static double _parseDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    return defaultValue;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is String) {
      final parsed = DateTime.tryParse(value.trim());
      return parsed?.toLocal();
    }
    return null;
  }

  static const Set<String> _knownStates = {
    'available',
    'not_started',
    'used',
    'expired',
    'limit_reached',
  };

  static String _parseCouponState(dynamic value) {
    if (value == null) return 'unknown';
    final normalized = value.toString().trim().toLowerCase();
    if (_knownStates.contains(normalized)) {
      return normalized;
    }
    return 'unknown';
  }

  factory CustomerCoupon.fromRpc(Map<String, dynamic> map) {
    final rawDesc = map['public_description']?.toString().trim();
    final rawTerms = map['public_terms']?.toString().trim();

    return CustomerCoupon(
      couponId: (map['coupon_id'] ?? map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString().trim(),
      name: (map['name'] ?? '').toString().trim(),
      publicDescription: (rawDesc != null && rawDesc.isNotEmpty)
          ? rawDesc
          : null,
      publicTerms: (rawTerms != null && rawTerms.isNotEmpty) ? rawTerms : null,
      discountType: (map['discount_type'] ?? 'percentage').toString().trim(),
      discountValue: _parseDouble(map['discount_value']),
      minimumSubtotal: _parseDouble(map['minimum_subtotal']),
      maximumDiscount: map['maximum_discount'] != null
          ? _parseDouble(map['maximum_discount'])
          : (map['max_discount_amount'] != null
                ? _parseDouble(map['max_discount_amount'])
                : null),
      validFrom: _parseDate(map['valid_from'] ?? map['starts_at']),
      validUntil: _parseDate(map['valid_until'] ?? map['ends_at']),
      applicationScope: (map['application_scope'] ?? 'purchase').toString(),
      catalogScope: (map['catalog_scope'] ?? 'all').toString(),
      combinableWithPromotions: map['combinable_with_promotions'] == true,
      distributionScope: (map['distribution_scope'] ?? 'all_clients')
          .toString(),
      usageLimit: _parseInt(map['usage_limit'] ?? map['usage_limit_total']),
      clientUsageLimit: _parseInt(
        map['client_usage_limit'] ?? map['usage_limit_per_client'],
      ),
      clientUses: _parseInt(map['client_uses']) ?? 0,
      remainingUses: _parseInt(map['remaining_uses']),
      couponState: _parseCouponState(map['coupon_state']),
    );
  }

  bool get isAvailable => couponState == 'available';
  bool get isUsed => couponState == 'used';
  bool get isExpired => couponState == 'expired';
  bool get isNotStarted => couponState == 'not_started';
  bool get isLimitReached => couponState == 'limit_reached';

  String get benefitText {
    switch (discountType) {
      case 'percentage':
        final formatted = discountValue.truncateToDouble() == discountValue
            ? discountValue.toInt().toString()
            : discountValue.toStringAsFixed(1);
        return '$formatted% de descuento';
      case 'fixed_amount':
        final formatted = discountValue.truncateToDouble() == discountValue
            ? discountValue.toInt().toString()
            : discountValue.toStringAsFixed(2);
        return '\$$formatted MXN de descuento';
      case 'free_shipping':
        return 'Envío gratis';
      default:
        return 'Descuento especial';
    }
  }

  String get stateLabel {
    switch (couponState) {
      case 'available':
        return 'Disponible';
      case 'not_started':
        return 'Próximamente';
      case 'used':
        return 'Utilizado';
      case 'expired':
        return 'Vencido';
      case 'limit_reached':
        return 'Límite alcanzado';
      default:
        return 'No disponible';
    }
  }

  Color get stateColor {
    switch (couponState) {
      case 'available':
        return const Color(0xFF10B981);
      case 'not_started':
        return const Color(0xFF3B82F6);
      case 'used':
        return const Color(0xFF64748B);
      case 'expired':
        return const Color(0xFFEF4444);
      case 'limit_reached':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  static String _formatDateShort(DateTime dt) {
    final month = _months[dt.month - 1];
    return '${dt.day} de $month. ${dt.year}';
  }

  String? get formattedValidUntil {
    if (validUntil == null) return null;
    return 'Válido hasta el ${_formatDateShort(validUntil!)}';
  }

  String? get formattedValidFrom {
    if (validFrom == null) return null;
    return 'Desde el ${_formatDateShort(validFrom!)}';
  }

  String get formattedValidRange {
    if (validFrom != null && validUntil != null) {
      return 'Del ${_formatDateShort(validFrom!)} al ${_formatDateShort(validUntil!)}';
    } else if (validUntil != null) {
      return formattedValidUntil!;
    } else if (validFrom != null) {
      return 'Disponible desde el ${_formatDateShort(validFrom!)}';
    }
    return 'Sin límite de vigencia';
  }

  String? get minimumSubtotalText {
    if (minimumSubtotal <= 0) return null;
    final formatted = minimumSubtotal.truncateToDouble() == minimumSubtotal
        ? minimumSubtotal.toInt().toString()
        : minimumSubtotal.toStringAsFixed(2);
    return 'Compra mínima: \$$formatted MXN';
  }

  String? get maximumDiscountText {
    if (maximumDiscount == null || maximumDiscount! <= 0) return null;
    final formatted = maximumDiscount!.truncateToDouble() == maximumDiscount!
        ? maximumDiscount!.toInt().toString()
        : maximumDiscount!.toStringAsFixed(2);
    return 'Descuento máximo: \$$formatted MXN';
  }

  String? get remainingUsesText {
    if (remainingUses != null) {
      return '$remainingUses ${remainingUses == 1 ? 'uso restante' : 'usos restantes'}';
    }
    if (clientUsageLimit != null) {
      final left = (clientUsageLimit! - clientUses).clamp(0, 999);
      return '$left ${left == 1 ? 'uso restante' : 'usos restantes'}';
    }
    return null;
  }
}
