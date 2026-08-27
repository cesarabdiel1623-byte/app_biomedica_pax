import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_coupon.dart';

/// Servicio para consultar los cupones disponibles para el cliente autenticado.
///
/// REGLA DE SEGURIDAD:
/// Consume exclusivamente la función autoritativa `public.get_my_coupons()`.
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
}
