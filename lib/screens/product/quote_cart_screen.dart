import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/product.dart';
import '../../models/quote_item.dart';
import '../../services/quote_service.dart';
import 'product_detail_screen.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFEF4444);
const _kBg = Color(0xFFF8FAFC);

class QuoteCartScreen extends StatefulWidget {
  const QuoteCartScreen({super.key});

  @override
  State<QuoteCartScreen> createState() => _QuoteCartScreenState();
}

class _QuoteCartScreenState extends State<QuoteCartScreen> {
  List<QuoteItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await QuoteService.getQuoteItems();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  double get _estimatedSubtotal => _items.fold(0.0, (s, i) => s + ((i.product?.unitPriceMxn ?? 0.0) * i.quantity));
  int get _totalQty => _items.fold(0, (s, i) => s + i.quantity);

  String _fmt(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '\$$buf.${parts[1]}';
  }

  void _showFormBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuoteFormSheet(
        itemsCount: _totalQty,
        onSuccess: (requestNumber) {
          if (mounted) {
            setState(() {
              _items = [];
            });
            _showSuccessDialog(requestNumber);
          }
        },
      ),
    );
  }

  void _showSuccessDialog(String requestNumber) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: _kGreen,
                  size: 54,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '¡Solicitud Enviada!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Hemos recibido tu solicitud de cotización comercial.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _kBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  'Folio: $requestNumber',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: _kNavy,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Nuestro equipo de ejecutivos de Biomedica Pax la revisará y te enviará una propuesta formal por correo electrónico a la brevedad.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close dialog
                    Navigator.pop(context); // Return to home/previous page
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Entendido',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Bolsa de Cotización',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _items.isEmpty
              ? _buildEmptyState()
              : _buildCartContent(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.request_quote_outlined,
                size: 64,
                color: _kPrimary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tu bolsa de cotizaciones está vacía',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega equipos médicos o consumibles desde el catálogo para solicitar una cotización formal.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('Explorar Catálogo', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartContent() {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: _kPrimary,
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _buildItemCard(item);
              },
            ),
          ),
        ),
        _buildBottomSummary(),
      ],
    );
  }

  Widget _buildItemCard(QuoteItem item) {
    final p = item.product!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: p.id)),
            ).then((_) => _load()),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 70,
                height: 70,
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.all(4),
                child: p.mainImageUrl != null && p.mainImageUrl!.isNotEmpty
                    ? Image.network(p.mainImageUrl!, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.medical_services, color: Colors.grey))
                    : const Icon(Icons.medical_services, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: _kNavy),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (p.sku.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('SKU: ${p.sku}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmt(p.unitPriceMxn),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _kPrimary),
                        ),
                        Text('Precio unitario estimado', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                      ],
                    ),
                    // Quantity control
                    Row(
                      children: [
                        _qtyBtn(Icons.remove, () async {
                          if (item.quantity > 1) {
                            setState(() {
                              item.quantity--;
                            });
                            await QuoteService.updateQuantity(p.id, item.quantity);
                          } else {
                            _confirmRemove(p);
                          }
                        }),
                        Container(
                          width: 32,
                          alignment: Alignment.center,
                          child: Text(
                            '${item.quantity}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kNavy),
                          ),
                        ),
                        _qtyBtn(Icons.add, () async {
                          setState(() {
                            item.quantity++;
                          });
                          await QuoteService.updateQuantity(p.id, item.quantity);
                        }),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Remove button
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
            onPressed: () => _confirmRemove(p),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, size: 14, color: _kNavy),
      ),
    );
  }

  void _confirmRemove(Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Eliminar del presupuesto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy)),
        content: Text('¿Deseas remover "${product.name}" de tu lista de cotización?', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await QuoteService.removeFromQuote(product.id);
              _load();
            },
            child: const Text('Eliminar', style: TextStyle(color: _kRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummary() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total de equipos ($_totalQty piezas):', style: const TextStyle(fontSize: 13, color: _kNavy)),
                    const SizedBox(height: 2),
                    Text(
                      _fmt(_estimatedSubtotal),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kPrimary),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _showFormBottomSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Row(
                    children: [
                      Text('Solicitar Cotización', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Los montos son ilustrativos y no constituyen una oferta de venta formal.',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteFormSheet extends StatefulWidget {
  final int itemsCount;
  final Function(String requestNumber) onSuccess;
  const _QuoteFormSheet({required this.itemsCount, required this.onSuccess});

  @override
  State<_QuoteFormSheet> createState() => _QuoteFormSheetState();
}

class _QuoteFormSheetState extends State<_QuoteFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyController = TextEditingController();
  final _messageController = TextEditingController();

  bool _loading = false;
  bool _fetchingProfile = false;

  @override
  void initState() {
    super.initState();
    _prefillFromSession();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _prefillFromSession() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    setState(() => _fetchingProfile = true);

    // Initial prefill from auth metadata
    if (mounted) {
      _emailController.text = user.email ?? '';
      _phoneController.text = user.phone ?? '';
      _nameController.text = user.userMetadata?['full_name'] as String? ?? 
                             user.userMetadata?['name'] as String? ?? '';
    }

    try {
      // 1. Fetch from clients table
      final clientData = await client
          .from('clients')
          .select('contact_name, email, contact_phone, business_name')
          .eq('id', user.id)
          .maybeSingle();

      if (clientData != null && mounted) {
        if (clientData['contact_name'] != null && (clientData['contact_name'] as String).isNotEmpty) {
          _nameController.text = clientData['contact_name'] as String;
        }
        if (clientData['email'] != null && (clientData['email'] as String).isNotEmpty) {
          _emailController.text = clientData['email'] as String;
        }
        if (clientData['contact_phone'] != null && (clientData['contact_phone'] as String).isNotEmpty) {
          _phoneController.text = clientData['contact_phone'] as String;
        }
        if (clientData['business_name'] != null && (clientData['business_name'] as String).isNotEmpty) {
          _companyController.text = clientData['business_name'] as String;
        }
      }
    } catch (_) {}

    try {
      // 2. Fetch from profiles table
      final profileData = await client
          .from('profiles')
          .select('full_name, phone')
          .eq('id', user.id)
          .maybeSingle();

      if (profileData != null && mounted) {
        if (profileData['full_name'] != null && (profileData['full_name'] as String).isNotEmpty) {
          _nameController.text = profileData['full_name'] as String;
        }
        if (profileData['phone'] != null && (profileData['phone'] as String).isNotEmpty) {
          _phoneController.text = profileData['phone'] as String;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _fetchingProfile = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final requestNumber = await QuoteService.sendQuoteRequest(
        contactName: _nameController.text,
        contactEmail: _emailController.text,
        contactPhone: _phoneController.text,
        companyName: _companyController.text,
        message: _messageController.text,
      );

      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
        widget.onSuccess(requestNumber); // Trigger success callback
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final errMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar la solicitud: $errMsg'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pull handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Datos de Contacto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kNavy),
            ),
            const SizedBox(height: 4),
            Text(
              'Completa tus datos para enviarte tu propuesta formal de cotización.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            if (_fetchingProfile)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary)),
                      SizedBox(width: 10),
                      Text('Cargando información del perfil...', style: TextStyle(fontSize: 13, color: _kNavy)),
                    ],
                  ),
                ),
              ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Full name
                  TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration('Nombre completo *', Icons.person_outline),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa tu nombre completo' : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  // Email
                  TextFormField(
                    controller: _emailController,
                    decoration: _inputDecoration('Correo electrónico *', Icons.mail_outline),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Ingresa tu correo electrónico';
                      }
                      final emailReg = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailReg.hasMatch(v.trim())) {
                        return 'Ingresa un correo electrónico válido';
                      }
                      return null;
                    },
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  // Phone
                  TextFormField(
                    controller: _phoneController,
                    decoration: _inputDecoration('Teléfono (Recomendado)', Icons.phone_android_outlined),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  // Company
                  TextFormField(
                    controller: _companyController,
                    decoration: _inputDecoration('Empresa (Opcional)', Icons.business_outlined),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  // Message
                  TextFormField(
                    controller: _messageController,
                    decoration: _inputDecoration('Mensaje / Notas adicionales', Icons.comment_outlined, isMultiline: true),
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  // Send button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Enviar Solicitud',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {bool isMultiline = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
      prefixIcon: Icon(icon, color: _kNavy, size: 20),
      alignLabelWithHint: isMultiline,
      filled: true,
      fillColor: Colors.grey.shade50,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kRed, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}
