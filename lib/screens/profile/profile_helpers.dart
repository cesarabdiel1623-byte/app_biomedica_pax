import 'package:flutter/material.dart';

const kPrimary = Color(0xFF0D9488);
const kNavy = Color(0xFF1E3A5F);
const kGreen = Color(0xFF16A34A);
const kRed = Color(0xFFEF4444);
const kOrange = Color(0xFFF59E0B);

String formatCurrency(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final buf = StringBuffer();
  for (int i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
    buf.write(parts[0][i]);
  }
  return '\$$buf.${parts[1]} MXN';
}

String getEffectiveStatus(Map<String, dynamic> q) {
  final status = q['status'] ?? '';
  if (status == 'sent' || status == 'draft') {
    final validUntilStr = q['valid_until'];
    if (validUntilStr != null) {
      final validDate = DateTime.tryParse(validUntilStr)?.toLocal();
      if (validDate != null && DateTime.now().isAfter(validDate)) {
        return 'expired';
      }
    }
  }
  return status;
}
