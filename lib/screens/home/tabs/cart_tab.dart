import 'package:flutter/material.dart';
import '../../../services/cart_service.dart';
import '../../../services/address_service.dart';
import '../../../utils/ui_helpers.dart';
import '../address_picker_screen.dart';
import '../home_screen.dart';
import '../widgets/checkout_sheet.dart';

const _kPrimary = Color(0xFF0D9488);

class CartTab extends StatefulWidget {
  const CartTab({super.key});
  @override
  State<CartTab> createState() => CartTabState();
}

class CartTabState extends State<CartTab> {
  List<CartItem> _items = [];
  bool _loading = true;
  String _currentLocation = 'Selecciona tu ubicación';
  Set<String> _selectedItemIds = {};
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  void _removeItem(int index, CartItem item, {bool fromSwipe = false}) async {
    final removedItem = item;
    final int originalIndex = index;

    setState(() {
      _selectedItemIds.remove(removedItem.id);
      _items.removeAt(originalIndex);
    });

    _listKey.currentState?.removeItem(
      originalIndex,
      (context, animation) {
        if (fromSwipe) {
          return const SizedBox.shrink();
        }
        return SizeTransition(
          sizeFactor: animation,
          child: FadeTransition(
            opacity: animation,
            child: _cartItemCard(removedItem, originalIndex),
          ),
        );
      },
      duration: fromSwipe ? Duration.zero : const Duration(milliseconds: 300),
    );

    try {
      await CartService.removeFromCart(removedItem.id);
      load(showSpinner: false);
    } catch (e) {
      setState(() {
        _items.insert(originalIndex, removedItem);
        _selectedItemIds.add(removedItem.id);
      });
      _listKey.currentState?.insertItem(originalIndex);
      if (context.mounted) {
        UiHelpers.showErrorToast(
          context,
          'Error al eliminar: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> _loadLocation() async {
    try {
      final addr = await AddressService.getDefaultAddress();
      if (addr != null && mounted) {
        setState(() => _currentLocation = addr.displayText);
      }
    } catch (_) {}
  }

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _loading = true);
    }
    _loadLocation();
    try {
      final items = await CartService.getCartItems();
      if (mounted) {
        setState(() {
          _items = items;
          _selectedItemIds = items.map((i) => i.id).toSet();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _subtotal => _items
      .where((i) => _selectedItemIds.contains(i.id))
      .fold(0, (s, i) => s + i.subtotal);
  double get _iva => _subtotal * 0.16;

  double get _shippingFee {
    if (_subtotal <= 0) return 0.0;
    return _subtotal >= 2000 ? 0.0 : 80.0;
  }

  double get _savings {
    double s = 0.0;
    for (final item in _items) {
      if (_selectedItemIds.contains(item.id) && item.product != null) {
        final p = item.product!;
        if (p.hasDiscount && p.oldPrice != null) {
          s += (p.oldPrice! - p.unitPriceMxn) * item.quantity;
        }
      }
    }
    return s;
  }

  double get _originalSubtotal => _items
      .where((i) => _selectedItemIds.contains(i.id))
      .fold(
        0,
        (s, i) =>
            s +
            (i.product != null
                ? (i.product!.oldPrice ?? i.product!.unitPriceMxn) * i.quantity
                : i.subtotal),
      );

  double get _originalTotal => _originalSubtotal + _shippingFee;

  double get _productDiscountAmount {
    double d = 0.0;
    for (final item in _items) {
      if (_selectedItemIds.contains(item.id) && item.product != null) {
        final p = item.product!;
        if (p.hasDiscount && p.oldPrice != null) {
          d += (p.oldPrice! - p.unitPriceMxn) * item.quantity;
        }
      }
    }
    return d;
  }

  double get _total => (_subtotal + _shippingFee).clamp(0.0, double.infinity);

  int get _totalQty => _items
      .where((i) => _selectedItemIds.contains(i.id))
      .fold(0, (s, i) => s + i.quantity);

  bool _isUnavailable(CartItem item) {
    final status = item.product?.stockStatusLabel.toLowerCase() ?? '';
    return status.contains('sin stock') || status.contains('agotado');
  }

  bool get _hasUnavailableSelected => _items.any(
    (item) => _selectedItemIds.contains(item.id) && _isUnavailable(item),
  );

  String _fmt(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '\$$buf.${parts[1]}';
  }

  void _showCouponDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ingresar cupón de descuento',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Escribe tu cupón al finalizar la compra para que el equipo lo valide antes de confirmar la orden.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.grey.shade600,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2F1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: _kPrimary,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Los descuentos se aplican después de validar el cupón.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF0F766E),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Entendido',
                            style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPurchaseSummaryBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final double origSubtotal = _originalSubtotal;
            final double subtotal = _subtotal;
            final double shipping = _shippingFee;
            final double prodDiscount = _productDiscountAmount;
            final double total = _total;
            final double savings = _savings;
            final int qty = _totalQty;
            final bool hasUnavailableSelected = _hasUnavailableSelected;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Resumen de compra',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.grey,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (subtotal > 0 && subtotal < 2000) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: (subtotal / 2000).clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade100,
                            color: _kPrimary,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Agrega ${_fmt(2000 - subtotal)} más para tener envío gratis',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ],

                    _summaryRow('Productos ($qty)', _fmt(origSubtotal)),
                    const SizedBox(height: 10),
                    _summaryRow(
                      'Envío',
                      shipping <= 0 ? 'Gratis' : _fmt(shipping),
                      color: shipping <= 0 ? const Color(0xFF16A34A) : null,
                    ),

                    if (prodDiscount > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Descuento de productos',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '-${_fmt(prodDiscount)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _showCouponDialog();
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: _kPrimary, width: 1.5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.confirmation_number_outlined,
                              color: _kPrimary,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'Ingresar cupón de descuento',
                                style: TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (hasUnavailableSelected) ...[
                      const SizedBox(height: 14),
                      _availabilityWarning(),
                    ],

                    const SizedBox(height: 20),
                    CustomPaint(
                      size: const Size(double.infinity, 1),
                      painter: DashedLinePainter(color: Colors.grey.shade200),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (savings > 0) ...[
                                  Text(
                                    _fmt(_originalTotal),
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.grey.shade400,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  _fmt(total),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            if (savings > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Ahorras ${_fmt(savings)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 2),
                              Text(
                                'IVA incluido',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: qty <= 0 || hasUnavailableSelected
                            ? null
                            : () {
                                Navigator.pop(context);
                                _showCheckoutBottomSheet();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade200,
                          disabledForegroundColor: Colors.grey.shade400,
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Comprar',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCheckoutBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => CheckoutSheet(
        total: _total,
        onSuccess: () {
          load();
        },
      ),
    );
  }

  Widget _buildStickyFooter() {
    final qty = _totalQty;
    final hasUnavailableSelected = _hasUnavailableSelected;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _showCouponDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade100),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.confirmation_number_outlined,
                      color: _kPrimary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ingresar cupón de descuento',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_right_rounded,
                      color: Colors.grey.shade400,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (hasUnavailableSelected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _availabilityWarning(),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _showPurchaseSummaryBottomSheet,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  if (_savings > 0) ...[
                                    Text(
                                      _fmt(_originalTotal),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade400,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    _fmt(_total),
                                    style: const TextStyle(
                                      fontSize: 18.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    color: _kPrimary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                            if (_savings > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Ahorras ${_fmt(_savings)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 2),
                              Text(
                                'IVA incluido',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    width: 180,
                    child: ElevatedButton(
                      onPressed: qty <= 0 || hasUnavailableSelected
                          ? null
                          : _showCheckoutBottomSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade400,
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Comprar',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: _kPrimary,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 24,
                        ),
                        tooltip: 'Regresar al inicio',
                        onPressed: () => HomeScreen.showTab(0),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Carrito (${_items.fold<int>(0, (s, i) => s + i.quantity)})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.2,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Finaliza tu orden de compra',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.of(context)
                        .push<ClientAddress>(
                          MaterialPageRoute(
                            builder: (_) => const AddressPickerScreen(),
                          ),
                        );
                    if (result != null && mounted) {
                      setState(() => _currentLocation = result.displayText);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _currentLocation == 'Selecciona tu ubicación'
                                    ? '¿Dónde enviamos?'
                                    : _currentLocation,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _items.isEmpty
              ? RefreshIndicator(
                  color: _kPrimary,
                  onRefresh: load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height - 240,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shopping_cart_outlined,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Tu carrito está vacío',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Explora nuestro catálogo médico',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value:
                                  _selectedItemIds.length == _items.length &&
                                  _items.isNotEmpty,
                              activeColor: _kPrimary,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedItemIds = _items
                                        .map((i) => i.id)
                                        .toSet();
                                  } else {
                                    _selectedItemIds.clear();
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedItemIds.length == _items.length &&
                                    _items.isNotEmpty
                                ? 'Deseleccionar todos'
                                : 'Seleccionar todos',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    Expanded(
                      child: RefreshIndicator(
                        color: _kPrimary,
                        onRefresh: load,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              sliver: SliverAnimatedList(
                                key: _listKey,
                                initialItemCount: _items.length,
                                itemBuilder: (context, index, animation) {
                                  if (index >= _items.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final item = _items[index];
                                  return _buildAnimatedItem(
                                    item,
                                    animation,
                                    index,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_items.isNotEmpty) _buildStickyFooter(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAnimatedItem(
    CartItem item,
    Animation<double> animation,
    int index,
  ) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: Dismissible(
          key: Key('dismiss-${item.id}'),
          direction: DismissDirection.horizontal,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 22,
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 22,
            ),
          ),
          onDismissed: (direction) {
            _removeItem(index, item, fromSwipe: true);
          },
          child: _cartItemCard(item, index),
        ),
      ),
    );
  }

  Widget _buildInvoiceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RESUMEN DE SOLICITUD',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.8,
                ),
              ),
              Icon(
                Icons.receipt_long_outlined,
                color: Colors.grey.shade400,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _summaryRow('Productos ($_totalQty)', _fmt(_subtotal)),
          const SizedBox(height: 8),
          _summaryRow('IVA (16%)', _fmt(_iva)),
          const SizedBox(height: 16),
          CustomPaint(
            size: const Size(double.infinity, 1),
            painter: DashedLinePainter(color: Colors.grey.shade200),
          ),
          const SizedBox(height: 16),
          _summaryRow(
            'Total a Pagar',
            _fmt(_total),
            bold: true,
            size: 18,
            color: const Color(0xFF0F172A),
          ),
        ],
      ),
    );
  }

  Widget _availabilityWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hay productos seleccionados sin disponibilidad. Deseleccionalos o quitalos para continuar.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9A3412),
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartItemCard(CartItem item, int index) {
    final p = item.product;
    final isSelected = _selectedItemIds.contains(item.id);
    final isUnavailable = _isUnavailable(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Row(
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: isSelected,
                      activeColor: _kPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedItemIds.add(item.id);
                          } else {
                            _selectedItemIds.remove(item.id);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: p?.mainImageUrl != null
                          ? UiHelpers.networkImage(
                              p!.mainImageUrl!,
                              fit: BoxFit.contain,
                              iconSize: 28,
                            )
                          : Container(
                              color: const Color(0xFFF8FAFC),
                              child: const Icon(
                                Icons.medical_services_outlined,
                                color: Colors.grey,
                                size: 28,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p?.name ?? 'Producto',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              p?.formattedPrice ?? '',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (p != null && p.hasDiscount) ...[
                              const SizedBox(width: 6),
                              Text(
                                p.formattedOldPrice,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (p != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(
                                isUnavailable
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 13,
                                color: p.stockStatusColor,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  p.stockStatusLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: p.stockStatusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                if (item.quantity <= 1) return;
                                setState(() {
                                  item.quantity--;
                                });
                                try {
                                  await CartService.updateQuantity(
                                    item.id,
                                    item.quantity,
                                  );
                                  load(showSpinner: false);
                                } catch (e) {
                                  setState(() {
                                    item.quantity++;
                                  });
                                  if (context.mounted) {
                                    UiHelpers.showErrorToast(
                                      context,
                                      'Error al actualizar: ${e.toString().replaceAll('Exception: ', '')}',
                                    );
                                  }
                                }
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.remove,
                                  size: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                '${item.quantity}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap:
                                  (p != null &&
                                      p.stock != null &&
                                      item.quantity >= p.stock!)
                                  ? null
                                  : () async {
                                      final stock = p?.stock ?? 999;
                                      if (item.quantity >= stock) return;
                                      setState(() {
                                        item.quantity++;
                                      });
                                      try {
                                        await CartService.updateQuantity(
                                          item.id,
                                          item.quantity,
                                        );
                                        load(showSpinner: false);
                                      } catch (e) {
                                        setState(() {
                                          item.quantity--;
                                        });
                                        if (context.mounted) {
                                          final errStr = e.toString();
                                          if (errStr.contains(
                                            'stock_limit_reached',
                                          )) {
                                            final limit =
                                                int.tryParse(
                                                  errStr.split(':').last,
                                                ) ??
                                                stock;
                                            UiHelpers.showStockLimitToast(
                                              context,
                                              limit,
                                            );
                                          } else {
                                            UiHelpers.showErrorToast(
                                              context,
                                              'Error al actualizar: ${errStr.replaceAll('Exception: ', '')}',
                                            );
                                          }
                                        }
                                      }
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.add,
                                  size: 13,
                                  color:
                                      (p != null &&
                                          p.stock != null &&
                                          item.quantity >= p.stock!)
                                      ? Colors.grey.shade300
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _removeItem(index, item, fromSwipe: false),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    double size = 14,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: size,
            color:
                color ??
                (bold ? const Color(0xFF0F172A) : Colors.grey.shade600),
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: size,
            color:
                color ??
                (bold ? const Color(0xFF0F172A) : const Color(0xFF334155)),
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  DashedLinePainter({this.color = Colors.grey});

  @override
  void paint(Canvas canvas, Size size) {
    double dashWidth = 5, dashSpace = 3, startX = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
