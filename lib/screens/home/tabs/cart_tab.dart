import 'package:flutter/material.dart';
import '../../../services/cart_service.dart';
import '../../../utils/price_formatter.dart';
import '../../../services/address_service.dart';
import '../../../utils/ui_helpers.dart';
import '../../../widgets/standard_section_header.dart';
import '../address_picker_screen.dart';
import '../home_screen.dart';
import '../widgets/checkout_sheet.dart';
import '../../product/product_detail_screen.dart';

const _kPrimary = Color(0xFF024C8B);

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
  CartPricingAmounts? _cartPricingAmounts;
  bool _syncingCouponState = false;
  final Set<String> _notifiedStaleCouponKeys = {};

  bool get _isFullCartSelected =>
      _items.isNotEmpty && _selectedItemIds.length == _items.length;

  void _clearCartPricingAmounts() {
    _cartPricingAmounts = null;
  }

  void _removeItem(int index, CartItem item, {bool fromSwipe = false}) async {
    final removedItem = item;
    final int originalIndex = index;

    setState(() {
      _clearCartPricingAmounts();
      _selectedItemIds.remove(removedItem.id);
      _items.removeAt(originalIndex);
    });

    try {
      await CartService.removeFromCart(removedItem.id);
      load(showSpinner: false);
    } catch (e) {
      setState(() {
        _clearCartPricingAmounts();
        final safeIndex = originalIndex.clamp(0, _items.length);
        _items.insert(safeIndex, removedItem);
        _selectedItemIds.add(removedItem.id);
      });
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
        setState(() => _currentLocation = addr.deliveryLabel);
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
      final couponCleanup = items.isNotEmpty
          ? await CartService.clearInvalidPersistedCouponIfAny()
          : null;
      if (mounted) {
        setState(() {
          _items = items;
          _selectedItemIds = items.map((i) => i.id).toSet();
          _cartPricingAmounts = couponCleanup?.amounts;
          _loading = false;
        });
        if (couponCleanup?.removed == true) {
          _showStaleCouponRemovedNotice(couponCleanup!);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _subtotal => _items
      .where((i) => _selectedItemIds.contains(i.id))
      .fold(0, (s, i) => s + i.subtotal);
  double get _iva => _subtotal * 0.16;
  double get _couponDiscountAmount =>
      _isFullCartSelected ? (_cartPricingAmounts?.couponDiscount ?? 0.0) : 0.0;

  static const double freeShippingThreshold = 5000.0;

  double get _shippingFee {
    if (_subtotal <= 0) return 0.0;
    return _subtotal >= freeShippingThreshold ? 0.0 : 0.0;
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

  double get _total {
    if (_isFullCartSelected && _cartPricingAmounts != null) {
      return _cartPricingAmounts!.total.clamp(0.0, double.infinity);
    }
    return (_subtotal + _shippingFee).clamp(0.0, double.infinity);
  }

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
    return formatCommercialPrice(v);
  }

  Future<void> _showCouponDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CartCouponDialog(
        currentAmounts: _cartPricingAmounts,
        onPricingChanged: (amounts) {
          if (!mounted) return;
          setState(() => _cartPricingAmounts = amounts);
        },
      ),
    );

    if (changed == true && mounted) {
      setState(() {});
    }
  }

  void _showStaleCouponRemovedNotice(StaleCartCouponCleanupResult result) {
    if (!mounted || !result.removed) return;
    final key = '${result.code ?? ''}:${result.reason ?? ''}';
    if (_notifiedStaleCouponKeys.contains(key)) return;
    _notifiedStaleCouponKeys.add(key);

    final code = result.code?.trim().isNotEmpty == true
        ? result.code!.trim()
        : 'guardado';
    final message = result.reason == 'not_combinable'
        ? 'El cupón $code no se puede combinar con la promoción activa y fue retirado del carrito.'
        : 'El cupón $code ya no aplica a este carrito y fue retirado.';

    UiHelpers.showWarningToast(context, message, bottomMargin: 88);
  }

  Future<bool> _syncPersistedCouponBeforeCheckout() async {
    if (_syncingCouponState) return false;
    setState(() => _syncingCouponState = true);
    try {
      final cleanup = await CartService.clearInvalidPersistedCouponIfAny();
      if (!mounted) return false;
      setState(() => _cartPricingAmounts = cleanup.amounts);
      if (cleanup.removed) {
        _showStaleCouponRemovedNotice(cleanup);
      }
      return true;
    } catch (_) {
      if (mounted) {
        UiHelpers.showErrorToast(
          context,
          'No se pudo sincronizar el carrito. Inténtalo de nuevo.',
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _syncingCouponState = false);
      }
    }
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
            final double prodDiscount = _productDiscountAmount;
            final double couponDiscount = _couponDiscountAmount;
            final double total = _total;
            final double savings = _savings + couponDiscount;
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

                    if (subtotal > 0 && subtotal < freeShippingThreshold) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: (subtotal / freeShippingThreshold).clamp(
                              0.0,
                              1.0,
                            ),
                            backgroundColor: Colors.grey.shade100,
                            color: _kPrimary,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Agrega ${_fmt(freeShippingThreshold - subtotal)} más para tener envío gratis',
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
                    _summaryRow('Envío', 'Calculando al pagar'),

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

                    if (couponDiscount > 0) ...[
                      const SizedBox(height: 10),
                      _discountRow('Descuento de cupón', couponDiscount),
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

  Future<void> _showCheckoutBottomSheet() async {
    final synced = await _syncPersistedCouponBeforeCheckout();
    if (!synced || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CheckoutSheet(
          cartId: _items.isNotEmpty ? _items.first.cartId : '',
          subtotal: _subtotal,
          total: _total,
          cartPricingAmounts: _isFullCartSelected ? _cartPricingAmounts : null,
          asPage: true,
          onSuccess: () {
            load();
          },
        ),
      ),
    );
  }

  Widget _buildStickyFooter() {
    final qty = _totalQty;
    final hasUnavailableSelected = _hasUnavailableSelected;
    final totalSavings = _savings + _couponDiscountAmount;
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
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (totalSavings > 0)
                              Text(
                                _fmt(_originalTotal),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade400,
                                  decoration: TextDecoration.lineThrough,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Text(
                                    _fmt(_total),
                                    style: const TextStyle(
                                      fontSize: 19.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.3,
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
                            if (totalSavings > 0) ...[
                              const SizedBox(height: 1),
                              Text(
                                'Ahorras ${_fmt(totalSavings)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 1),
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
    final titleText = _loading
        ? 'Carrito'
        : (_items.isEmpty
              ? 'Carrito'
              : 'Carrito (${_items.fold<int>(0, (s, i) => s + i.quantity)})');

    final locationText =
        (_loading || _currentLocation == 'Selecciona tu ubicación')
        ? '¿Dónde enviamos?'
        : _currentLocation;

    return Column(
      children: [
        StandardSectionHeader(
          title: titleText,
          subtitle: 'Finaliza tu orden de compra',
          backgroundColor: _kPrimary,
          backTooltip: 'Regresar al inicio',
          onBack: () => HomeScreen.showTab(0),
        ),
        ColoredBox(
          color: _kPrimary,
          child: GestureDetector(
            onTap: () async {
              final result = await Navigator.of(context).push<ClientAddress>(
                MaterialPageRoute(builder: (_) => const AddressPickerScreen()),
              );
              if (result != null && mounted) {
                setState(() => _currentLocation = result.deliveryLabel);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
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
                          locationText,
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
        ),
        Expanded(
          child: _loading
              ? const _CartLoadingBody()
              : _items.isEmpty
              ? RefreshIndicator(
                  color: _kPrimary,
                  backgroundColor: Colors.white,
                  displacement: 42,
                  triggerMode: RefreshIndicatorTriggerMode.onEdge,
                  onRefresh: () => load(showSpinner: false),
                  child: ListView(
                    physics: UiHelpers.refreshScrollPhysics,
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
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        color: _kPrimary,
                        backgroundColor: Colors.white,
                        displacement: 42,
                        triggerMode: RefreshIndicatorTriggerMode.onEdge,
                        onRefresh: () => load(showSpinner: false),
                        child: CustomScrollView(
                          physics: UiHelpers.refreshScrollPhysics,
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
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
                                                _selectedItemIds.length ==
                                                    _items.length &&
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
                                          _selectedItemIds.length ==
                                                      _items.length &&
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
                                  const Divider(
                                    height: 1,
                                    color: Color(0xFFF1F5F9),
                                  ),
                                ],
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              sliver: SliverList.builder(
                                itemCount: _items.length,
                                itemBuilder: (context, index) =>
                                    _cartItemCard(_items[index], index),
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
          if (_couponDiscountAmount > 0) ...[
            const SizedBox(height: 8),
            _discountRow('Descuento de cupón', _couponDiscountAmount),
          ],
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: p == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(productId: p.id),
                      ),
                    );
                  },
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(width: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 76,
                          height: 76,
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
                            Padding(
                              padding: const EdgeInsets.only(right: 32),
                              child: Text(
                                p?.name ?? 'Producto',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            if (p != null && p.hasDiscount)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  'Antes: ${p.formattedOldPrice}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                    decoration: TextDecoration.lineThrough,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                Text(
                                  p?.formattedPrice ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                if (p != null && p.hasDiscount) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDC2626),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '-${p.discountPercent}%',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
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
                    ],
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => _removeItem(index, item, fromSwipe: false),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            if (item.quantity <= 1) return;
                            setState(() {
                              _clearCartPricingAmounts();
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
                                _clearCartPricingAmounts();
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
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Icon(
                              Icons.remove,
                              size: 14,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '${item.quantity}',
                            style: const TextStyle(
                              fontSize: 13,
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
                                    _clearCartPricingAmounts();
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
                                      _clearCartPricingAmounts();
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
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Icon(
                              Icons.add,
                              size: 14,
                              color:
                                  (p != null &&
                                      p.stock != null &&
                                      item.quantity >= p.stock!)
                                  ? Colors.grey.shade300
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  Widget _discountRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        Text(
          '-${_fmt(amount)}',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF16A34A),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CartCouponDialog extends StatefulWidget {
  const _CartCouponDialog({
    required this.onPricingChanged,
    this.currentAmounts,
  });

  final ValueChanged<CartPricingAmounts?> onPricingChanged;
  final CartPricingAmounts? currentAmounts;

  @override
  State<_CartCouponDialog> createState() => _CartCouponDialogState();
}

class _CartCouponDialogState extends State<_CartCouponDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _loading = false;
  bool _changed = false;
  bool _success = false;
  String? _feedback;
  CartPricingAmounts? _displayAmounts;

  @override
  void initState() {
    super.initState();
    _displayAmounts = widget.currentAmounts;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  Future<void> _applyCoupon() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _feedback = null;
    });

    try {
      final result = await CartService.applyCartCoupon(_codeController.text);
      if (!mounted) return;
      if (result.valid) {
        _displayAmounts = result.amounts;
        widget.onPricingChanged(result.amounts);
      }
      setState(() {
        _loading = false;
        _success = result.valid;
        _changed = _changed || result.valid;
        _feedback = result.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _feedback = _cleanError(error);
      });
    }
  }

  Future<void> _removeCoupon() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _feedback = null;
    });

    try {
      final amounts = await CartService.removeCartCoupon();
      if (!mounted) return;
      _codeController.clear();
      _displayAmounts = amounts;
      widget.onPricingChanged(amounts);
      setState(() {
        _loading = false;
        _success = true;
        _changed = true;
        _feedback = 'El cupón se quitó del carrito.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _feedback = _cleanError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final couponDiscount = _displayAmounts?.couponDiscount ?? 0.0;
    final hasAppliedCoupon = couponDiscount > 0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cupón de descuento',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'El servidor validará el código y calculará el total definitivo.',
              style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              enabled: !_loading,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _applyCoupon(),
              decoration: InputDecoration(
                labelText: 'Código del cupón',
                prefixIcon: const Icon(
                  Icons.confirmation_number_outlined,
                  color: _kPrimary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                ),
              ),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _success
                      ? const Color(0xFFE6F6F3)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _success
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _success
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB91C1C),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _feedback!,
                        style: TextStyle(
                          color: _success
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB91C1C),
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (hasAppliedCoupon) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.confirmation_number_outlined,
                      color: Color(0xFF16A34A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Descuento de cupón',
                        style: TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '-${formatCommercialPrice(couponDiscount)}',
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (hasAppliedCoupon) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _removeCoupon,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Quitar cupón aplicado'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.pop(context, _changed),
                  child: const Text('Cerrar'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _loading ? null : _applyCoupon,
                  style: FilledButton.styleFrom(backgroundColor: _kPrimary),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLoadingBody extends StatelessWidget {
  const _CartLoadingBody();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(child: CircularProgressIndicator(color: _kPrimary)),
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
