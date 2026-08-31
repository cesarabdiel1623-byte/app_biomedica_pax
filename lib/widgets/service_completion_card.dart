import 'package:flutter/material.dart';
import '../models/service_completion.dart';

/// Tarjeta de presentación de lectura para que el cliente visualice
/// el resultado de la ejecución técnica de su servicio una vez finalizado.
class ServiceCompletionCard extends StatelessWidget {
  final ServiceCompletion serviceCompletion;
  final VoidCallback? onDownloadReportPdf;
  final bool isDownloadingPdf;

  const ServiceCompletionCard({
    super.key,
    required this.serviceCompletion,
    this.onDownloadReportPdf,
    this.isDownloadingPdf = false,
  });

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'No registrada';
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  List<String> _buildCombinedParts(ServiceCompletion sc) {
    final result = <String>[];
    final seen = <String>{};

    // 1. Refacciones libres ingresadas como texto
    if (sc.partsUsedNotes != null && sc.partsUsedNotes!.trim().isNotEmpty) {
      final lines = sc.partsUsedNotes!
          .trim()
          .split('\n')
          .map((l) => l.startsWith('•') ? l.substring(1).trim() : l.trim())
          .where((l) => l.isNotEmpty);
      for (final line in lines) {
        final key = line.toLowerCase();
        if (!seen.contains(key)) {
          seen.add(key);
          result.add(line);
        }
      }
    }

    // 2. Refacciones estructuradas asociadas (sin mostrar costos)
    for (final part in sc.partsUsed) {
      final name =
          part.productName?.trim() ?? 'Refacción biomédica (${part.productId})';
      final qtyStr = part.quantity == part.quantity.roundToDouble()
          ? part.quantity.toInt().toString()
          : part.quantity.toString();
      final formatted = '$name — $qtyStr ${qtyStr == '1' ? 'pieza' : 'piezas'}';
      final key = name.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        result.add(formatted);
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final combinedParts = _buildCombinedParts(serviceCompletion);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFBBF7D0), width: 1.5),
      ),
      color: const Color(0xFFF0FDF4),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.verified,
                    color: Color(0xFF16A34A),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Servicio Técnico Finalizado',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF14532D),
                        ),
                      ),
                      Text(
                        'Concluido: ${_formatDate(serviceCompletion.completedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFFBBF7D0), height: 24),

            // Diagnóstico Técnico
            if (serviceCompletion.diagnosis != null &&
                serviceCompletion.diagnosis!.isNotEmpty) ...[
              const Text(
                'Diagnóstico Técnico Final:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF166534),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                serviceCompletion.diagnosis!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1F2937),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Trabajo Realizado y Solución
            if (serviceCompletion.solution != null &&
                serviceCompletion.solution!.isNotEmpty) ...[
              const Text(
                'Trabajo Realizado y Solución:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF166534),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                serviceCompletion.solution!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1F2937),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Recomendaciones
            if (serviceCompletion.recommendations != null &&
                serviceCompletion.recommendations!.isNotEmpty) ...[
              const Text(
                'Recomendaciones del Especialista:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF166534),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                serviceCompletion.recommendations!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1F2937),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Refacciones / Materiales Utilizados
            const Text(
              'Refacciones / Materiales Utilizados:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF166534),
              ),
            ),
            const SizedBox(height: 6),
            if (combinedParts.isNotEmpty) ...[
              ...combinedParts.map(
                (partText) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 15,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          partText,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Ninguna',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],

            // Técnico asignado
            if (serviceCompletion.assignedTechnicianName != null) ...[
              Row(
                children: [
                  const Icon(
                    Icons.engineering,
                    size: 16,
                    color: Color(0xFF024C8B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Técnico Responsable: ${serviceCompletion.assignedTechnicianName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Botón para Descargar Orden de Servicio Oficial (Final)
            if (onDownloadReportPdf != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isDownloadingPdf ? null : onDownloadReportPdf,
                  icon: isDownloadingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF024C8B),
                          ),
                        )
                      : const Icon(
                          Icons.picture_as_pdf,
                          color: Color(0xFF024C8B),
                          size: 18,
                        ),
                  label: Text(
                    isDownloadingPdf
                        ? 'Generando documento...'
                        : 'Descargar Orden de Servicio Oficial (PDF)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Color(0xFF024C8B),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF024C8B),
                      width: 1.2,
                    ),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
