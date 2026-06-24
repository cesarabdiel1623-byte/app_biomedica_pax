import 'package:flutter/material.dart';

class AppColors {
  // New Elegant Clinical Palette
  static const Color primary = Color(0xFF3F7373); // Ming
  static const Color secondary = Color(0xFF768C45); // Palm Leaf
  static const Color softHighlight = Color(0xFFC5D7D9); // Columbia Blue
  static const Color accent = Color(0xFF768C45); // Palm Leaf (replacing old orange/accent)
  static const Color background = Color(0xFFF2F1F0); // Anti-Flash White

  // Professional support palette.
  static const Color darkTeal = Color(0xFF4F7A7A);
  static const Color medicalBlue = Color(0xFF4F6D9A);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF5F6675);
  static const Color border = Color(0xFFA8BDBF); // Opal
  static const Color error = Color(0xFFEF4444);

  static const Color white = Colors.white;
  static const Color surface = Colors.white;
  static const Color black = Colors.black;

  // Backward-compatible semantic aliases used by existing screens.
  static const Color info = softHighlight;
}
