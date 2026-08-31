import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MercadoPagoCheckoutSession {
  const MercadoPagoCheckoutSession({
    required this.orderId,
    required this.paymentRecordId,
    required this.checkoutUri,
    required this.amount,
    required this.currencyId,
    this.alreadyPaid = false,
  });

  final String orderId;
  final String paymentRecordId;
  final Uri checkoutUri;
  final double amount;
  final String currencyId;
  final bool alreadyPaid;
}

class OrderPaymentSnapshot {
  const OrderPaymentSnapshot({
    required this.orderId,
    required this.orderStatus,
    required this.paymentStatus,
    required this.confirmed,
    this.total,
    this.paidAt,
    this.statusDetail,
    this.paymentId,
  });

  final String orderId;
  final String orderStatus;
  final String paymentStatus;
  final bool confirmed;
  final double? total;
  final DateTime? paidAt;
  final String? statusDetail;
  final String? paymentId;

  bool get approved => confirmed || paymentStatus == 'approved';
  bool get pending =>
      !approved &&
      (paymentStatus == 'created' ||
          paymentStatus == 'pending' ||
          paymentStatus == 'in_process' ||
          paymentStatus == 'not_found');
  bool get failed =>
      !approved &&
      (paymentStatus == 'rejected' ||
          paymentStatus == 'cancelled' ||
          paymentStatus == 'refunded' ||
          paymentStatus == 'charged_back');
}

class ServiceQuotePaymentResult {
  const ServiceQuotePaymentResult({
    required this.ok,
    required this.alreadyPaid,
    this.orderId,
    this.orderNumber,
    this.paymentRecordId,
    this.checkoutUri,
    this.amount,
    this.currencyId,
    this.reusedPreference = false,
  });

  final bool ok;
  final bool alreadyPaid;
  final String? orderId;
  final String? orderNumber;
  final String? paymentRecordId;
  final Uri? checkoutUri;
  final double? amount;
  final String? currencyId;
  final bool reusedPreference;
}

class MercadoPagoService {
  MercadoPagoService(this._supabase);

  final SupabaseClient _supabase;
  bool _opening = false;

  static const _allowedHosts = <String>{
    'mercadopago.com',
    'mercadopago.com.mx',
    'mercadopago.com.ar',
    'mercadopago.com.br',
    'mercadopago.cl',
    'mercadopago.co',
    'mpago.la',
  };

  Future<ServiceQuotePaymentResult> startServiceQuotePayment({
    required String quoteId,
    String? notes,
  }) async {
    if (_supabase.auth.currentSession == null) {
      throw Exception('Debes iniciar sesión para pagar.');
    }

    if (_opening) {
      throw Exception('Ya se está abriendo Mercado Pago.');
    }

    _opening = true;

    try {
      final response = await _supabase.functions.invoke(
        'create-mp-quote-order-preference',
        body: {
          'quote_id': quoteId,
          if (notes?.trim().isNotEmpty == true) 'notes': notes!.trim(),
        },
      );

      final data = response.data;
      if (response.status >= 400 || data is! Map) {
        final msg = data is Map ? data['message']?.toString() : null;
        throw Exception(
          msg ?? 'No fue posible iniciar el pago de la cotización.',
        );
      }

      final alreadyPaid = data['already_paid'] == true;
      final orderId = data['order_id']?.toString();
      final orderNumber = data['order_number']?.toString();
      final paymentRecordId = data['payment_record_id']?.toString();
      final amount = (data['amount'] as num?)?.toDouble();
      final currencyId = data['currency_id']?.toString() ?? 'MXN';
      final reusedPreference = data['reuse_preference'] == true;

      if (alreadyPaid) {
        return ServiceQuotePaymentResult(
          ok: true,
          alreadyPaid: true,
          orderId: orderId,
          orderNumber: orderNumber,
          amount: amount,
          currencyId: currencyId,
        );
      }

      final rawUrl = data['checkout_url']?.toString();
      if (rawUrl == null || rawUrl.trim().isEmpty) {
        throw Exception('No se recibió la URL de pago de Mercado Pago.');
      }

      final checkoutUri = validateCheckoutUri(rawUrl);

      await _openCheckout(checkoutUri);

      return ServiceQuotePaymentResult(
        ok: true,
        alreadyPaid: false,
        orderId: orderId,
        orderNumber: orderNumber,
        paymentRecordId: paymentRecordId,
        checkoutUri: checkoutUri,
        amount: amount,
        currencyId: currencyId,
        reusedPreference: reusedPreference,
      );
    } finally {
      _opening = false;
    }
  }

