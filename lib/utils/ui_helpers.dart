import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants.dart';

class UiHelpers {
  static String? sanitizeTrustedRemoteUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    final value = rawUrl.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }

    final supabaseUri = Uri.tryParse(Constants.supabaseUrl);
    if (supabaseUri == null || supabaseUri.host.isEmpty) {
      return null;
    }

    if (uri.host != supabaseUri.host) {
      return null;
    }

    return uri.toString();
  }

  static bool isTrustedRemoteUrl(String? rawUrl) =>
      sanitizeTrustedRemoteUrl(rawUrl) != null;

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

  /// Muestra una alerta de éxito (verde)
  static void showSuccessToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFF0FDF4), // Verde menta muy suave
        elevation: 2,
        margin: const EdgeInsets.only(
          bottom: 85,
          left: 16,
          right: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFBBF7D0), width: 1.2), // Borde verde menta suave
        ),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A), // Icono verde vibrante
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF15803D), // Texto verde oscuro
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: const Color(0xFF166534), // Texto verde oscuro de acción
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Muestra una alerta de advertencia (ámbar)
  static void showWarningToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFFFFBEB), // Ámbar suave
        elevation: 2,
        margin: const EdgeInsets.only(
          bottom: 85,
          left: 16,
          right: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFFDE68A), width: 1.2), // Borde ámbar claro
        ),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFD97706), // Ámbar alerta vibrante
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFB45309), // Texto ámbar oscuro
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Muestra una alerta de error (rojo)
  static void showErrorToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFFEF2F2), // Rojo suave premium
        elevation: 2,
        margin: const EdgeInsets.only(
          bottom: 85,
          left: 16,
          right: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2), // Borde rojo claro
        ),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFEF4444), // Rojo alerta vibrante
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF991B1B), // Texto rojo oscuro
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showStockLimitToast(BuildContext context, int stock, {double bottomMargin = 12}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFDC2626), // Rojo Crimson de advertencia
        elevation: 6,
        margin: EdgeInsets.only(
          bottom: bottomMargin,
          left: 20,
          right: 20,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
        content: const Text(
          'Alcanzaste el máximo de unidades.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Muestra un brindis (Toast/SnackBar) personalizado indicando que se ha agregado un producto al carrito
  static void showAddToCartSuccessToast(BuildContext context, String productName, int quantity, {double bottomMargin = 12}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0D9488), // Color teal de éxito (estilo Biomedica/GoMedical)
        elevation: 6,
        margin: EdgeInsets.only(
          bottom: bottomMargin,
          left: 20,
          right: 20,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
        content: Text(
          quantity > 1
              ? '✓ $productName ($quantity unidades) al carrito'
              : '✓ $productName al carrito',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Muestra un toast de éxito al agregar un producto a la bolsa de cotización.
  /// Sin botón de acción para que se auto-descarte en 2 segundos igual que el carrito.
  static void showAddToQuoteSuccessToast(BuildContext context, String productName, {double bottomMargin = 12}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E3A5F),
        elevation: 6,
        margin: EdgeInsets.only(
          bottom: bottomMargin,
          left: 20,
          right: 20,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
        content: Text(
          '✓ $productName añadido a cotización',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Muestra un brindis (Toast/SnackBar) personalizado indicando que se ha enviado una pregunta
  static void showQuestionSubmittedToast(BuildContext context, String message, {double bottomMargin = 12}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0D9488), // Teal de éxito (igual al carrito)
        elevation: 6,
        margin: EdgeInsets.only(
          bottom: bottomMargin,
          left: 20,
          right: 20,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Muestra un brindis (Toast/SnackBar) personalizado indicando que se ha agregado un producto a favoritos
  static void showAddFavoriteToast(BuildContext context, String productName, {double bottomMargin = 12}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0D9488), // Teal de éxito
        elevation: 6,
        margin: EdgeInsets.only(
          bottom: bottomMargin,
          left: 20,
          right: 20,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
        content: Text(
          '✓ $productName agregado a favoritos.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Muestra un brindis (Toast/SnackBar) personalizado indicando que se ha eliminado un producto de favoritos
  static void showRemoveFavoriteToast(BuildContext context, String productName, {double bottomMargin = 12}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFDC2626), // Rojo Crimson de eliminación
        elevation: 6,
        margin: EdgeInsets.only(
          bottom: bottomMargin,
          left: 20,
          right: 20,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
        content: Text(
          '$productName eliminado de favoritos.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Devuelve un widget de imagen con un cargador circular suave y un fondo gris suave
  /// para evitar que las fotos queden en blanco durante la carga.
  static Widget networkImage(
    String url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    double iconSize = 32,
  }) {
    final trustedUrl = sanitizeTrustedRemoteUrl(url);
    if (trustedUrl == null) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFFF1F5F9),
        child: Center(
          child: Icon(
            Icons.shield_outlined,
            color: Colors.grey.shade400,
            size: iconSize,
          ),
        ),
      );
    }

    return Image.network(
      trustedUrl,
      width: width,
      height: height,
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: const Color(0xFFF1F5F9), // Gris pizarra claro
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Color(0xFF0D9488), // Color teal
                strokeWidth: 2,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: const Color(0xFFF1F5F9),
          child: Center(
            child: Icon(
              Icons.medical_services_outlined,
              color: Colors.grey.shade300,
              size: iconSize,
            ),
          ),
        );
      },
    );
  }
}
