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
  const CheckoutSheet({
    super.key,
    required this.total,
    required this.onSuccess,
  });

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
  bool _loading = false;

  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    _rfcController.dispose();
    _razonSocialController.dispose();
    super.dispose();
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
            },
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
          debugPrint(
            'Aviso al guardar la dirección/facturación de la cotización: $quoteErr',
          );
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
                  'Tu solicitud de cotización ha sido generada con éxito.\n\nEl área administrativa la revisará y recibirás una notificación cuando sea enviada/aprobada.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text(
                      'Aceptar',
                      style: TextStyle(
                        color: _kPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        String finalMethod = '';
        if (_isFinancing) {
          finalMethod = 'Financiamiento ($_selectedMonths Meses) - ';
        } else {
          finalMethod = 'Contado - ';
        }

        if (_paymentMethod == 'transfer') {
          finalMethod += 'SPEI';
        } else if (_paymentMethod == 'cash') {
          finalMethod += 'Pago contra entrega';
        } else {
          finalMethod += 'Otro';
        }

        final notesBuf = StringBuffer();
        notesBuf.write('Método de pago solicitado: $finalMethod.');
        if (_notesController.text.trim().isNotEmpty) {
          notesBuf.write(' Notas: ${_notesController.text.trim()}');
        }

        String dbPaymentMethod = 'other';
        if (_isFinancing) {
          dbPaymentMethod = 'financial';
        } else {
          if (_paymentMethod == 'transfer') {
            dbPaymentMethod = 'spei';
          } else if (_paymentMethod == 'cash') {
            dbPaymentMethod = 'cash';
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
            },
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
          debugPrint(
            'Aviso al guardar la dirección/facturación del pedido: $addrErr',
          );
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: _kPrimary, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'Orden generada',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                content: Text(
                  'Tu orden fue enviada bajo la modalidad de $finalMethod.\n\nTe notificaremos el seguimiento de pago y entrega.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                    },
                    child: const Text(
                      'Aceptar',
                      style: TextStyle(
                        color: _kPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
        _showError('Error al procesar la compra: $errMsg');
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
                'Orden enviada',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Gracias por tu compra.',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
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
                            'Completa tus datos para finalizar la compra.',
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
                        const Text(
                          'Total a Pagar:',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _kNavy,
                          ),
                        ),
                        Text(
                          _formatCurrency(widget.total),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _kPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Tipo de Transacción',
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
                                color: !_isQuote
                                    ? _kPrimary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Pedido de Compra',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: !_isQuote
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                ),
                                textAlign: TextAlign.center,
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
                                color: _isQuote
                                    ? _kPrimary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Solicitar Cotización',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _isQuote
                                      ? Colors.white
                                      : Colors.grey.shade700,
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
                    const Text(
                      'Modelo de Pago *',
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
                                  : () => setState(() => _isFinancing = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: !_isFinancing
                                      ? _kPrimary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Pago de Contado',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: !_isFinancing
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: _loading
                                  ? null
                                  : () => setState(() => _isFinancing = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _isFinancing
                                      ? _kPrimary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Financiamiento (Plazos)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _isFinancing
                                        ? Colors.white
                                        : Colors.grey.shade700,
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
                      const Text(
                        'Selecciona el plazo de Financiamiento *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _kNavy,
                        ),
                      ),
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

                    const Text(
                      'Selecciona el metodo de pago solicitado *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPaymentMethodsGrid(),
                    const SizedBox(height: 20),

                    if (_paymentMethod == 'transfer')
                      _buildSpeiFlow()
                    else if (_paymentMethod == 'cash')
                      _buildCashFlow(),
                    const SizedBox(height: 20),
                  ],

                  const Divider(height: 32),
                  SwitchListTile(
                    title: const Text(
                      '¿Requiere factura fiscal?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                      ),
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
                    const Text(
                      'RFC *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _rfcController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 13,
                      enabled: !_loading,
                      decoration: InputDecoration(
                        hintText: 'ABCD123456XX0 o ABC123456XX0',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Razón Social *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _razonSocialController,
                      enabled: !_loading,
                      decoration: InputDecoration(
                        hintText: 'Nombre de la persona o empresa',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Uso de CFDI *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kNavy,
                      ),
                    ),
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
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _kNavy,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  Text(
                    _isQuote
                        ? 'Notas / Instrucciones Especiales'
                        : 'Notas / Instrucciones de Entrega',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kNavy,
                    ),
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
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _isQuote
                                  ? 'Solicitar Cotización'
                                  : 'Confirmar compra',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
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
                  ),
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
    return Row(
      children: [
        Expanded(
          child: _buildPaymentMethodCard(
            'transfer',
            'SPEI / Transferencia',
            Icons.account_balance,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPaymentMethodCard(
            'cash',
            'Contra entrega',
            Icons.local_shipping,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(String value, String label, IconData icon) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: _loading
          ? null
          : () {
              setState(() {
                _paymentMethod = value;
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
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? _kPrimary : Colors.grey.shade600,
              size: 24,
            ),
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                  fontSize: 14,
                ),
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
                  Clipboard.setData(
                    const ClipboardData(text: '646180001234567890'),
                  );
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
            '* Tu orden se procesa una vez que se detecte la transferencia. La verificación suele tomar menos de 10 minutos.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black54,
              fontStyle: FontStyle.italic,
            ),
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
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
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
                'Pago contra entrega',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Divider(height: 20),
          Text(
            '• Nuestro equipo coordinará contigo la forma de pago al momento de la entrega.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 6),
          Text(
            '• Los tiempos de entrega pueden variar según cobertura y método de pago.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 6),
          Text(
            '• Recibirás indicaciones por notificación o contacto de seguimiento.',
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

class SuccessCheckmark extends StatefulWidget {
  const SuccessCheckmark({super.key});

  @override
  State<SuccessCheckmark> createState() => _SuccessCheckmarkState();
}

class _SuccessCheckmarkState extends State<SuccessCheckmark>
    with SingleTickerProviderStateMixin {
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
    return oldDelegate.scale != scale ||
        oldDelegate.checkProgress != checkProgress;
  }
}
