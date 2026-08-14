import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/address_service.dart';
import '../../../services/cart_service.dart';
import '../../../services/mercado_pago_test_service.dart';
import '../../../services/shipping_quote_service.dart';
import '../../../utils/price_formatter.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kBg = Color(0xFFF8FAFC);

class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({
    super.key,
    required this.cartId,
    required this.subtotal,
    required this.total,
    required this.onSuccess,
    this.cartPricingAmounts,
  });

  final String cartId;
  final double subtotal;
  final double total;
  final VoidCallback onSuccess;
  final CartPricingAmounts? cartPricingAmounts;

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

      await _fetchQuoteForAddress(_selectedAddressId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _shippingErrorMessage =
              'No se pudo cargar la dirección ni cotizar el envío.';
          _fetchingShipping = false;
        });
      }
    }
  }

  Future<void> _fetchQuoteForAddress(String? addressId) async {
    if (widget.cartId.isEmpty) {
      setState(() => _fetchingShipping = false);
      return;
    }

    setState(() {
      _fetchingShipping = true;
      _shippingErrorMessage = null;
      _shippingQuoteResult = null;
      _selectedShippingRate = null;
    });

    try {
      final result = await ShippingQuoteService.fetchQuote(
        cartId: widget.cartId,
        addressId: addressId,
      );

      if (!mounted) return;

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
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        setState(() {
          _shippingErrorMessage = msg;
          _fetchingShipping = false;
        });
      }
    }
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

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Revisar pedido',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _kNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isQuote
                                ? 'Completa tus datos para solicitar la cotización.'
                                : 'Prueba técnica de pago con Mercado Pago.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
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
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isQuote
                          ? (_loading ? null : _submit)
                          : (_canSubmitPayment ? _submit : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: const StadiumBorder(),
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
                          : Text(
                              _isQuote
                                  ? 'Solicitar cotización'
                                  : 'Continuar con Mercado Pago - Prueba',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
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
        ? (_fetchingShipping ? 'Calculando...' : 'Por calcular')
        : (shippingCost == 0 ? 'GRATIS' : _formatCurrency(shippingCost));
    final totalLabel = hasSelectedRate
        ? _formatCurrency(totalAmount)
        : 'Por calcular';
    final totalTextColor = hasSelectedRate
        ? _kPrimary
        : const Color(0xFF64748B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Subtotal productos:',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              Text(
                _formatCurrency(_displayProductSubtotal),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_couponDiscountAmount > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Descuento de cupón:',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                Text(
                  '-${_formatCurrency(_couponDiscountAmount)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Envío seleccionado:',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              Text(
                shippingLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: hasSelectedRate && shippingCost == 0
                      ? _kPrimary
                      : _kNavy,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total a pagar:',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              Text(
                totalLabel,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: totalTextColor,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.local_shipping, color: _kPrimary, size: 20),
              SizedBox(width: 8),
              Text(
                'Opciones de Envío (SkyDropX)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_addresses.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedAddressId,
              isExpanded: true,
              decoration: _inputDecoration('Dirección de entrega'),
              items: _addresses.map<DropdownMenuItem<String>>((addr) {
                final label = '${addr.label} - ${addr.address}';
                return DropdownMenuItem<String>(
                  value: addr.id as String,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
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
            const SizedBox(height: 12),
          ],
          if (_fetchingShipping) ...[
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kPrimary,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Calculando opciones de envío...',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ] else if (_shippingErrorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFDC2626),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _shippingErrorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF991B1B),
                        height: 1.35,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Text(
                  '✓ Envío gratis aplicado con la opción más económica.\nPuedes elegir un servicio más rápido pagando la diferencia.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF166534),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            Column(
              children: _shippingQuoteResult!.rates.map((rate) {
                final isSelected = _selectedShippingRate?.rateId == rate.rateId;

                return InkWell(
                  onTap: () => setState(() => _selectedShippingRate = rate),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF0FDFA)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? _kPrimary : const Color(0xFFCBD5E1),
                        width: isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // ignore: deprecated_member_use
                        Radio<String>(
                          value: rate.rateId,
                          // ignore: deprecated_member_use
                          groupValue: _selectedShippingRate?.rateId,
                          activeColor: _kPrimary,
                          // ignore: deprecated_member_use
                          onChanged: (_) =>
                              setState(() => _selectedShippingRate = rate),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${rate.carrier} · ${rate.service}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _kNavy,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${rate.days} días de entrega estimada',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          rate.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: rate.customerShippingAmount == 0
                                ? _kPrimary
                                : _kNavy,
                          ),
                        ),
                      ],
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

  Widget _buildTransactionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de transacción',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: _kNavy,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _loading
                      ? null
                      : () => setState(() => _isQuote = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isQuote ? _kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Pago de prueba',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: !_isQuote ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _loading
                      ? null
                      : () => setState(() => _isQuote = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isQuote ? _kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Solicitar cotización',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _isQuote ? Colors.white : Colors.grey.shade700,
                      ),
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.payments_rounded, color: _kPrimary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mercado Pago Checkout Pro - Prueba',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Esta es una prueba técnica de Mercado Pago. No genera un pedido real y no modifica el inventario.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFEFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'El importe final se valida de forma segura en el servidor con los productos y la opción de envío seleccionada.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFF155E75),
                  ),
                ),
              ),
              if (!isLoggedIn) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Debes iniciar sesión para realizar el pago de prueba.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuoteForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notas para la cotización',
          style: TextStyle(
            fontSize: 13,
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
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return formatFinancialPrice(amount);
  }
}
