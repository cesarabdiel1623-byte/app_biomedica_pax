import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/service_completion.dart';
import '../../services/admin_service_order_service.dart';
import '../../utils/ui_helpers.dart';

class AdminCompleteServiceOrderSheet extends StatefulWidget {
  final String ticketId;
  final String ticketNumber;
  final String clientName;
  final String? equipmentSummary;
  final String currentTicketStatus;
  final ServiceCompletion? initialServiceOrder;

  const AdminCompleteServiceOrderSheet({
    super.key,
    required this.ticketId,
    required this.ticketNumber,
    required this.clientName,
    this.equipmentSummary,
    required this.currentTicketStatus,
    this.initialServiceOrder,
  });

  @override
  State<AdminCompleteServiceOrderSheet> createState() =>
      _AdminCompleteServiceOrderSheetState();
}

class _FreePartEntry {
  final TextEditingController nameController;
  final TextEditingController quantityController;

  _FreePartEntry({String name = '', String quantity = '1'})
    : nameController = TextEditingController(text: name),
      quantityController = TextEditingController(text: quantity);

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
  }
}

class _AdminCompleteServiceOrderSheetState
    extends State<AdminCompleteServiceOrderSheet> {
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _solutionController = TextEditingController();
  final TextEditingController _recommendationsController =
      TextEditingController();

  final List<_FreePartEntry> _freeParts = [];

  ServiceCompletion? _serviceOrder;
  bool _isLoading = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _serviceOrder = widget.initialServiceOrder;
    if (_serviceOrder != null) {
      _diagnosisController.text = _serviceOrder!.diagnosis ?? '';
      _solutionController.text = _serviceOrder!.solution ?? '';
      _recommendationsController.text = _serviceOrder!.recommendations ?? '';
      _initFreePartsFromNotes(_serviceOrder!.partsUsedNotes);
    } else {
      _loadDetails();
    }
  }

  void _initFreePartsFromNotes(String? notes) {
    _freeParts.clear();
    if (notes == null || notes.trim().isEmpty) return;
    final lines = notes.split('\n');
    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.startsWith('•')) line = line.substring(1).trim();
      if (line.isEmpty) continue;

      // Check if ends with (Cant: X) or (X)
      final cantMatch = RegExp(
        r'^(.*?)\s*\((?:Cant:\s*)?([0-9.]+)\)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (cantMatch != null) {
        _freeParts.add(
          _FreePartEntry(
            name: cantMatch.group(1)?.trim() ?? line,
            quantity: cantMatch.group(2)?.trim() ?? '1',
          ),
        );
      } else {
        _freeParts.add(_FreePartEntry(name: line, quantity: '1'));
      }
    }
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _solutionController.dispose();
    _recommendationsController.dispose();
    for (final part in _freeParts) {
      part.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final service = AdminServiceOrderService(Supabase.instance.client);
      final details = await service.getServiceOrderDetails(widget.ticketId);
      if (mounted) {
        setState(() {
          _serviceOrder = details;
          if (details != null) {
            if (_diagnosisController.text.isEmpty) {
              _diagnosisController.text = details.diagnosis ?? '';
            }
            if (_solutionController.text.isEmpty) {
              _solutionController.text = details.solution ?? '';
            }
            if (_recommendationsController.text.isEmpty) {
              _recommendationsController.text = details.recommendations ?? '';
            }
            if (_freeParts.isEmpty && details.partsUsedNotes != null) {
              _initFreePartsFromNotes(details.partsUsedNotes);
            }
          }
        });
      }
    } catch (_) {
      // Manejo silencioso en carga inicial
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _isReadOnly =>
      _serviceOrder?.status == 'resolved' ||
      _serviceOrder?.status == 'closed' ||
      widget.currentTicketStatus == 'resolved' ||
      widget.currentTicketStatus == 'closed';

  void _addFreePart() {
    setState(() {
      _freeParts.add(_FreePartEntry());
    });
  }

  void _removeFreePart(int index) {
    setState(() {
      final removed = _freeParts.removeAt(index);
      removed.dispose();
    });
  }

  String? _buildPartsUsedNotes() {
    final lines = <String>[];
    for (final part in _freeParts) {
      final name = part.nameController.text.trim();
      final qty = part.quantityController.text.trim();
      if (name.isNotEmpty) {
        if (qty.isNotEmpty && qty != '1') {
          lines.add('• $name (Cant: $qty)');
        } else {
          lines.add('• $name');
        }
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  Future<void> _startService() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final service = AdminServiceOrderService(Supabase.instance.client);
      await service.startServiceOrder(ticketId: widget.ticketId);
      if (!mounted) return;

      UiHelpers.showFloatingSuccessToast(
        context,
        'Servicio iniciado exitosamente.',
      );
      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showErrorToast(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _completeService() async {
    if (_isSubmitting) return;

    if (_serviceOrder == null) {
      UiHelpers.showErrorToast(
        context,
        'La orden de servicio no ha sido iniciada.',
      );
      return;
    }

    try {
      AdminServiceOrderService.validateCompletionInput(
        diagnosis: _diagnosisController.text,
        solution: _solutionController.text,
      );
    } catch (e) {
      UiHelpers.showErrorToast(
        context,
        e.toString().replaceAll('ArgumentError: ', ''),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final service = AdminServiceOrderService(Supabase.instance.client);
      await service.completeServiceOrder(
        serviceOrderId: _serviceOrder!.id,
        diagnosis: _diagnosisController.text.trim(),
        solution: _solutionController.text.trim(),
        recommendations: _recommendationsController.text.trim(),
        partsUsedNotes: _buildPartsUsedNotes(),
      );

      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(
        context,
        'Orden de servicio completada exitosamente.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showErrorToast(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _closeTicket() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final service = AdminServiceOrderService(Supabase.instance.client);
      await service.closeServiceTicket(ticketId: widget.ticketId);

      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(
        context,
        'Ticket cerrado definitivamente.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showErrorToast(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Encabezado
                  Row(
                    children: [
                      const Icon(
                        Icons.engineering_outlined,
                        color: Color(0xFF024C8B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ejecución Técnica de Servicio',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const Divider(),

                  // Resumen de Ticket
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ticket: ${widget.ticketNumber} · Estado: ${widget.currentTicketStatus.toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cliente: ${widget.clientName}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                        if (widget.equipmentSummary != null &&
                            widget.equipmentSummary!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Equipo: ${widget.equipmentSummary}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_serviceOrder == null &&
                      widget.currentTicketStatus != 'in_progress') ...[
                    // Botón para Iniciar Servicio
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _startService,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Iniciar Ejecución Técnica'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF024C8B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Formulario de Captura Técnica
                    TextFormField(
                      controller: _diagnosisController,
                      readOnly: _isReadOnly,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Diagnóstico Técnico Final *',
                        hintText:
                            'Causa raíz identificada durante la revisión...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _solutionController,
                      readOnly: _isReadOnly,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Trabajo Realizado y Solución *',
                        hintText:
                            'Acciones correctivas, ajustes, calibración y pruebas realizadas...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _recommendationsController,
                      readOnly: _isReadOnly,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Recomendaciones al Cliente (Opcional)',
                        hintText:
                            'Condiciones de operación, fechas de mantenimiento sugeridas...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // REFACCIONES Y PARTES UTILIZADAS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'REFACCIONES Y PARTES UTILIZADAS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (!_isReadOnly)
                          TextButton.icon(
                            onPressed: _addFreePart,
                            icon: const Icon(
                              Icons.add,
                              size: 18,
                              color: Color(0xFF024C8B),
                            ),
                            label: const Text(
                              'Agregar refacción',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF024C8B),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Text(
                      'Registra las piezas o materiales utilizados durante el servicio.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),

                    if (_freeParts.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'No se utilizaron refacciones.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ] else ...[
                      ..._freeParts.asMap().entries.map((entry) {
                        final index = entry.key;
                        final part = entry.value;

                        if (_isReadOnly) {
                          final name = part.nameController.text.trim();
                          final qty = part.quantityController.text.trim();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                  color: Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                if (qty.isNotEmpty && qty != '1')
                                  Text(
                                    'Cant: $qty',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: Color(0xFF024C8B),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 7,
                                child: TextFormField(
                                  controller: part.nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Refacción / pieza / material',
                                    hintText:
                                        'Ej. Fusible 5A, Cable de poder...',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: part.quantityController,
                                  keyboardType: TextInputType.text,
                                  decoration: const InputDecoration(
                                    labelText: 'Cant.',
                                    hintText: '1',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFEF4444),
                                  size: 20,
                                ),
                                tooltip: 'Eliminar',
                                onPressed: () => _removeFreePart(index),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Si existen partes de almacén estructuradas heredadas de otros flujos, mostrarlas sin romper
                    if (_serviceOrder?.partsUsed.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Refacciones de inventario registradas:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._serviceOrder!.partsUsed.map(
                        (p) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.inventory_2_outlined,
                            size: 18,
                            color: Color(0xFF024C8B),
                          ),
                          title: Text(
                            p.productName ?? p.productId,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          trailing: Text(
                            'Cant: ${p.quantity}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Botones de acción según estado
                    if (!_isReadOnly)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _completeService,
                          icon: const Icon(Icons.check_circle_outline),
                          label: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Completar Orden de Servicio'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF024C8B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      )
                    else if (widget.currentTicketStatus == 'resolved')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _closeTicket,
                          icon: const Icon(Icons.lock_outline),
                          label: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Cerrar Ticket Definitivamente'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF334155),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
