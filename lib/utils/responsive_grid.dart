import 'dart:math' as math;

/// Shared sizing rules for catalog grids on phones and tablets.
abstract final class ResponsiveGrid {
  static int productColumnCount(double availableWidth) {
    return (availableWidth / 180).floor().clamp(2, 6);
  }

  static double productCardExtent(double textScale) {
    final extraScale = math.max(0.0, textScale - 1.0).clamp(0.0, 2.0);
    return 330 + (extraScale * 125);
  }

  static int subcategoryColumnCount(double availableWidth) {
    return (availableWidth / 112).floor().clamp(2, 6);
  }

  static double subcategoryCardExtent(double textScale) {
    final extraScale = math.max(0.0, textScale - 1.0).clamp(0.0, 2.0);
    return 132 + (extraScale * 40);
  }
}
