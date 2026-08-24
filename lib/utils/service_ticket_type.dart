class ServiceTicketType {
  static const preventivo = 'preventivo';
  static const correctivo = 'correctivo';
  static const reparacion = 'reparacion';
  static const diagnostico = 'diagnostico';

  static String normalize(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case preventivo:
        return preventivo;
      case correctivo:
      case reparacion:
        return correctivo;
      case diagnostico:
        return diagnostico;
      default:
        return type?.trim().toLowerCase() ?? '';
    }
  }

  static bool isCorrectiveFlow(String? type) => normalize(type) == correctivo;

  static String label(String? type, {String? title}) {
    final normalizedTitle = title?.trim().toLowerCase() ?? '';
    if (normalizedTitle.startsWith('reparación:')) {
      return 'Mantenimiento correctivo';
    }
    if (normalizedTitle.startsWith('soporte técnico:')) {
      return 'Soporte técnico';
    }

    switch (normalize(type)) {
      case preventivo:
        return 'Mantenimiento preventivo';
      case correctivo:
        return 'Mantenimiento correctivo';
      case diagnostico:
        return 'Diagnóstico';
      default:
        return type?.trim().isNotEmpty == true ? type!.trim() : 'Otro';
    }
  }
}
