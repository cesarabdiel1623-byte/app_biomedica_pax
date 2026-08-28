import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/address_service.dart';
import '../../../services/cart_service.dart';
import '../../../services/mercado_pago_test_service.dart';
import '../../../services/shipping_quote_service.dart';
import '../../../utils/price_formatter.dart';
import '../../../widgets/standard_section_header.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kBg = Color(0xFFF8FAFC);
const _shippingProcessingRetryDelay = Duration(seconds: 2);
const _shippingProcessingMaxRetries = 3;

class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({
    super.key,
    required this.cartId,
    required this.subtotal,
    required this.total,
    required this.onSuccess,
    this.cartPricingAmounts,
    this.asPage = false,
  });

  final String cartId;
  final double subtotal;
  final double total;
  final VoidCallback onSuccess;
  final CartPricingAmounts? cartPricingAmounts;
  final bool asPage;

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  bool _isQuote = false;
  bool _loading = false;
  bool _fetchingShipping = false;
  bool _syncingCouponState = false;

  final _notesController = TextEditingController();

  List<dynamic> _addresses = [];
  String? _selectedAddressId;
  String _selectedAddressLabel = 'Dirección predeterminada';

  ShippingQuoteResult? _shippingQuoteResult;
  ShippingRate? _selectedShippingRate;
  String? _shippingErrorMessage;
  bool _pricingMismatchLogged = false;

  @override
  void initState() {
    super.initState();
    _loadAddressesAndQuote();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAddressesAndQuote() async {
    setState(() => _fetchingShipping = true);
    final initialQuoteFuture = widget.cartId.isEmpty
        ? Future<ShippingQuoteResult?>.value(null)
        : ShippingQuoteService.fetchQuote(cartId: widget.cartId)
              .then<ShippingQuoteResult?>((result) => result)
              .catchError((_) => null);

    try {
      final list = await AddressService.getAddresses();
      _addresses = list;

      if (list.isNotEmpty) {
        final defaultAddr = list.firstWhere(
          (a) => a.isDefault,
          orElse: () => list.first,
        );
        _selectedAddressId = defaultAddr.id;
        _selectedAddressLabel = '${defaultAddr.label} - ${defaultAddr.address}';
      }
    } catch (_) {
      // La cotización puede seguir usando la dirección predeterminada
      // que resuelve el backend si no se envía address_id.
    }

    final result = await initialQuoteFuture;
    if (!mounted) return;
    if (result != null) {
      await _handleShippingQuoteResult(result, _selectedAddressId);
      return;
    }

    try {
      await _fetchQuoteForAddress(_selectedAddressId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _shippingErrorMessage = 'No se pudo cotizar el envío.';
          _fetchingShipping = false;
        });
      }
    }
  }

  Future<void> _handleShippingQuoteResult(
    ShippingQuoteResult result,
    String? addressId, {
    int processingRetry = 0,
  }) async {
    if (result.isStillProcessing &&
        processingRetry < _shippingProcessingMaxRetries) {
      await Future.delayed(_shippingProcessingRetryDelay);
      if (!mounted) return;
      await _fetchQuoteForAddress(
        addressId,
        processingRetry: processingRetry + 1,
      );
      return;
    }

    _applyShippingQuoteResult(result);
  }

  void _applyShippingQuoteResult(ShippingQuoteResult result) {
    if (!result.shippable) {
      setState(() {
        _shippingErrorMessage =
            result.message ??
            'El producto "${result.productName ?? ''}" no cuenta con dimensiones logísticas para cotizar envío.';
        _fetchingShipping = false;
      });
      return;
    }

    if (!result.ok) {
      setState(() {
        _shippingErrorMessage =
            result.message ?? 'No se pudo obtener la cotización de envío.';
        _fetchingShipping = false;
      });
      return;
    }

    setState(() {
      _shippingQuoteResult = result;
      if (result.rates.isNotEmpty) {
        _selectedShippingRate = result.rates.first;
      } else {
        _shippingErrorMessage =
            'No se encontraron opciones de envío para la dirección seleccionada.';
      }
      _fetchingShipping = false;
    });
  }

  Future<void> _fetchQuoteForAddress(
    String? addressId, {
    int processingRetry = 0,
  }) async {
    if (widget.cartId.isEmpty) {
      setState(() => _fetchingShipping = false);
      return;
    }

    if (processingRetry == 0) {
      setState(() {
        _fetchingShipping = true;
        _shippingErrorMessage = null;
        _shippingQuoteResult = null;
        _selectedShippingRate = null;
      });
    }

    try {
      final result = await ShippingQuoteService.fetchQuote(
        cartId: widget.cartId,
        addressId: addressId,
      );

      if (!mounted) return;

      await _handleShippingQuoteResult(
        result,
        addressId,
        processingRetry: processingRetry,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _shippingErrorMessage = _friendlyShippingError(e);
          _fetchingShipping = false;
        });
      }
    }
  }

  String _friendlyShippingError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('network') ||
        text.contains('timeout')) {
      return 'No se pudo cotizar el envío. Revisa tu conexión e intenta nuevamente.';
    }

    return 'No se pudo cotizar el envío. Intenta nuevamente.';
  }

  String get _shippingErrorTitle {
    final message = _shippingErrorMessage?.toLowerCase() ?? '';
    if (message.contains('procesando')) {
      return 'Cotización en proceso';
    }
    if (message.contains('dimensiones logísticas') ||
        message.contains('no cuenta con dimensiones')) {
      return 'Faltan datos de envío';
    }
    return 'No pudimos cotizar el envío';
  }

  double get _currentCustomerShippingAmount {
    return _selectedShippingRate?.customerShippingAmount ?? 0.0;
  }

  double get _localCommercialSubtotal {
    return roundFinancialAmount(
      widget.cartPricingAmounts?.effectiveItemsSubtotal ?? widget.subtotal,
    );
  }

  void _logPricingMismatchOnce(double localSubtotal, double backendSubtotal) {
    if (_pricingMismatchLogged) return;
    _pricingMismatchLogged = true;
    assert(() {
      debugPrint(
        'pricing_mismatch local_commercial_subtotal=$localSubtotal '
        'backend_product_subtotal=$backendSubtotal',
      );
      return true;
    }());
  }

  double get _displayProductSubtotal {
    final localSubtotal = _localCommercialSubtotal;
    final backendSubtotal = _shippingQuoteResult?.productSubtotal;
    if (backendSubtotal == null) return localSubtotal;

    final roundedBackendSubtotal = roundFinancialAmount(backendSubtotal);
    if ((roundedBackendSubtotal - localSubtotal).abs() > 0.009) {
      _logPricingMismatchOnce(localSubtotal, roundedBackendSubtotal);
      return localSubtotal;
    }

    return roundedBackendSubtotal;
  }

  double get _couponDiscountAmount =>
      widget.cartPricingAmounts?.couponDiscount ?? 0.0;

  double get _displayPayableProductAmount {
    return roundFinancialAmount(
      (_displayProductSubtotal - _couponDiscountAmount).clamp(
        0.0,
        double.infinity,
      ),
    );
  }

  double get _calculatedTotal {
    return _displayPayableProductAmount + _currentCustomerShippingAmount;
  }

  bool get _canSubmitPayment {
    if (_loading || _fetchingShipping || _syncingCouponState) return false;
    if (_shippingQuoteResult == null || !_shippingQuoteResult!.shippable) {
      return false;
    }
    if (_selectedShippingRate == null) return false;
    if (_shippingQuoteResult!.quotationId.trim().isEmpty) return false;
    if (_selectedShippingRate!.rateId.trim().isEmpty) return false;
    return true;
  }

  Future<void> _submit() async {
    if (_isQuote) {
      await _submitQuote();
      return;
    }

    await _startMercadoPagoTest();
  }

  Future<void> _submitQuote() async {
    setState(() => _loading = true);

    try {
      final notesText = _notesController.text.trim();
      final quoteId = await CartService.requestQuote(notes: notesText);

      try {
        final addr = await AddressService.getDefaultAddress();
        final updateFields = <String, dynamic>{
          if (addr != null) 'shipping_address': addr.address,
        };

        if (addr == null) {
          final list = await AddressService.getAddresses();
          if (list.isNotEmpty) {
            updateFields['shipping_address'] = list.first.address;
          }
        }

        await Supabase.instance.client
            .from('quotes')
            .update(updateFields)
            .eq('id', quoteId);
      } catch (quoteErr) {
        debugPrint('Aviso al guardar la dirección de la cotización: $quoteErr');
      }

      if (!mounted) return;

      Navigator.pop(context);
      widget.onSuccess();

      showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: _kPrimary, size: 28),
              SizedBox(width: 10),
              Text(
                '¡Cotización Solicitada!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Tu solicitud de cotización ha sido generada con éxito.\n\nEl área administrativa la revisará y recibirás una notificación cuando sea enviada o aprobada.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text(
                'Aceptar',
                style: TextStyle(color: _kPrimary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        final errMsg = e.toString().replaceAll('Exception: ', '');
        _showError('Error al solicitar la cotización: $errMsg');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startMercadoPagoTest() async {
    if (!_canSubmitPayment) return;
    setState(() {
      _loading = true;
      _syncingCouponState = true;
    });
    final service = MercadoPagoTestService(Supabase.instance.client);

    try {
      final cleanup = await CartService.clearInvalidPersistedCouponIfAny();
      if (!mounted) return;
      if (cleanup.removed) {
        _showWarning(
          cleanup.reason == 'not_combinable'
              ? 'El cupón ${cleanup.code ?? ''} no se puede combinar con la promoción activa y fue retirado del carrito. Intenta continuar de nuevo.'
              : 'El cupón guardado ya no aplica y fue retirado del carrito. Intenta continuar de nuevo.',
        );
        setState(() {
          _loading = false;
          _syncingCouponState = false;
        });
        return;
      }

      await service.startTestPayment(
        cartId: widget.cartId,
        addressId: _selectedAddressId,
        quotationId: _shippingQuoteResult?.quotationId,
        rateId: _selectedShippingRate?.rateId,
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Abriendo Mercado Pago...'),
          backgroundColor: const Color(0xFF0D9488),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        final errMsg = e.toString().replaceAll('Exception: ', '');
        _showError(errMsg);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _syncingCouponState = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final subtitle = _isQuote
        ? 'Completa tus datos para solicitar la cotización'
        : 'Revisa tu pedido y selecciona tu método de entrega';

    if (widget.asPage) {
      return Scaffold(
        backgroundColor: _kBg,
        body: Column(
          children: [
            StandardSectionHeader(
              title: 'Revisar pedido',
              subtitle: subtitle,
              backgroundColor: _kPrimary,
              backTooltip: 'Regresar',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTotalCard(),
                    const SizedBox(height: 16),
                    _buildShippingSection(),
                    const SizedBox(height: 16),
                    _buildTransactionSelector(),
                    const SizedBox(height: 16),
                    if (_isQuote) ...[
                      _buildQuoteForm(),
                    ] else ...[
                      _buildMercadoPagoTestSection(currentUser != null),
                    ],
                    const SizedBox(height: 24),
                    _buildActionButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Revisar pedido',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTotalCard(),
                  const SizedBox(height: 16),
                  _buildShippingSection(),
                  const SizedBox(height: 16),
                  _buildTransactionSelector(),
                  const SizedBox(height: 16),
                  if (_isQuote) ...[
                    _buildQuoteForm(),
                  ] else ...[
                    _buildMercadoPagoTestSection(currentUser != null),
                  ],
                  const SizedBox(height: 24),
                  _buildActionButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard() {
    final shippingCost = _currentCustomerShippingAmount;
    final totalAmount = _calculatedTotal;
    final hasSelectedRate = _selectedShippingRate != null;
    final shippingLabel = !hasSelectedRate
        ? (_fetchingShipping ? 'Recalculando...' : 'Calculando...')
        : (shippingCost == 0 ? 'GRATIS' : _formatCurrency(shippingCost));
    final totalLabel = hasSelectedRate
        ? _formatCurrency(totalAmount)
        : 'Calculando...';
    final totalTextColor = hasSelectedRate ? _kNavy : const Color(0xFF64748B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: _kPrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Resumen de compra',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Subtotal productos',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _formatCurrency(_displayProductSubtotal),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _kNavy,
                  ),
                ),
              ),
            ],
          ),
          if (_couponDiscountAmount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.confirmation_number_outlined,
                  size: 15,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Descuento de cupón',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '-${_formatCurrency(_couponDiscountAmount)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Envío seleccionado',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 12),
              hasSelectedRate && shippingCost == 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Text(
                        'GRATIS',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF15803D),
                          letterSpacing: 0.3,
                        ),
                      ),
                    )
                  : Flexible(
                      child: Text(
                        shippingLabel,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: hasSelectedRate
                              ? _kNavy
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Protección y garantía',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Incluida',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total a pagar',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _kNavy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'IVA incluido · Facturación disponible',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  totalLabel,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: hasSelectedRate ? 21 : 19,
                    fontWeight: FontWeight.w900,
                    color: totalTextColor,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShippingSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: _kPrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Método de entrega y paquetería',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_addresses.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedAddressId,
              isExpanded: true,
              decoration: _inputDecoration('Dirección de entrega').copyWith(
                prefixIcon: const Icon(
                  Icons.location_on_outlined,
                  color: _kPrimary,
                  size: 20,
                ),
              ),
              items: _addresses.map<DropdownMenuItem<String>>((addr) {
                String cleanAddr = (addr.address as String? ?? '').trim();
                if (cleanAddr.startsWith('Dirección:')) {
                  cleanAddr = cleanAddr.replaceFirst('Dirección:', '').trim();
                }
                final label = '${addr.label} · $cleanAddr';
                return DropdownMenuItem<String>(
                  value: addr.id as String,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (newId) {
                if (newId != null && newId != _selectedAddressId) {
                  setState(() => _selectedAddressId = newId);
                  _fetchQuoteForAddress(newId);
                }
              },
            ),
            const SizedBox(height: 14),
          ],
          if (_fetchingShipping) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      color: _kPrimary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Calculando opciones de envío en tiempo real...',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_shippingErrorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFF7ED),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: Color(0xFFD97706),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _shippingErrorTitle,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: _kNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _shippingErrorMessage!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF92400E),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Mercado Pago se habilitará cuando exista una opción de envío válida.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _fetchingShipping
                          ? null
                          : () => _fetchQuoteForAddress(_selectedAddressId),
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Reintentar cotización'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPrimary,
                        side: const BorderSide(color: _kPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_shippingQuoteResult != null) ...[
            if (_shippingQuoteResult!.freeShippingUnlocked) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Envío gratis aplicado en la opción económica.\nPuedes elegir un servicio más rápido pagando la diferencia.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF166534),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Column(
              children: _shippingQuoteResult!.rates.map((rate) {
                final isSelected = _selectedShippingRate?.rateId == rate.rateId;
                final isFree = rate.customerShippingAmount == 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFF0FDFA) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? _kPrimary : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.8 : 1.1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _kPrimary.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedShippingRate = rate),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? _kPrimary : Colors.white,
                                border: Border.all(
                                  color: isSelected
                                      ? _kPrimary
                                      : Colors.grey.shade400,
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Center(
                                      child: Icon(
                                        Icons.check,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _buildCarrierBadge(rate.carrier),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          rate.service,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: _kNavy,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        size: 14,
                                        color: isFree
                                            ? const Color(0xFF16A34A)
                                            : const Color(0xFF0D9488),
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          '${rate.days} ${rate.days == 1 ? "día hábil" : "días hábiles"} de entrega estimada',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            isFree
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF86EFAC),
                                      ),
                                    ),
                                    child: const Text(
                                      'GRATIS',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF15803D),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  )
                                : Text(
                                    rate.label,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: _kNavy,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCarrierBadge(String carrier) {
    Color bg;
    Color fg;
    final lower = carrier.toLowerCase();
    if (lower.contains('fedex')) {
      bg = const Color(0xFF4F46E5).withValues(alpha: 0.1);
      fg = const Color(0xFF4338CA);
    } else if (lower.contains('dhl')) {
      bg = const Color(0xFFD97706).withValues(alpha: 0.12);
      fg = const Color(0xFFB45309);
    } else if (lower.contains('estafeta')) {
      bg = const Color(0xFFDC2626).withValues(alpha: 0.1);
      fg = const Color(0xFFB91C1C);
    } else {
      bg = _kPrimary.withValues(alpha: 0.1);
      fg = _kPrimary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        carrier,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildTransactionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.tune_rounded, color: _kPrimary, size: 18),
            SizedBox(width: 6),
            Text(
              'Modalidad de compra',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: _kNavy,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _loading
                      ? null
                      : () => setState(() => _isQuote = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isQuote ? _kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: !_isQuote
                          ? [
                              BoxShadow(
                                color: _kPrimary.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.credit_card_rounded,
                          size: 16,
                          color: !_isQuote
                              ? Colors.white
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pago de prueba',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: !_isQuote
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _loading
                      ? null
                      : () => setState(() => _isQuote = true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isQuote ? _kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _isQuote
                          ? [
                              BoxShadow(
                                color: _kPrimary.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: _isQuote ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Solicitar cotización',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _isQuote
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMercadoPagoTestSection(bool isLoggedIn) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF009EE3).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.credit_card_rounded,
                      color: Color(0xFF009EE3),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mercado Pago Checkout Pro',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: _kNavy,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'Tarjetas · SPEI · Efectivo · Saldo MP',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          size: 12,
                          color: Color(0xFF1D4ED8),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Seguro',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _paymentMethodChip('Visa / Mastercard', Icons.credit_card),
                  _paymentMethodChip('AMEX', Icons.credit_score),
                  _paymentMethodChip(
                    'SPEI (Transferencia)',
                    Icons.account_balance,
                  ),
                  _paymentMethodChip('Efectivo (OXXO)', Icons.storefront),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Tu transacción está respaldada y protegida. Podrás elegir tu forma de pago favorita al continuar.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF99F6E4)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: Color(0xFF0D9488),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pago seguro con encriptación SSL de 256 bits y protección total al comprador.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: Color(0xFF115E59),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLoggedIn) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Debes iniciar sesión para realizar el pago.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentMethodChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notas para la cotización',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: _kNavy,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Comparte detalles adicionales para tu solicitud.',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final hasSelectedRate = _selectedShippingRate != null;
    final totalAmount = _calculatedTotal;
    final buttonText = _isQuote
        ? 'Solicitar cotización formal'
        : (hasSelectedRate
              ? 'Pagar ${_formatCurrency(totalAmount)}'
              : 'Continuar con Mercado Pago');

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isQuote
                ? (_loading ? null : _submit)
                : (_canSubmitPayment ? _submit : null),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade500,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isQuote
                            ? Icons.send_rounded
                            : Icons.lock_outline_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            buttonText,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 14, color: Color(0xFF94A3B8)),
            SizedBox(width: 5),
            Text(
              'Transacción 100% segura con encriptación SSL de 256 bits',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kPrimary, width: 1.5),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return formatFinancialPrice(amount);
  }
}
