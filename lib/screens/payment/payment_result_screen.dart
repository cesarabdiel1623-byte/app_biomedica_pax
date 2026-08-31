import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/payment_test_result.dart';
import '../../services/mercado_pago_service.dart';

class PaymentResultScreen extends StatefulWidget {
  const PaymentResultScreen({super.key, this.returnData, this.result});

  final PaymentReturnData? returnData;
  final PaymentTestResult? result;

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  bool _loading = true;
  bool _checking = false;
  String? _error;
  OrderPaymentSnapshot? _snapshot;
  final List<Timer> _scheduledTimers = [];

  @override
  void initState() {
    super.initState();
    _startVerificationSequence();
  }

  @override
  void dispose() {
    _cancelAllTimers();
    super.dispose();
  }

  void _cancelAllTimers() {
    for (final timer in _scheduledTimers) {
      timer.cancel();
    }
    _scheduledTimers.clear();
  }

  void _startVerificationSequence() {
    _cancelAllTimers();
    _verifyNow();

    // Programar reintentos automáticos a los 2s, 5s y 10s si no se ha confirmado
    _scheduledTimers.add(
      Timer(const Duration(seconds: 2), () {
        if (mounted && _snapshot?.confirmed != true) _verifyNow();
      }),
    );

    _scheduledTimers.add(
      Timer(const Duration(seconds: 5), () {
        if (mounted && _snapshot?.confirmed != true) _verifyNow();
      }),
    );

    _scheduledTimers.add(
      Timer(const Duration(seconds: 10), () {
        if (mounted && _snapshot?.confirmed != true) _verifyNow();
      }),
    );
  }

  Future<void> _verifyNow() async {
    if (_checking) return;
    final orderId = widget.returnData?.orderId;

    if (orderId == null || orderId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Mercado Pago devolvió un resultado. Puedes revisar el estado de tu pedido en la sección "Mis compras".';
        });
      }
      return;
    }

    setState(() => _checking = true);

    try {
      final service = MercadoPagoService(Supabase.instance.client);
      final snapshot = await service.verifyOrderPayment(orderId);

      if (!mounted) return;

      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
        _checking = false;
      });

      if (snapshot.confirmed) {
        _cancelAllTimers();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _checking = false;
        if (_snapshot == null) {
          _error =
              'No fue posible verificar el pago en este momento. Intenta pulsar "Verificar nuevamente".';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _buildConfig();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Estado del pago'),
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
              child: _loading && _snapshot == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Color(0xFF024C8B),
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Pago en verificación...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Verificando confirmación con el servidor...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: config.backgroundColor,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Icon(
                            config.icon,
                            size: 42,
                            color: config.color,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          config.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          config.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Color(0xFF475569),
                          ),
                        ),
                        if (_snapshot?.paymentId != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'ID de Pago: ${_snapshot!.paymentId}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _checking ? null : _verifyNow,
                            icon: _checking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: Text(
                              _checking
                                  ? 'Consultando...'
                                  : 'Verificar nuevamente',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF024C8B),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst),
                          child: const Text('Regresar al inicio'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  _ScreenConfig _buildConfig() {
    if (_error != null && _snapshot == null) {
      return _ScreenConfig(
        title: 'Verificación pendiente',
        message: _error!,
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF64748B),
        backgroundColor: const Color(0xFFE2E8F0),
      );
    }

    final s = _snapshot;
    if (s?.approved == true) {
      return const _ScreenConfig(
        title: '¡Pago Acreditado!',
        message:
            'El pago ha sido confirmado de forma segura por el servidor. Tu pedido ya está en procesamiento.',
        icon: Icons.check_circle_rounded,
        color: Color(0xFF16A34A),
        backgroundColor: Color(0xFFDCFCE7),
      );
    }

    if (s?.failed == true) {
      return const _ScreenConfig(
        title: 'Pago No Completado',
        message:
            'Mercado Pago rechazó o no completó la transacción. No se ha realizado ningún cobro definitivo.',
        icon: Icons.cancel_rounded,
        color: Color(0xFFEF4444),
        backgroundColor: Color(0xFFFEE2E2),
      );
    }

    return const _ScreenConfig(
      title: 'Pago en verificación',
      message:
          'Estamos esperando la confirmación de la notificación de Mercado Pago. Puedes pulsar "Verificar nuevamente" para actualizar el estado.',
      icon: Icons.schedule_rounded,
      color: Color(0xFFCA8A04),
      backgroundColor: Color(0xFFFEF3C7),
    );
  }
}

class _ScreenConfig {
  const _ScreenConfig({
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
