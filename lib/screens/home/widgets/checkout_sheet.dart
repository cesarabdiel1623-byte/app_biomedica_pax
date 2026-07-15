import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/cart_service.dart';
import '../../../services/address_service.dart';
const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kGreen = Color(0xFF16A34A);
const _kBg = Color(0xFFF8FAFC);

class CheckoutSheet extends StatefulWidget {
  final double total;
  final VoidCallback onSuccess;
  const CheckoutSheet({super.key, required this.total, required this.onSuccess});

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  bool _isQuote = false;
  bool _requiresInvoice = false;
  bool _showSuccessAnimation = false;
  final _rfcController = TextEditingController();
  final _razonSocialController = TextEditingController();
  String _selectedCfdi = 'G03';

  final Map<String, String> _cfdiMap = {
    'G01': 'G01 - Adquisición de mercancías',
    'G03': 'G03 - Gastos en general',
    'I01': 'I01 - Construcciones',
    'I04': 'I04 - Equipo de cómputo',
    'D01': 'D01 - Honorarios médicos y dentales',
    'S01': 'S01 - Sin efectos fiscales',
    'P01': 'P01 - Por definir',
  };

  bool _isFinancing = false;
  int _selectedMonths = 3;
  String _paymentMethod = 'transfer';
  String _codiOption = 'mobile';
  bool _codiSimulatedPaid = false;
  bool _codiRequestSent = false;
  int _codiTimerSeconds = 120;
  Timer? _codiTimer;
  bool _loading = false;

  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();
  final _codiPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _codiPhoneController.dispose();
    _notesController.dispose();
    _rfcController.dispose();
    _razonSocialController.dispose();
    _codiTimer?.cancel();
    super.dispose();
  }

  void _startCodiTimer() {
    _codiTimer?.cancel();
    _codiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_codiTimerSeconds > 0) {
          _codiTimerSeconds--;
        } else {
          _codiRequestSent = false;
          timer.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La solicitud de cobro CoDi ha expirado. Por favor intenta de nuevo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    });
  }

  Future<void> _submit() async {
    if (_requiresInvoice) {
      final rfc = _rfcController.text.trim().toUpperCase();
      if (rfc.isEmpty) {
        _showError('Por favor ingresa tu RFC.');
        return;
      }
      if (rfc.length < 12 || rfc.length > 13) {
        _showError('El RFC debe tener entre 12 y 13 caracteres.');
        return;
      }
      if (_razonSocialController.text.trim().isEmpty) {
        _showError('Por favor ingresa la Razón Social.');
        return;
      }
    }

    if (!_isQuote) {
      if (_paymentMethod == 'card') {
        final cardNo = _cardNumberController.text.replaceAll(' ', '');
        if (cardNo.length < 15 || cardNo.length > 16) {
          _showError('Por favor ingresa un número de tarjeta válido.');
          return;
        }
        if (_cardHolderController.text.trim().isEmpty) {
          _showError('Por favor ingresa el nombre del titular.');
          return;
        }
        if (_cardExpiryController.text.trim().length != 5) {
          _showError('Por favor ingresa una fecha de expiración válida (MM/YY).');
          return;
        }
        if (_cardCvvController.text.trim().length < 3) {
          _showError('Por favor ingresa un CVV válido.');
          return;
        }
      } else if (_paymentMethod == 'codi') {
        if (_codiOption == 'mobile') {
          if (_codiPhoneController.text.length != 10) {
            _showError('Por favor ingresa un número de celular de 10 dígitos.');
            return;
          }
          if (!_codiSimulatedPaid) {
            _showError('Por favor simula la aprobación del pago CoDi en tu celular antes de confirmar.');
            return;
          }
        } else {
          if (!_codiSimulatedPaid) {
            _showError('Por favor simula el escaneo del código QR CoDi antes de confirmar.');
            return;
          }
        }
      }
    }

    setState(() => _loading = true);

    try {
      if (_isQuote) {
        final notesText = _notesController.text.trim();
        final quoteId = await CartService.requestQuote(notes: notesText);

        try {
          final addr = await AddressService.getDefaultAddress();
          final Map<String, dynamic> updateFields = {
            if (addr != null) 'shipping_address': addr.address,
            'billing_requested': _requiresInvoice,
            if (_requiresInvoice) ...{
              'rfc': _rfcController.text.trim().toUpperCase(),
              'razon_social': _razonSocialController.text.trim(),
              'cfdi_use': _selectedCfdi,
            }
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
          debugPrint('Aviso al guardar la dirección/facturación de la cotización: $quoteErr');
        }

        if (mounted) {
          setState(() {
            _loading = false;
            _showSuccessAnimation = true;
          });
          HapticFeedback.lightImpact();
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
            widget.onSuccess();

            showDialog(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: _kPrimary, size: 28),
                    SizedBox(width: 10),
                    Text('¡Cotización Solicitada!', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: const Text(
                  'Tu solicitud de cotización ha sido generada con éxito.\n\nEl área administrativa la revisará y recibirás una notificación cuando sea enviada/aprobada.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Aceptar', style: TextStyle(color: _kPrimary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        String finalMethod = '';
        String cardEnding = '';
        if (_isFinancing) {
          finalMethod = 'Financiamiento ($_selectedMonths Meses) - ';
        } else {
          finalMethod = 'Contado - ';
        }

        if (_paymentMethod == 'transfer') {
          finalMethod += 'SPEI';
        } else if (_paymentMethod == 'codi') {
          finalMethod += 'CoDi (${_codiOption == 'mobile' ? 'Celular' : 'QR'})';
        } else if (_paymentMethod == 'card') {
          finalMethod += 'Tarjeta';
          final rawNo = _cardNumberController.text.replaceAll(' ', '');
          cardEnding = ' [Tarjeta terminación: **** ${rawNo.substring(rawNo.length - 4)}]';
        } else if (_paymentMethod == 'cash') {
          finalMethod += 'Efectivo';
        } else {
          finalMethod += 'Otro';
        }

        final notesBuf = StringBuffer();
        notesBuf.write('Método de pago seleccionado: $finalMethod.');
        if (_notesController.text.trim().isNotEmpty) {
          notesBuf.write(' Notas: ${_notesController.text.trim()}');
        }
        if (cardEnding.isNotEmpty) {
          notesBuf.write(' $cardEnding');
        }
        if (_paymentMethod == 'codi' && _codiOption == 'mobile') {
          notesBuf.write(' [CoDi Móvil: ${_codiPhoneController.text}]');
        }

        String dbPaymentMethod = 'other';
        if (_isFinancing) {
          dbPaymentMethod = 'financial';
        } else {
          if (_paymentMethod == 'transfer') {
            dbPaymentMethod = 'spei';
          } else if (_paymentMethod == 'card') {
            dbPaymentMethod = 'card';
          } else if (_paymentMethod == 'cash') {
            dbPaymentMethod = 'cash';
          } else if (_paymentMethod == 'codi') {
            dbPaymentMethod = 'spei';
          }
        }

        final orderId = await CartService.checkout(
          paymentMethod: dbPaymentMethod,
          notes: notesBuf.toString(),
        );

        try {
          final addr = await AddressService.getDefaultAddress();
          final Map<String, dynamic> updateFields = {
            if (addr != null) 'shipping_address': addr.address,
            'billing_requested': _requiresInvoice,
            if (_requiresInvoice) ...{
              'rfc': _rfcController.text.trim().toUpperCase(),
              'razon_social': _razonSocialController.text.trim(),
              'cfdi_use': _selectedCfdi,
            }
          };

          if (addr == null) {
            final list = await AddressService.getAddresses();
            if (list.isNotEmpty) {
              updateFields['shipping_address'] = list.first.address;
            }
          }

          await Supabase.instance.client
              .from('orders')
              .update(updateFields)
              .eq('id', orderId);
        } catch (addrErr) {
          debugPrint('Aviso al guardar la dirección/facturación del pedido: $addrErr');
        }

        if (mounted) {
          setState(() {
            _loading = false;
            _showSuccessAnimation = true;
          });
          HapticFeedback.lightImpact();
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
            widget.onSuccess();

            showDialog(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: _kPrimary, size: 28),
                    SizedBox(width: 10),
                    Text('¡Compra Exitosa!', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Text(
                  'Tu orden de compra ha sido generada bajo la modalidad de $finalMethod y el stock de los productos se ha actualizado en tiempo real.\n\nRecibirás una notificación con los detalles de tu compra.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                    },
                    child: const Text('Aceptar', style: TextStyle(color: _kPrimary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final errMsg = e.toString().replaceAll('Exception: ', '');
        _showError('Error al procesar la solicitud: $errMsg');
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

  @override
  Widget build(BuildContext context) {
    if (_showSuccessAnimation) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.45,
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SuccessCheckmark(),
              SizedBox(height: 24),
              Text(
                '¡Pago Confirmado!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Tu compra se ha procesado con éxito.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
              padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Confirmar Compra', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kNavy)),
                          const SizedBox(height: 2),
                          Text('Finaliza tu pedido seleccionando tus opciones de pago.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 16),

                  Container(
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total a Pagar:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kNavy)),
                        Text(
                          _formatCurrency(widget.total),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Tipo de Transacción', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
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
                            onTap: _loading ? null : () => setState(() => _isQuote = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !_isQuote ? _kPrimary : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Pedido de Compra',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: !_isQuote ? Colors.white : Colors.grey.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: _loading ? null : () => setState(() => _isQuote = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _isQuote ? _kPrimary : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Solicitar Cotización',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _isQuote ? Colors.white : Colors.grey.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (!_isQuote) ...[
                    const Text('Modelo de Pago *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
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
                              onTap: _loading ? null : () => setState(() => _isFinancing = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !_isFinancing ? _kPrimary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Pago de Contado',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: !_isFinancing ? Colors.white : Colors.grey.shade700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: _loading ? null : () => setState(() => _isFinancing = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _isFinancing ? _kPrimary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Financiamiento (Plazos)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _isFinancing ? Colors.white : Colors.grey.shade700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_isFinancing) ...[
                      const Text('Selecciona el plazo de Financiamiento *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildTermCard(3, 'Sin Intereses')),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTermCard(6, 'Sin Intereses')),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTermCard(12, '10% de Interés')),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Text('Selecciona el Método de Pago *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy)),
                    const SizedBox(height: 8),
                    _buildPaymentMethodsGrid(),
                    const SizedBox(height: 20),

                    if (_paymentMethod == 'transfer')
                      _buildSpeiFlow()
                    else if (_paymentMethod == 'codi') ...[
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _codiOption = 'mobile';
                                  _codiSimulatedPaid = false;
                                  _codiRequestSent = false;
                                  _codiTimer?.cancel();
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _codiOption == 'mobile' ? _kPrimary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'CoDi Móvil (Celular)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _codiOption == 'mobile' ? Colors.white : Colors.grey.shade700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _codiOption = 'qr';
                                  _codiSimulatedPaid = false;
                                  _codiRequestSent = false;
                                  _codiTimer?.cancel();
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _codiOption == 'qr' ? _kPrimary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Código QR CoDi',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _codiOption == 'qr' ? Colors.white : Colors.grey.shade700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_codiOption == 'mobile')
                        _buildCodiMobileFlow()
                      else
                        _buildCodiQrMock(),
                    ] else if (_paymentMethod == 'card')
                      _buildCardFlow()
                    else if (_paymentMethod == 'cash')
                      _buildCashFlow(),
                    const SizedBox(height: 20),
                  ],

                  const Divider(height: 32),
                  SwitchListTile(
                    title: const Text(
                      '¿Requiere factura fiscal?',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _kNavy),
                    ),
                    subtitle: const Text(
                      'Se emitirá factura CFDI en México',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    value: _requiresInvoice,
                    activeThumbColor: _kPrimary,
                    onChanged: (val) {
                      setState(() => _requiresInvoice = val);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_requiresInvoice) ...[
                    const SizedBox(height: 12),
                    const Text('RFC *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kNavy)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _rfcController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 13,
                      enabled: !_loading,
                      decoration: InputDecoration(
                        hintText: 'ABCD123456XX0 o ABC123456XX0',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        counterText: '',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Razón Social *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kNavy)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _razonSocialController,
                      enabled: !_loading,
                      decoration: InputDecoration(
                        hintText: 'Nombre de la persona o empresa',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Uso de CFDI *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kNavy)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCfdi,
                          isExpanded: true,
                          onChanged: _loading
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() => _selectedCfdi = val);
                                  }
                                },
                          items: _cfdiMap.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                style: const TextStyle(fontSize: 13, color: _kNavy),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  Text(
                    _isQuote ? 'Notas / Instrucciones Especiales' : 'Notas / Instrucciones de Entrega',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      hintText: _isQuote
                          ? 'Ej. Solicito entrega inmediata, o color específico.'
                          : 'Ej. Entregar por la mañana, o requiere facturar.',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _isQuote ? 'Solicitar Cotización' : 'Confirmar y Comprar',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermCard(int months, String subtitle) {
    final isSelected = _selectedMonths == months;
    double adjustedTotal = widget.total;
    if (months == 12) {
      adjustedTotal = widget.total * 1.10;
    }
    final monthlyAmount = adjustedTotal / months;

    return GestureDetector(
      onTap: _loading ? null : () => setState(() => _selectedMonths = months),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _kPrimary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kPrimary.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Column(
          children: [
            Text(
              '$months Meses',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? _kPrimary : _kNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatCurrency(monthlyAmount),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? _kPrimary : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9,
                color: isSelected ? _kPrimary : Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildPaymentMethodCard('transfer', 'SPEI / Transf.', Icons.account_balance)),
            const SizedBox(width: 12),
            Expanded(child: _buildPaymentMethodCard('codi', 'CoDi Móvil / QR', Icons.qr_code_scanner)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildPaymentMethodCard('card', 'Tarjeta Créd/Déb', Icons.credit_card)),
            const SizedBox(width: 12),
            Expanded(child: _buildPaymentMethodCard('cash', 'Efectivo / Entrega', Icons.local_shipping)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(String value, String label, IconData icon) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: _loading ? null : () {
        setState(() {
          _paymentMethod = value;
          _codiRequestSent = false;
          _codiSimulatedPaid = false;
          _codiTimer?.cancel();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kPrimary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kPrimary.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? _kPrimary : Colors.grey.shade600, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? _kPrimary : Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeiFlow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance, color: _kPrimary, size: 20),
              SizedBox(width: 8),
              Text(
                'Datos para Transferencia SPEI',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14),
              ),
            ],
          ),
          const Divider(height: 20),
          _buildSpeiRow('Banco:', 'STP (Sistema de Transferencias y Pagos)'),
          _buildSpeiRow('Beneficiario:', 'Go Medical S.A. de C.V.'),
          Row(
            children: [
              Expanded(
                child: _buildSpeiRow('CLABE:', '6461 8000 1234 5678 90'),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: _kPrimary, size: 18),
                tooltip: 'Copiar CLABE',
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: '646180001234567890'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('CLABE copiada al portapapeles'),
                      duration: Duration(seconds: 2),
                      backgroundColor: _kPrimary,
                    ),
                  );
                },
              ),
            ],
          ),
          _buildSpeiRow('Referencia:', 'GOMED-CHECKOUT'),
          const SizedBox(height: 10),
          const Text(
            '* Tu orden será revisada por nuestro equipo una vez que se detecte la transferencia. La verificación suele tomar menos de 10 minutos.',
            style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeiRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          children: [
            TextSpan(text: '$label ', style: const TextStyle(fontWeight: FontWeight.bold, color: _kNavy)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildCodiQrMock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: 160,
            height: 160,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: CustomPaint(
              size: const Size(140, 140),
              painter: _QrPainter(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner, color: _kPrimary, size: 16),
              const SizedBox(width: 6),
              Text(
                _codiSimulatedPaid ? '¡Pago detectado con éxito!' : 'Esperando escaneo de código...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _codiSimulatedPaid ? _kGreen : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_codiSimulatedPaid)
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _codiSimulatedPaid = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Simulación: Código QR escaneado y pagado'),
                    backgroundColor: _kGreen,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary.withValues(alpha: 0.1),
                foregroundColor: _kPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Simular Escaneo CoDi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            )
          else
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: _kGreen, size: 20),
                SizedBox(width: 6),
                Text('Pago Confirmado', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCodiMobileFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingresa el número celular asociado a tu cuenta CoDi / App Bancaria para recibir la solicitud de cobro de inmediato.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _codiPhoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          enabled: !_codiRequestSent && !_loading,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Número de Celular (10 dígitos)',
            prefixIcon: const Icon(Icons.phone_android),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            fillColor: Colors.white,
            filled: true,
          ),
        ),
        const SizedBox(height: 12),
        if (!_codiRequestSent)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final phone = _codiPhoneController.text.trim();
                if (phone.length != 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa un número celular de 10 dígitos'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                setState(() {
                  _codiRequestSent = true;
                  _codiTimerSeconds = 120;
                  _codiSimulatedPaid = false;
                });
                _startCodiTimer();
              },
              icon: const Icon(Icons.send_to_mobile),
              label: const Text('Enviar Solicitud de Cobro'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_codiSimulatedPaid)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                      ),
                    const SizedBox(width: 10),
                    Text(
                      _codiSimulatedPaid 
                          ? '¡Pago CoDi recibido y confirmado!'
                          : 'Esperando pago en tu app... (0${_codiTimerSeconds ~/ 60}:${(_codiTimerSeconds % 60).toString().padLeft(2, '0')})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_codiSimulatedPaid)
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _codiSimulatedPaid = true;
                        _codiTimer?.cancel();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Simulación: Solicitud de cobro CoDi aprobada en banco'),
                          backgroundColor: _kGreen,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary.withValues(alpha: 0.1),
                      foregroundColor: _kPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Simular Aprobación Bancaria', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                else
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: _kGreen, size: 20),
                      SizedBox(width: 6),
                      Text('Pago Confirmado', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _codiRequestSent = false;
                  _codiTimer?.cancel();
                });
              },
              child: const Text('Reingresar número o cambiar método', style: TextStyle(fontSize: 11, color: Colors.black45)),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildCardFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVirtualCard(),
        const SizedBox(height: 20),
        const Text(
          'Datos de la Tarjeta',
          style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cardNumberController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _CardNumberFormatter(),
          ],
          decoration: InputDecoration(
            labelText: 'Número de Tarjeta',
            prefixIcon: const Icon(Icons.credit_card),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            fillColor: Colors.white,
            filled: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cardHolderController,
          keyboardType: TextInputType.name,
          decoration: InputDecoration(
            labelText: 'Nombre del Titular',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            fillColor: Colors.white,
            filled: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _cardExpiryController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _CardExpiryFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'Expiración (MM/YY)',
                  prefixIcon: const Icon(Icons.calendar_today),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  fillColor: Colors.white,
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _cardCvvController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'CVV',
                  prefixIcon: const Icon(Icons.lock),
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  fillColor: Colors.white,
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVirtualCard() {
    final numStr = _cardNumberController.text.isEmpty ? '•••• •••• •••• ••••' : _cardNumberController.text;
    final holderStr = _cardHolderController.text.isEmpty ? 'NOMBRE DEL TITULAR' : _cardHolderController.text.toUpperCase();
    final expiryStr = _cardExpiryController.text.isEmpty ? 'MM/YY' : _cardExpiryController.text;
    final cvvStr = _cardCvvController.text.isEmpty ? '•••' : _cardCvvController.text;

    final isVisa = _cardNumberController.text.startsWith('4');
    final isMastercard = _cardNumberController.text.startsWith('5');

    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E3A5F),
            Color(0xFF0D9488),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  children: [
                    Positioned(left: 10, top: 0, bottom: 0, child: VerticalDivider(color: Colors.black26, width: 1)),
                    Positioned(left: 20, top: 0, bottom: 0, child: VerticalDivider(color: Colors.black26, width: 1)),
                    Positioned(left: 30, top: 0, bottom: 0, child: VerticalDivider(color: Colors.black26, width: 1)),
                    Positioned(top: 10, left: 0, right: 0, child: Divider(color: Colors.black26, height: 1)),
                    Positioned(top: 20, left: 0, right: 0, child: Divider(color: Colors.black26, height: 1)),
                  ],
                ),
              ),
              Text(
                isVisa ? 'VISA' : (isMastercard ? 'mastercard' : 'CREDIT CARD'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ],
          ),
          Text(
            numStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TITULAR', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      holderStr,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('EXPIRA', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    expiryStr,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('CVV', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    cvvStr,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashFlow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping, color: _kPrimary, size: 20),
              SizedBox(width: 8),
              Text(
                'Pago Contra Entrega / Efectivo',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy, fontSize: 14),
              ),
            ],
          ),
          Divider(height: 20),
          Text(
            '• Puedes pagar en efectivo o con tarjeta al momento de recibir tus productos.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 6),
          Text(
            '• Nuestros choferes y repartidores cuentan con terminal móvil bancaria.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 6),
          Text(
            '• Si pagas en efectivo, por favor ten listo el importe exacto para agilizar la entrega.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '\$$buf.${parts[1]} MXN';
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(' ', '');
    if (text.length > 16) text = text.substring(0, 16);
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll('/', '');
    if (text.length > 4) text = text.substring(0, 4);
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(text[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87;
    final double finderSize = size.width * 0.25;

    _drawFinderPattern(canvas, const Offset(0, 0), finderSize, paint);
    _drawFinderPattern(canvas, Offset(size.width - finderSize, 0), finderSize, paint);
    _drawFinderPattern(canvas, Offset(0, size.height - finderSize), finderSize, paint);

    final randPattern = [
      [1,0,1,1,0,1,0,1,1,0],
      [0,1,0,0,1,0,1,0,0,1],
      [1,1,0,1,1,0,0,1,1,0],
      [0,0,1,0,0,1,1,0,0,1],
      [1,0,1,1,0,1,0,1,1,0],
      [0,1,0,0,1,0,1,0,0,1],
      [1,1,0,1,1,0,0,1,1,0],
      [0,0,1,0,0,1,1,0,0,1],
      [1,0,1,1,0,1,0,1,1,0],
      [0,1,0,0,1,0,1,0,0,1],
    ];

    final blockSize = size.width / 14;
    final startOffset = finderSize + blockSize;

    for (int r = 0; r < randPattern.length; r++) {
      for (int c = 0; c < randPattern[r].length; c++) {
        if (randPattern[r][c] == 1) {
          canvas.drawRect(
            Rect.fromLTWH(
              startOffset + c * blockSize,
              startOffset + r * blockSize,
              blockSize - 1,
              blockSize - 1,
            ),
            paint,
          );
        }
      }
    }

    for (double x = finderSize + blockSize; x < size.width - finderSize - blockSize; x += blockSize * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, blockSize, blockSize), paint);
      canvas.drawRect(Rect.fromLTWH(0, x, blockSize, blockSize), paint);
    }
  }

  void _drawFinderPattern(Canvas canvas, Offset offset, double size, Paint paint) {
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, size, size), paint);
    final whitePaint = Paint()..color = Colors.white;
    final double innerWhiteStart = size * 0.15;
    final double innerWhiteSize = size * 0.7;
    canvas.drawRect(
      Rect.fromLTWH(offset.dx + innerWhiteStart, offset.dy + innerWhiteStart, innerWhiteSize, innerWhiteSize),
      whitePaint,
    );
    final double innerBlackStart = size * 0.3;
    final double innerBlackSize = size * 0.4;
    canvas.drawRect(
      Rect.fromLTWH(offset.dx + innerBlackStart, offset.dy + innerBlackStart, innerBlackSize, innerBlackSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SuccessCheckmark extends StatefulWidget {
  const SuccessCheckmark({super.key});

  @override
  State<SuccessCheckmark> createState() => _SuccessCheckmarkState();
}

class _SuccessCheckmarkState extends State<SuccessCheckmark> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );

    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeInOutBack),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(100, 100),
          painter: SuccessCheckmarkPainter(
            scale: _scaleAnimation.value,
            checkProgress: _checkAnimation.value,
          ),
        );
      },
    );
  }
}

class SuccessCheckmarkPainter extends CustomPainter {
  final double scale;
  final double checkProgress;

  SuccessCheckmarkPainter({required this.scale, required this.checkProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * 0.9 * scale;

    if (radius <= 0) return;

    final bgPaint = Paint()
      ..color = const Color(0xFF0D9488)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    if (checkProgress > 0) {
      final checkPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round;

      final path = Path();
      
      final start = Offset(size.width * 0.32, size.height * 0.5);
      final mid = Offset(size.width * 0.46, size.height * 0.64);
      final end = Offset(size.width * 0.68, size.height * 0.36);

      path.moveTo(start.dx, start.dy);
      path.lineTo(mid.dx, mid.dy);
      path.lineTo(end.dx, end.dy);

      final pathMetrics = path.computeMetrics();
      final finalPath = Path();
      for (final metric in pathMetrics) {
        final extract = metric.extractPath(0.0, metric.length * checkProgress);
        finalPath.addPath(extract, Offset.zero);
      }

      canvas.drawPath(finalPath, checkPaint);
    }
  }

  @override
  bool shouldRepaint(SuccessCheckmarkPainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.checkProgress != checkProgress;
  }
}
