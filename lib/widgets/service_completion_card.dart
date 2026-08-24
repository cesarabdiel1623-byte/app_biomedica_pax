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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasParts = serviceCompletion.partsUsed.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
      ),
      color: const Color(0xFFF0FDFA),
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
                    color: const Color(0xFFCCFBF1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.verified, color: Color(0xFF0F766E), size: 22),
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
                          color: const Color(0xFF134E4A),
                        ),
                      ),
                      Text(
                        'Concluido: ${_formatDate(serviceCompletion.completedAt)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF0F766E)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF99F6E4), height: 24),

            // Diagnóstico Técnico
            if (serviceCompletion.diagnosis != null && serviceCompletion.diagnosis!.isNotEmpty) ...[
              const Text(
                'Diagnóstico Técnico Final:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF115E59)),
              ),
              const SizedBox(height: 3),
              Text(
                serviceCompletion.diagnosis!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937), height: 1.3),
              ),
              const SizedBox(height: 12),
            ],

            // Trabajo Realizado y Solución
            if (serviceCompletion.solution != null && serviceCompletion.solution!.isNotEmpty) ...[
              const Text(
                'Trabajo Realizado y Solución:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF115E59)),
              ),
              const SizedBox(height: 3),
              Text(
                serviceCompletion.solution!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937), height: 1.3),
              ),
              const SizedBox(height: 12),
            ],

            // Recomendaciones
            if (serviceCompletion.recommendations != null &&
                serviceCompletion.recommendations!.isNotEmpty) ...[
              const Text(
                'Recomendaciones del Especialista:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF115E59)),
              ),
              const SizedBox(height: 3),
              Text(
                serviceCompletion.recommendations!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937), height: 1.3),
              ),
              const SizedBox(height: 12),
            ],

            // Refacciones Empleadas (Sin costos unitarios)
            if (hasParts) ...[
              const Text(
                'Refacciones / Materiales Utilizados:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF115E59)),
              ),
              const SizedBox(height: 6),
              ...serviceCompletion.partsUsed.map(
                (part) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF0D9488)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          part.productName ?? 'Refacción biomédica (${part.productId})',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF374151)),
                        ),
                      ),
                      Text(
                        'Cant: ${part.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF115E59)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Técnico asignado
            if (serviceCompletion.assignedTechnicianName != null) ...[
              Row(
                children: [
                  const Icon(Icons.engineering, size: 16, color: Color(0xFF0D9488)),
                  const SizedBox(width: 6),
                  Text(
                    'Técnico Responsable: ${serviceCompletion.assignedTechnicianName}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F766E)),
                        )
                      : const Icon(Icons.picture_as_pdf, color: Color(0xFF0F766E), size: 18),
                  label: Text(
                    isDownloadingPdf ? 'Generando documento...' : 'Descargar Orden de Servicio Oficial (PDF)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0F766E)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0D9488), width: 1.2),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
