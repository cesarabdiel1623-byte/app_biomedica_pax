import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/customer_coupon.dart';
import '../../services/coupon_service.dart';
import '../../services/cart_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';
import 'coupon_conditions_screen.dart';
import 'coupon_eligible_products_screen.dart';
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _buildDisclaimerBanner(),
        const SizedBox(height: 14),
        if (availableCoupons.isNotEmpty) ...[
          _buildSectionHeader('DISPONIBLES', availableCoupons.length),
          const SizedBox(height: 10),
          ...availableCoupons.map(_buildCouponCard),
          const SizedBox(height: 16),
        ],
        if (otherCoupons.isNotEmpty) ...[
          _buildSectionHeader('OTROS CUPONES', otherCoupons.length),
          const SizedBox(height: 10),
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
        borderRadius: BorderRadius.circular(10),
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
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF64748B),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
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

  void _openConditions(CustomerCoupon coupon) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CouponConditionsScreen(coupon: coupon)),
    );
  }

  void _openEligibleProducts(CustomerCoupon coupon) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CouponEligibleProductsScreen(coupon: coupon),
      ),
    );
  }

  Widget _buildCouponCard(CustomerCoupon coupon) {
    final isAvailable = coupon.isAvailable;
    final stateColor = coupon.stateColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isAvailable ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAvailable
              ? const Color(0xFFE2E8F0)
              : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: isAvailable
            ? [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Benefit & Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    coupon.benefitText,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isAvailable ? kNavy : const Color(0xFF64748B),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(
                      alpha: isAvailable ? 0.12 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: stateColor.withValues(
                        alpha: isAvailable ? 0.3 : 0.15,
                      ),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    coupon.stateLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: stateColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Name
            Text(
              coupon.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isAvailable
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF64748B),
              ),
            ),

            // Public Description (commercial summary)
            if (coupon.publicDescription != null &&
                coupon.publicDescription!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                coupon.publicDescription!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isAvailable
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Max 2 Secondary summary items (clean, unsaturating)
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (coupon.minimumSubtotalText != null)
                  _buildSecondarySummaryItem(
                    Icons.shopping_bag_outlined,
                    coupon.minimumSubtotalText!,
                    isAvailable,
                  ),
                if (_formatCardValidity(coupon) != null)
                  _buildSecondarySummaryItem(
                    Icons.event_outlined,
                    _formatCardValidity(coupon)!,
                    isAvailable,
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Dedicated Code Strip Capsule with Copy action
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isAvailable
                    ? const Color(0xFFF1F5F9)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.confirmation_number_outlined,
                    size: 15,
                    color: kPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      coupon.code,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: isAvailable
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => _copyCouponCode(coupon),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: isAvailable
                                ? kNavy
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Copiar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isAvailable
                                  ? kNavy
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Actions Row: [ Ver productos ] [ Ver condiciones ] [ Usar cupón ]
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isAvailable) ...[
                  ElevatedButton.icon(
                    onPressed: () => _openEligibleProducts(coupon),
                    icon: const Icon(Icons.grid_view_rounded, size: 14),
                    label: const Text(
                      'Ver productos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: () => _openConditions(coupon),
                  icon: const Icon(Icons.info_outline_rounded, size: 14),
                  label: const Text(
                    'Ver condiciones',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                if (isAvailable && _hasActiveCart) ...[
                  ElevatedButton(
                    onPressed: _applyingCouponId == coupon.couponId
                        ? null
                        : () => _applyCouponToCart(coupon),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kNavy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
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
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _formatCardValidity(CustomerCoupon coupon) {
    if (coupon.validUntil == null) return null;
    final dt = coupon.validUntil!;
    final months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final month = months[dt.month - 1];
    final dateStr = '${dt.day} $month.';
    if (coupon.isExpired) {
      return 'Venció $dateStr';
    }
    return 'Vence $dateStr';
  }

  Widget _buildSecondarySummaryItem(
    IconData icon,
    String text,
    bool isAvailable,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 13.5,
              color: isAvailable
                  ? const Color(0xFF64748B)
                  : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isAvailable
                    ? const Color(0xFF475569)
                    : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
