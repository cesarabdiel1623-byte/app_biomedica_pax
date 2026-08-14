import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef MercadoPagoSessionGetter = Session? Function();
typedef MercadoPagoInvoke = Future<dynamic> Function(Map<String, dynamic> body);
typedef MercadoPagoUrlOpener = Future<void> Function(Uri url);

class MercadoPagoTestService {
  MercadoPagoTestService(
    this._supabase, {
    MercadoPagoSessionGetter? sessionGetter,
    MercadoPagoInvoke? invokePreference,
    MercadoPagoUrlOpener? openCheckout,
  }) : _sessionGetter = sessionGetter,
       _invokePreference = invokePreference,
       _openCheckout = openCheckout;

  final SupabaseClient _supabase;
  final MercadoPagoSessionGetter? _sessionGetter;
  final MercadoPagoInvoke? _invokePreference;
  final MercadoPagoUrlOpener? _openCheckout;

  bool _isOpening = false;

  static const _allowedCheckoutHosts = <String>{
    'mercadopago.com',
    'mercadopago.com.mx',
    'mercadopago.com.ar',
    'mercadopago.com.br',
    'mercadopago.cl',
    'mercadopago.co',
    'mercadopago.com.uy',
    'mercadopago.com.pe',
    'mercadopago.com.ec',
    'mercadopago.com.ve',
    'mercadopago.com.bo',
    'mercadopago.com.do',
    'mercadopago.com.pa',
    'mercadopago.com.py',
    'mpago.la',
  };

  Future<void> startTestPayment({
    required String cartId,
    String? addressId,
    String? quotationId,
    String? rateId,
    String? notes,
  }) async {
    final session = (_sessionGetter ?? _defaultSessionGetter).call();
    if (session == null) {
      throw Exception('Debes iniciar sesión para realizar el pago de prueba.');
    }

    if (_isOpening) {
      throw Exception(
        'Ya hay una apertura de Mercado Pago en curso. Espera un momento.',
      );
    }

    if (addressId == null ||
        addressId.isEmpty ||
        quotationId == null ||
        quotationId.isEmpty ||
        rateId == null ||
        rateId.isEmpty) {
      throw Exception(
        'Debes seleccionar una opción de envío válida para continuar al pago.',
      );
    }

    _isOpening = true;
    try {
      final payload = <String, dynamic>{
        'cart_id': cartId,
        'address_id': addressId,
        'skydropx_quotation_id': quotationId,
        'skydropx_rate_id': rateId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      final data = await (_invokePreference ?? _invokeCreatePreference).call(
        payload,
      );

      if (data is! Map) {
        throw Exception('Supabase devolvió una respuesta de pago inválida.');
      }

      final checkoutUrl = data['checkout_url'];
      if (checkoutUrl is! String || checkoutUrl.trim().isEmpty) {
        throw Exception('No se recibió una URL válida de Mercado Pago.');
      }

      final checkoutUri = validateCheckoutUri(checkoutUrl);
      await (_openCheckout ?? _defaultOpenCheckout).call(checkoutUri);
    } finally {
      _isOpening = false;
    }
  }

  Session? _defaultSessionGetter() => _supabase.auth.currentSession;

  Future<dynamic> _invokeCreatePreference(Map<String, dynamic> body) async {
    final response = await _supabase.functions.invoke(
      'create-mp-test-preference',
      body: body,
    );

    if (response.status == 401) {
      throw Exception('Tu sesión expiró. Inicia sesión nuevamente.');
    }
    if (response.status == 405) {
      throw Exception('La función de pago de prueba no acepta este método.');
    }
    if (response.status >= 500) {
      throw Exception(
        'No fue posible iniciar Mercado Pago. Revisa la configuración del backend.',
      );
    }

    return response.data;
  }

  Future<void> _defaultOpenCheckout(Uri url) async {
    await launchUrl(
      url,
      customTabsOptions: const CustomTabsOptions(
        showTitle: true,
        shareState: CustomTabsShareState.off,
        urlBarHidingEnabled: true,
      ),
      safariVCOptions: const SafariViewControllerOptions(
        entersReaderIfAvailable: false,
        barCollapsingEnabled: true,
      ),
    );
  }

  static Uri validateCheckoutUri(String checkoutUrl) {
    final uri = Uri.tryParse(checkoutUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw Exception('Mercado Pago devolvió una URL inválida.');
    }
    if (uri.scheme.toLowerCase() != 'https') {
      throw Exception('La URL de Mercado Pago debe usar HTTPS.');
    }

    final host = uri.host.toLowerCase();
    final isAllowed = _allowedCheckoutHosts.any(
      (allowedHost) => host == allowedHost || host.endsWith('.$allowedHost'),
    );
    if (!isAllowed) {
      throw Exception('El dominio de checkout no pertenece a Mercado Pago.');
    }

    return uri;
  }
}
