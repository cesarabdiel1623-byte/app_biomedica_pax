import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/customer_coupon.dart';
import '../../services/coupon_service.dart';
import '../../services/cart_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';
import 'profile_helpers.dart';

class CouponsScreen extends StatefulWidget {
  final Future<List<CustomerCoupon>> Function()? couponsLoader;
  final Future<bool> Function()? hasActiveCartLoader;
  final Future<CartCouponResult> Function(String code)? couponApplier;

  const CouponsScreen({
    super.key,
    this.couponsLoader,
    this.hasActiveCartLoader,
    this.couponApplier,
  });

  /// Sanitiza los motivos de rechazo del backend a mensajes seguros y claros para el usuario.
  static String sanitizeCouponApplyReason(String? reason) {
    switch (reason?.trim().toLowerCase()) {
      case 'minimum_not_met':
        return 'Tu compra todavía no alcanza el monto mínimo requerido.';
      case 'expired':
        return 'Este cupón ya venció.';
      case 'not_started':
        return 'Este cupón todavía no está disponible.';
      case 'not_combinable':
        return 'Este cupón no puede combinarse con las promociones actuales.';
      case 'usage_limit_reached':
        return 'Este cupón alcanzó su límite de usos.';
      case 'client_limit_reached':
        return 'Ya utilizaste el número máximo de veces permitido.';
      case 'first_purchase_required':
        return 'Este cupón es exclusivo para la primera compra.';
      case 'not_assigned':
        return 'Este cupón no está disponible para tu cuenta.';
      case 'not_applicable':
        return 'Este cupón no aplica a los productos del carrito.';
      case 'inactive':
        return 'Este cupón no está disponible.';
      default:
        return 'No pudimos aplicar el cupón. Verifica las condiciones e inténtalo de nuevo.';
    }
  }

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  List<CustomerCoupon> _coupons = const [];
  bool _loading = true;
  String? _error;
  bool _hasActiveCart = false;
  String? _applyingCouponId;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  Future<void> _loadCoupons({bool showSpinner = true}) async {
    if (mounted && showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final fetchCoupons = widget.couponsLoader != null
          ? widget.couponsLoader!()
          : CouponService.getMyCoupons();
      final checkCart = widget.hasActiveCartLoader != null
          ? widget.hasActiveCartLoader!()
          : CartService.hasActiveCart();

      final results = await Future.wait<dynamic>([
        fetchCoupons,
        checkCart,
        if (showSpinner) Future.delayed(const Duration(milliseconds: 100)),
      ]);

      if (mounted) {
        setState(() {
          _coupons = results[0] as List<CustomerCoupon>;
          _hasActiveCart = results[1] as bool;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar cupones: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyCouponCode(CustomerCoupon coupon) async {
    await Clipboard.setData(ClipboardData(text: coupon.code));
    if (!mounted) return;
    UiHelpers.showFloatingSuccessToast(
      context,
      'Código ${coupon.code} copiado al portapapeles',
    );
  }

  Future<void> _applyCouponToCart(CustomerCoupon coupon) async {
    if (_applyingCouponId != null) return;
    setState(() => _applyingCouponId = coupon.couponId);

    try {
      final applyFuture = widget.couponApplier != null
          ? widget.couponApplier!(coupon.code)
          : CartService.applyCartCoupon(coupon.code);

      final result = await applyFuture;
      if (!mounted) return;

      if (result.valid) {
        UiHelpers.showFloatingSuccessToast(
          context,
          '¡Cupón ${coupon.code} aplicado a tu carrito!',
        );
        await _loadCoupons(showSpinner: false);
      } else {
        final message = CouponsScreen.sanitizeCouponApplyReason(result.reason);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error técnico al aplicar cupón: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos aplicar el cupón. Verifica las condiciones e inténtalo de nuevo.',
          ),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _applyingCouponId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Mis Cupones',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _error != null
          ? RefreshIndicator(
              color: kPrimary,
              backgroundColor: Colors.white,
              onRefresh: () => _loadCoupons(showSpinner: false),
              child: ListView(
                physics: UiHelpers.refreshScrollPhysics,
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height - 180,
                    child: LoadErrorState(
                      error: _error,
                      onRetry: _loadCoupons,
                      genericTitle: 'Error al cargar cupones',
                      genericMessage: 'No pudimos cargar tus cupones.',
                    ),
                  ),
                ],
              ),
            )
          : _coupons.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: kPrimary,
              backgroundColor: Colors.white,
              onRefresh: () => _loadCoupons(showSpinner: false),
              child: _buildCouponsList(),
            ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      color: kPrimary,
      backgroundColor: Colors.white,
      onRefresh: () => _loadCoupons(showSpinner: false),
      child: ListView(
        physics: UiHelpers.refreshScrollPhysics,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.confirmation_number_outlined,
                        size: 36,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No tienes cupones disponibles',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cuando tengas descuentos disponibles aparecerán aquí.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponsList() {
    final availableCoupons = _coupons.where((c) => c.isAvailable).toList();
    final otherCoupons = _coupons.where((c) => !c.isAvailable).toList();

    return ListView(
      physics: UiHelpers.refreshScrollPhysics,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _buildDisclaimerBanner(),
        const SizedBox(height: 12),
        if (availableCoupons.isNotEmpty) ...[
          _buildSectionHeader('Disponibles', availableCoupons.length),
          const SizedBox(height: 8),
          ...availableCoupons.map(_buildCouponCard),
          const SizedBox(height: 14),
        ],
        if (otherCoupons.isNotEmpty) ...[
          _buildSectionHeader('Otros cupones', otherCoupons.length),
          const SizedBox(height: 8),
          ...otherCoupons.map(_buildCouponCard),
        ],
      ],
    );
  }

  Widget _buildDisclaimerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Las condiciones finales se validan al aplicar el cupón en el carrito.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey.shade700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF475569),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCouponCard(CustomerCoupon coupon) {
    final isAvailable = coupon.isAvailable;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAvailable
              ? const Color(0xFFCBD5E1)
              : const Color(0xFFE2E8F0),
          width: isAvailable ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Benefit & Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    coupon.benefitText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isAvailable ? kNavy : const Color(0xFF64748B),
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: coupon.stateColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    coupon.stateLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: coupon.stateColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Name
            Text(
              coupon.name,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),

            // Public Description
            if (coupon.publicDescription != null &&
                coupon.publicDescription!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                coupon.publicDescription!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Conditions summary
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                if (coupon.minimumSubtotalText != null)
                  _buildConditionChip(
                    Icons.shopping_cart_outlined,
                    coupon.minimumSubtotalText!,
                  ),
                if (coupon.formattedValidUntil != null)
                  _buildConditionChip(
                    Icons.schedule_outlined,
                    coupon.formattedValidUntil!,
                  ),
                if (coupon.clientUsageLimit != null)
                  _buildConditionChip(
                    Icons.repeat_rounded,
                    'Usos restantes: ${coupon.remainingUses ?? (coupon.clientUsageLimit! - coupon.clientUses).clamp(0, 999)}',
                  ),
                if (!coupon.combinableWithPromotions)
                  _buildConditionChip(
                    Icons.layers_clear_outlined,
                    'No acumulable con otras promociones',
                  ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
            ),

            // Bottom action row: Code container + Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                // Code box
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.discount_outlined,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        coupon.code,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),

                // Buttons row
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Copy code button
                    OutlinedButton.icon(
                      onPressed: () => _copyCouponCode(coupon),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text(
                        'Copiar código',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kNavy,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),

                    // Apply coupon button (available only when valid and cart exists)
                    if (isAvailable && _hasActiveCart) ...[
                      ElevatedButton(
                        onPressed: _applyingCouponId == coupon.couponId
                            ? null
                            : () => _applyCouponToCart(coupon),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: _applyingCouponId == coupon.couponId
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Usar cupón',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
