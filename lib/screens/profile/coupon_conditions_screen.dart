import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/customer_coupon.dart';
import '../../utils/ui_helpers.dart';
import 'coupon_eligible_products_screen.dart';
import 'profile_helpers.dart';

class CouponConditionsScreen extends StatelessWidget {
  final CustomerCoupon coupon;

  const CouponConditionsScreen({super.key, required this.coupon});

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: coupon.code));
    UiHelpers.showFloatingSuccessToast(
      context,
      'Código ${coupon.code} copiado al portapapeles',
    );
  }

  void _openEligibleProducts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CouponEligibleProductsScreen(coupon: coupon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAvailable = coupon.isAvailable;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Condiciones del cupón',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        coupon.benefitText,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isAvailable ? kNavy : const Color(0xFF64748B),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: coupon.stateColor.withValues(
                          alpha: isAvailable ? 0.12 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: coupon.stateColor.withValues(
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
                          color: coupon.stateColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  coupon.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                if (coupon.publicDescription != null &&
                    coupon.publicDescription!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    coupon.publicDescription!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Code Box Capsule
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.confirmation_number_outlined,
                        size: 16,
                        color: kPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          coupon.code,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _copyCode(context),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded, size: 13, color: kNavy),
                              SizedBox(width: 4),
                              Text(
                                'Copiar',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: kNavy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Conditions Detail Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Detalles y restricciones',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: kNavy,
                  ),
                ),
                const SizedBox(height: 14),

                // Descuento
                _buildConditionRow(
                  icon: Icons.percent_rounded,
                  title: 'DESCUENTO',
                  value: coupon.benefitText,
                ),

                // Compra mínima
                if (coupon.minimumSubtotal > 0)
                  _buildConditionRow(
                    icon: Icons.shopping_cart_outlined,
                    title: 'COMPRA MÍNIMA',
                    value: formatCurrency(coupon.minimumSubtotal),
                  ),

                // Descuento máximo
                if (coupon.maximumDiscount != null &&
                    coupon.maximumDiscount! > 0)
                  _buildConditionRow(
                    icon: Icons.price_check_rounded,
                    title: 'DESCUENTO MÁXIMO',
                    value: formatCurrency(coupon.maximumDiscount!),
                  ),

                // Vigencia
                _buildConditionRow(
                  icon: Icons.calendar_today_outlined,
                  title: 'VIGENCIA',
                  value: coupon.formattedValidRange,
                ),

                // Usos
                if (coupon.remainingUsesText != null)
                  _buildConditionRow(
                    icon: Icons.repeat_rounded,
                    title: 'LÍMITE DE USOS',
                    value: coupon.remainingUsesText!,
                  ),

                // Promociones
                _buildConditionRow(
                  icon: coupon.combinableWithPromotions
                      ? Icons.layers_outlined
                      : Icons.layers_clear_outlined,
                  title: 'PROMOCIONES',
                  value: coupon.combinableWithPromotions
                      ? 'Acumulable con otras promociones activas'
                      : 'No acumulable con otras promociones',
                ),

                // Productos
                _buildConditionRow(
                  icon: Icons.inventory_2_outlined,
                  title: 'PRODUCTOS PARTICIPANTES',
                  value: coupon.catalogScope == 'all'
                      ? 'Aplica a todo el catálogo disponible'
                      : 'Aplica únicamente a productos y categorías seleccionadas',
                  isLast: true,
                ),
              ],
            ),
          ),

          // Condiciones adicionales administrables (solo si existe texto)
          if (coupon.publicTerms != null && coupon.publicTerms!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.article_outlined, size: 16, color: kNavy),
                      SizedBox(width: 8),
                      Text(
                        'Condiciones adicionales',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: kNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    coupon.publicTerms!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Disclaimer
          Container(
            padding: const EdgeInsets.all(12),
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
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons at bottom
          if (isAvailable) ...[
            ElevatedButton.icon(
              onPressed: () => _openEligibleProducts(context),
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text(
                'Ver productos participantes',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConditionRow({
    required IconData icon,
    required String title,
    required String value,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF475569)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
