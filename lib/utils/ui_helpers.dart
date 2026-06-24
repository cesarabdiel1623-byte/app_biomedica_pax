import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UiHelpers {
  /// Devuelve un mensaje de error amigable en español para excepciones de Supabase Auth
  static String getFriendlyAuthErrorMessage(dynamic error) {
    if (error is AuthException) {
      final code = error.code;
      final msg = error.message.toLowerCase();
      
      if (code == 'invalid_credentials' || msg.contains('invalid login credentials')) {
        return 'El correo o la contraseña son incorrectos. Por favor, verifica tus datos.';
      }
      if (code == 'email_not_confirmed' || msg.contains('email not confirmed')) {
        return 'Tu correo electrónico aún no ha sido confirmado. Por favor, revisa tu bandeja de entrada.';
      }
      if (code == 'user_already_exists' || msg.contains('user already registered') || msg.contains('already exists')) {
        return 'Este correo electrónico ya se encuentra registrado.';
      }
      if (code == 'phone_exists' || msg.contains('phone_exists') || msg.contains('already been registered') || msg.contains('phone already registered')) {
        return 'Este número de teléfono ya está registrado en otra cuenta. Por favor, usa otro número.';
      }
      if (msg.contains('exceeded') && msg.contains('daily')) {
        return 'Se alcanzó el límite diario de SMS. Intenta nuevamente mañana o contacta soporte.';
      }
      if (msg.contains('sms_send_failed')) {
        return 'No se pudo enviar el SMS. Verifica tu número e intenta más tarde.';
      }
      if (msg.contains('invalid') && msg.contains('phone')) {
        return 'El número de teléfono no es válido. Verifica que sea correcto.';
      }
      if (msg.contains('otp') || msg.contains('token') || msg.contains('verify') || msg.contains('confirm')) {
        return 'El código ingresado es incorrecto o ha expirado.';
      }
      if (msg.contains('too_many_requests') || msg.contains('rate_limit') || msg.contains('too many requests')) {
        return 'Demasiados intentos. Espera unos minutos antes de intentar de nuevo.';
      }
      if (msg.contains('network') || msg.contains('connection') || msg.contains('failed host lookup')) {
        return 'Error de conexión. Revisa tu conexión a internet e inténtalo de nuevo.';
      }
      if (error.message.isNotEmpty) {
        return error.message;
      }
    }
    
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('network') || errStr.contains('connection') || errStr.contains('socketexception') || errStr.contains('failed host lookup')) {
      return 'Error de conexión. Revisa tu conexión a internet e inténtalo de nuevo.';
    }
    
    return 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo.';
  }

  /// Muestra un brindis (Toast/SnackBar) personalizado al estilo de Mercado Libre
  /// indicando que se ha alcanzado el límite de stock disponible para el producto.
  static void showStockLimitToast(BuildContext context, int stock) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B), // Gris pizarra oscuro premium
        elevation: 6,
        margin: const EdgeInsets.only(
          bottom: 85, // Suficientemente alto para flotar sobre los botones inferiores y barras de navegación
          left: 20,
          right: 20,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFFBBF24), // Amarillo ámbar/alerta
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Has alcanzado el límite de stock disponible ($stock).',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
