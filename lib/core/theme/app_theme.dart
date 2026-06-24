import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.white,
        error: AppColors.error,
        onPrimary: AppColors.white,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
        outline: AppColors.border,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,

      // AppBar Theme (Luminosa y moderna)
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.primary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
      ),

      // Botones Elevados (Primary)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // Botones Secundarios (Outlined)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // Botones de Texto
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // Campos de Texto (Inputs)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),

      // Tarjetas (Cards)
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: AppColors.primary.withOpacity(0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // Chips (Categorías y Filtros)
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.secondary.withOpacity(0.15),
        disabledColor: Colors.grey.shade100,
        selectedColor: AppColors.primary,
        secondarySelectedColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
          side: const BorderSide(color: Colors.transparent),
        ),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Hojas de Diálogo Modal Inferior (Bottom Sheets)
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // Diálogos (Alerts)
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
      ),

      // Pestañas (TabBar)
      tabBarTheme: TabBarThemeData(
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.border,
      ),

      // Botón de Acción Flotante (FAB)
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Divisores (Dividers)
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // Barra de Navegación Inferior (Fallback por si no se usa curved)
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Íconos
      iconTheme: const IconThemeData(color: AppColors.primary),
    );
  }
}
