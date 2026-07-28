import 'package:flutter/material.dart';

import '../../models/payment_test_result.dart';

class PaymentResultScreen extends StatelessWidget {
  const PaymentResultScreen({super.key, required this.result});

  final PaymentTestResult result;

  @override
  Widget build(BuildContext context) {
    final config = _screenConfig(result);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Resultado del pago'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: config.backgroundColor,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(config.icon, size: 42, color: config.color),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    config.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    config.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Regresar al inicio',
                        style: TextStyle(
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
        ),
      ),
    );
  }

  _PaymentResultScreenConfig _screenConfig(PaymentTestResult result) {
    switch (result) {
      case PaymentTestResult.success:
        return const _PaymentResultScreenConfig(
          title: 'Pago de prueba reportado como aprobado',
          message:
              'Mercado Pago devolvió un resultado aprobado.\n\nEsta respuesta todavía debe confirmarse mediante un Webhook antes de considerarse definitiva.\n\nNo se generó ningún pedido real y no se modificó el inventario.',
          icon: Icons.check_circle_rounded,
          color: Color(0xFF16A34A),
          backgroundColor: Color(0xFFDCFCE7),
        );
      case PaymentTestResult.pending:
        return const _PaymentResultScreenConfig(
          title: 'Pago de prueba pendiente',
          message:
              'Mercado Pago reportó que la operación está pendiente.\n\nNo se generó ningún pedido real y el estado deberá confirmarse posteriormente desde el backend.',
          icon: Icons.schedule_rounded,
          color: Color(0xFFCA8A04),
          backgroundColor: Color(0xFFFEF3C7),
        );
      case PaymentTestResult.failure:
        return const _PaymentResultScreenConfig(
          title: 'Pago de prueba no completado',
          message:
              'La prueba fue rechazada, cancelada o no se completó.\n\nPuedes regresar e intentar nuevamente con otro escenario de prueba.',
          icon: Icons.cancel_rounded,
          color: Color(0xFFEF4444),
          backgroundColor: Color(0xFFFEE2E2),
        );
    }
  }
}

class _PaymentResultScreenConfig {
  const _PaymentResultScreenConfig({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
}
