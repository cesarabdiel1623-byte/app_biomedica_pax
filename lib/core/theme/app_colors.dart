import 'package:flutter/material.dart';

class AppColors {
  // ── Paleta oficial Go Medical Azul ──────────────────────────
  static const Color primary      = Color(0xFF0256CA); // Primary blue
  static const Color primaryBright = Color(0xFF086BEF); // Primary bright
  static const Color primaryDark  = Color(0xFF043B65); // Primary dark
  static const Color navy         = Color(0xFF023A65); // Navy

  // Fondos
  static const Color background   = Color(0xFFDCEEFF); // Fondo general azul claro #DCEEFF
  static const Color backgroundSoft = Color(0xFFEAF4FF); // Fondo suave
  static const Color surface      = Color(0xFFF9FAFD); // Surface cards
  static const Color surfaceBlue  = Color(0xFFEAF4FF); // Surface azul
  static const Color glowBlue     = Color(0xFFDCEEFF); // Azul glow suave
  static const Color decorativeBlue = Color(0xFFCFE5FF); // Azul decorativo

  // Bordes y texto
  static const Color border       = Color(0xFFD6DFE7);
  static const Color textPrimary  = Color(0xFF0B1F3A);
  static const Color textSecondary = Color(0xFF5B6F84);
  static const Color textDisabled = Color(0xFF9AA7B3);

  // Semánticos
  static const Color success      = Color(0xFF0F8A7A);
  static const Color successBg    = Color(0xFFDFF7F1);
  static const Color warning      = Color(0xFFF5B84B);
  static const Color warningBg    = Color(0xFFFFF2D8);
  static const Color danger       = Color(0xFFEF5B5B);
  static const Color dangerBg     = Color(0xFFFFE6E8);
  static const Color info         = Color(0xFF5F9FE7);
  static const Color infoBg       = Color(0xFFEAF4FF);

  // Básicos
  static const Color white        = Colors.white;
  static const Color black        = Colors.black;

  // ── Alias de compatibilidad (usados en pantallas existentes) ──
  // Estos alias mantienen la compatibilidad con referencias antiguas
  // sin romper código que no se toca en esta fase.
  static const Color secondary    = success;        // verde = éxito
  static const Color accent       = warning;        // amarillo = advertencia
  static const Color error        = danger;         // rojo = error/urgente
  static const Color softHighlight = surfaceBlue;   // azul claro
  static const Color darkTeal     = primaryDark;    // azul oscuro
  static const Color medicalBlue  = primary;        // alias directo
}
