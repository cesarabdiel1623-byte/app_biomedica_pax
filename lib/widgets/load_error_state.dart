import 'package:flutter/material.dart';

import '../utils/ui_helpers.dart';

class LoadErrorState extends StatelessWidget {
  final dynamic error;
  final VoidCallback onRetry;
  final String genericTitle;
  final String genericMessage;
  final EdgeInsetsGeometry padding;

  const LoadErrorState({
    super.key,
    required this.error,
    required this.onRetry,
    this.genericTitle = 'Ocurrió un error',
    this.genericMessage = 'Intenta nuevamente en unos momentos.',
    this.padding = const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    final isOffline = UiHelpers.isNetworkError(error);
    final title = isOffline ? 'No hay internet' : genericTitle;
    final message = isOffline
        ? 'Revisa tu conexión y vuelve a intentarlo.'
        : genericMessage;
    final icon = isOffline
        ? Icons.wifi_off_rounded
        : Icons.error_outline_rounded;
    final accent = isOffline
        ? const Color(0xFF0D9488)
        : const Color(0xFFEF4444);

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A5F),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0D9488),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'Reintentar',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
