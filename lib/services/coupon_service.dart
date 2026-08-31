import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_coupon.dart';

final _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class CouponEligibleProductsResult {
  final List<String> productIds;
  final int totalCount;
  final bool isFullCatalog;

  const CouponEligibleProductsResult({
    required this.productIds,
    required this.totalCount,
    required this.isFullCatalog,
  });

  factory CouponEligibleProductsResult.fromRpc(dynamic response) {
    if (response == null || response is! Map) {
      throw const FormatException(
        'Respuesta del servidor no válida para cupones.',
      );
    }

    final map = response;

    // 1. Debe contener explícitamente las tres claves obligatorias
    if (!map.containsKey('product_ids') ||
        !map.containsKey('total_count') ||
        !map.containsKey('is_full_catalog')) {
      throw const FormatException(
        'Formato de respuesta incompleto para productos de cupón.',
      );
    }

    // 2. Validar total_count: debe ser un entero >= 0
    final rawCount = map['total_count'];
    final int totalCount;
    if (rawCount is int) {
      totalCount = rawCount;
    } else if (rawCount is num && rawCount == rawCount.roundToDouble()) {
      totalCount = rawCount.toInt();
    } else {
      throw const FormatException('Campo total_count inválido.');
    }

    if (totalCount < 0) {
      throw const FormatException('total_count no puede ser negativo.');
    }

    // 3. Validar product_ids: debe ser List y cada elemento estrictamente String UUID
    final rawIds = map['product_ids'];
    if (rawIds is! List) {
      throw const FormatException('Campo product_ids inválido.');
    }

    final productIds = <String>[];
    for (final item in rawIds) {
      if (item is! String) {
        throw const FormatException(
          'Elemento no es String dentro de product_ids.',
        );
      }
      final trimmed = item.trim();
      if (trimmed.isEmpty || !_uuidRegex.hasMatch(trimmed)) {
        throw const FormatException(
          'Elemento no es un UUID válido dentro de product_ids.',
        );
      }
      productIds.add(trimmed.toLowerCase());
    }

    // 4. Consistencia entre product_ids y total_count
    if (totalCount == 0 && productIds.isNotEmpty) {
      throw const FormatException(
        'Inconsistencia: product_ids no está vacío cuando total_count es 0.',
      );
    }

    if (productIds.length > totalCount) {
      throw const FormatException(
        'Inconsistencia: la cantidad de product_ids excede total_count.',
      );
    }

    // 5. Validar is_full_catalog: debe ser bool
    final rawFullCatalog = map['is_full_catalog'];
    if (rawFullCatalog is! bool) {
      throw const FormatException('Campo is_full_catalog inválido.');
    }

    return CouponEligibleProductsResult(
      productIds: productIds,
      totalCount: totalCount,
      isFullCatalog: rawFullCatalog,
    );
  }
}

/// Servicio para consultar los cupones disponibles para el cliente autenticado.
///
/// REGLA DE SEGURIDAD:
/// Consume exclusivamente las funciones autoritativas `public.get_my_coupons()`
/// y `public.get_coupon_eligible_product_ids()`.
/// No realiza SELECT directo sobre tablas de cupones ni envía identificadores de cliente desde el frontend.
class CouponService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Obtiene los cupones asociados o disponibles para el cliente autenticado en sesión.
  static Future<List<CustomerCoupon>> getMyCoupons({
    SupabaseClient? client,
  }) async {
    final effectiveClient = client ?? _client;
    final user = effectiveClient.auth.currentUser;
    if (user == null) {
      throw Exception('Sesión no válida. Inicia sesión para ver tus cupones.');
    }

    try {
      final response = await effectiveClient
          .rpc('get_my_coupons')
          .timeout(const Duration(seconds: 25));

      if (response == null) return const [];
      if (response is! List) {
        debugPrint(
          'get_my_coupons devolvió un tipo no esperado: ${response.runtimeType}',
        );
        return const [];
      }

      return response
          .whereType<Map>()
          .map(
            (item) => CustomerCoupon.fromRpc(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('Error en CouponService.getMyCoupons: $e');
      rethrow;
    }
  }

  /// Obtiene los IDs de productos participantes y metadata mínima para un cupón.
  static Future<CouponEligibleProductsResult> getCouponEligibleProductIds({
    required String couponId,
    String? search,
    int limit = 20,
    int offset = 0,
    SupabaseClient? client,
  }) async {
    final effectiveClient = client ?? _client;
    final user = effectiveClient.auth.currentUser;
    if (user == null) {
      throw Exception(
        'Sesión no válida. Inicia sesión para consultar los productos.',
      );
    }

    try {
      final response = await effectiveClient
          .rpc(
            'get_coupon_eligible_product_ids',
            params: {
              'p_coupon_id': couponId,
              if (search != null && search.trim().isNotEmpty)
                'p_search': search.trim(),
              'p_limit': limit,
              'p_offset': offset,
            },
          )
          .timeout(const Duration(seconds: 25));

      return CouponEligibleProductsResult.fromRpc(response);
    } catch (e) {
      debugPrint('Error en CouponService.getCouponEligibleProductIds: $e');
      rethrow;
    }
  }
}
