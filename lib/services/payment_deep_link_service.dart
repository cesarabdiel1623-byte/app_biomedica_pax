import 'dart:async';

import 'package:app_links/app_links.dart';

import '../models/payment_test_result.dart';

typedef PaymentResultHandler = void Function(PaymentTestResult result);
typedef InitialPaymentLinkLoader = Future<Uri?> Function();
typedef PaymentLinkStreamFactory = Stream<Uri> Function();

class PaymentDeepLinkService {
  PaymentDeepLinkService({
    AppLinks? appLinks,
    InitialPaymentLinkLoader? initialLinkLoader,
    PaymentLinkStreamFactory? linkStreamFactory,
  }) : _appLinks = appLinks ?? AppLinks(),
       _initialLinkLoader = initialLinkLoader,
       _linkStreamFactory = linkStreamFactory;

  final AppLinks _appLinks;
  final InitialPaymentLinkLoader? _initialLinkLoader;
  final PaymentLinkStreamFactory? _linkStreamFactory;

  StreamSubscription<Uri>? _subscription;
  PaymentResultHandler? _onResult;
  String? _lastHandledKey;
  bool _initialized = false;

  Future<void> init({required PaymentResultHandler onResult}) async {
    _onResult = onResult;
    if (_initialized) return;
    _initialized = true;

    final initialUri =
        await (_initialLinkLoader?.call() ?? _appLinks.getInitialLink());
    _handleUri(initialUri);

    final stream = _linkStreamFactory?.call() ?? _appLinks.uriLinkStream;
    _subscription = stream.listen(
      _handleUri,
      onError: (_) {
        // Ignorar errores del stream y mantener la app estable.
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }

  static PaymentTestResult? parseResult(Uri uri) {
    if (uri.scheme.toLowerCase() != 'gomedical') return null;
    if (uri.host.toLowerCase() != 'payment') return null;

    switch (uri.path.toLowerCase()) {
      case '/success':
        return PaymentTestResult.success;
      case '/pending':
        return PaymentTestResult.pending;
      case '/failure':
        return PaymentTestResult.failure;
      default:
        return null;
    }
  }

  void _handleUri(Uri? uri) {
    if (uri == null) return;

    final result = parseResult(uri);
    if (result == null) return;

    final dedupeKey =
        '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}${uri.path.toLowerCase()}';
    if (_lastHandledKey == dedupeKey) return;
    _lastHandledKey = dedupeKey;
    _onResult?.call(result);
  }
}
