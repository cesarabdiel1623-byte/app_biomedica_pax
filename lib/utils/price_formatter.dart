double roundFinancialAmount(double value) {
  return (value * 100).roundToDouble() / 100;
}

double roundCommercialAmount(double value) {
  return value.roundToDouble();
}

String formatCommercialPrice(double value, {bool includeCurrency = true}) {
  final rounded = roundCommercialAmount(value).toInt();
  final formatted = _groupThousands(rounded.toString());
  return '\$$formatted${includeCurrency ? ' MXN' : ''}';
}

String formatFinancialPrice(double value, {bool includeCurrency = true}) {
  final parts = roundFinancialAmount(value).toStringAsFixed(2).split('.');
  final formatted = '${_groupThousands(parts[0])}.${parts[1]}';
  return '\$$formatted${includeCurrency ? ' MXN' : ''}';
}

String _groupThousands(String value) {
  final negative = value.startsWith('-');
  final digits = negative ? value.substring(1) : value;
  final buffer = StringBuffer(negative ? '-' : '');

  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }

  return buffer.toString();
}
