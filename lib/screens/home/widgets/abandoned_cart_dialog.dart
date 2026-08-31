import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AbandonedCartDialog extends StatefulWidget {
  final String cartId;
  final VoidCallback onGoToCart;
  final VoidCallback onDismiss;

  const AbandonedCartDialog({
    super.key,
    required this.cartId,
    required this.onGoToCart,
    required this.onDismiss,
  });

  @override
  State<AbandonedCartDialog> createState() => _AbandonedCartDialogState();
}

class _AbandonedCartDialogState extends State<AbandonedCartDialog> {
  bool _loading = false;

  Future<void> _updateStatus(String status, VoidCallback callback) async {
    if (mounted) setState(() => _loading = true);
    try {
      await Supabase.instance.client
          .from('carts')
          .update({'followup_status': status})
          .eq('id', widget.cartId);
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
      callback();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF024C8B).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                color: Color(0xFF024C8B),
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Dejaste algo pendiente!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tienes artículos guardados en tu carrito de compras esperando por ti. ¿Quieres verlos ahora?',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF024C8B),
                    ),
                  ),
                ),
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF024C8B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () =>
                          _updateStatus('recovered', widget.onGoToCart),
                      child: const Text(
                        'Ver mi Carrito',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade500,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () =>
                          _updateStatus('dismissed', widget.onDismiss),
                      child: const Text(
                        'No, gracias',
                        style: TextStyle(fontSize: 16),
                      ),
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