  Future<MercadoPagoCheckoutSession> startOrderPayment({
    required String cartId,
    String? shippingAddress,
    String? notes,
  }) async {
    if (_supabase.auth.currentSession == null) {
      throw Exception('Debes iniciar sesión para pagar.');
    }

    if (_opening) {
      throw Exception('Ya se está abriendo Mercado Pago.');
    }

    _opening = true;

    try {
      final response = await _supabase.functions.invoke(
        'create-mp-order-preference',
        body: {
          'cart_id': cartId,
          if (shippingAddress?.trim().isNotEmpty == true)
            'shipping_address': shippingAddress!.trim(),
          if (notes?.trim().isNotEmpty == true) 'notes': notes!.trim(),
        },
      );

      if (response.status >= 400) {
        final responseData = response.data;
        final message = responseData is Map
            ? responseData['message']?.toString()
            : null;

        throw Exception(
          message?.isNotEmpty == true
              ? message
              : 'No fue posible iniciar el pago.',
        );
      }

      final responseData = response.data;
      if (responseData is! Map) {
        throw Exception('Respuesta de pago inválida.');
      }

      final data = Map<String, dynamic>.from(responseData);
      final isAlreadyPaid = data['already_paid'] == true;

      final uri = validateCheckoutUri(
        data['checkout_url']?.toString() ?? 'https://mercadopago.com.mx',
      );

      final session = MercadoPagoCheckoutSession(
        orderId: data['order_id']?.toString() ?? '',
        paymentRecordId: data['payment_record_id']?.toString() ?? '',
        checkoutUri: uri,
        amount: (data['amount'] as num?)?.toDouble() ?? 0,
        currencyId: data['currency_id']?.toString() ?? 'MXN',
        alreadyPaid: isAlreadyPaid,
      );

      if (!isAlreadyPaid) {
        await _openCheckout(uri);
      }
      return session;
    } finally {
      _opening = false;
    }
  }

  Future<OrderPaymentSnapshot> verifyOrderPayment(String orderId) async {
    if (_supabase.auth.currentSession == null) {
      throw Exception('Debes iniciar sesión para verificar el pago.');
    }

    try {
      final response = await _supabase.functions.invoke(
        'verify-mp-order-payment',
        body: {'order_id': orderId.trim()},
      );

      if (response.status == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data);
        return OrderPaymentSnapshot(
          orderId: data['order_id']?.toString() ?? orderId,
          orderStatus: data['order_status']?.toString() ?? 'pending_payment',
          paymentStatus: data['payment_status']?.toString() ?? 'pending',
          confirmed: data['confirmed'] == true,
        );
      }
    } catch (_) {
      // Fallback a consulta directa de la orden en Supabase BD
    }

    return getOrderPaymentFallback(orderId);
  }

  Future<OrderPaymentSnapshot> getOrderPaymentFallback(String orderId) async {
    final order = await _supabase
        .from('orders')
        .select('id,status,payment_status,total,paid_at,payment_id')
        .eq('id', orderId)
        .maybeSingle();

    if (order == null) {
      return OrderPaymentSnapshot(
        orderId: orderId,
        orderStatus: 'pending_payment',
        paymentStatus: 'pending',
        confirmed: false,
      );
    }

    final payment = await _supabase
        .from('order_payments')
        .select('status,status_detail,payment_id')
        .eq('order_id', orderId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final pStatus =
        order['payment_status']?.toString() ??
        payment?['status']?.toString() ??
        'pending';
    final isConfirmed =
        pStatus == 'approved' || order['status']?.toString() == 'paid';

    return OrderPaymentSnapshot(
      orderId: order['id'].toString(),
      orderStatus: order['status'].toString(),
      paymentStatus: pStatus,
      confirmed: isConfirmed,
      total: (order['total'] as num?)?.toDouble() ?? 0.0,
      paidAt: DateTime.tryParse(order['paid_at']?.toString() ?? ''),
      statusDetail: payment?['status_detail']?.toString(),
      paymentId:
          order['payment_id']?.toString() ?? payment?['payment_id']?.toString(),
    );
  }

  Future<void> _openCheckout(Uri url) async {
    try {
      await launchUrl(
        url,
        prefersDeepLink: true,
        customTabsOptions: const CustomTabsOptions(
          browser: CustomTabsBrowserConfiguration(prefersDefaultBrowser: true),
          showTitle: true,
          shareState: CustomTabsShareState.off,
          urlBarHidingEnabled: false,
        ),
        safariVCOptions: const SafariViewControllerOptions(
          entersReaderIfAvailable: false,
          barCollapsingEnabled: false,
          dismissButtonStyle: SafariViewControllerDismissButtonStyle.close,
        ),
      );
    } catch (_) {
      try {
        await launchUrl(
          url,
          prefersDeepLink: false,
          customTabsOptions: const CustomTabsOptions(
            browser: CustomTabsBrowserConfiguration(
              prefersDefaultBrowser: true,
            ),
            showTitle: true,
            shareState: CustomTabsShareState.off,
            urlBarHidingEnabled: false,
          ),
          safariVCOptions: const SafariViewControllerOptions(
            entersReaderIfAvailable: false,
            barCollapsingEnabled: false,
            dismissButtonStyle: SafariViewControllerDismissButtonStyle.close,
          ),
        );
      } catch (_) {
        throw Exception(
          'No fue posible abrir Mercado Pago. '
          'Verifica que tengas un navegador instalado y vuelve a intentarlo.',
        );
      }
    }
  }

  static Uri validateCheckoutUri(String value) {
    final uri = Uri.tryParse(value.trim());

    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority) {
      throw Exception('La URL de Mercado Pago no es válida.');
    }

    final host = uri.host.toLowerCase();
    final allowed = _allowedHosts.any(
      (item) => host == item || host.endsWith('.$item'),
    );

    if (!allowed) {
      throw Exception('La URL no pertenece a Mercado Pago.');
    }

    return uri;
  }
}
