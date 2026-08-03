import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Fondo general liso con un azul ligeramente más profundo
/// para que resalte la barra de navegación blanca.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.background, // #DCEEFF — azul claro liso
      child: child,
    );
  }
}
