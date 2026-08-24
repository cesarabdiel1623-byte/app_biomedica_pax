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
  State<AdminCompleteServiceOrderSheet> createState() => _AdminCompleteServiceOrderSheetState();
}

class _AdminCompleteServiceOrderSheetState extends State<AdminCompleteServiceOrderSheet> {
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _solutionController = TextEditingController();
  final TextEditingController _recommendationsController = TextEditingController();

  // Para captura de refacción rápida
  final TextEditingController _partProductIdController = TextEditingController();
  final TextEditingController _partWarehouseIdController = TextEditingController();
  final TextEditingController _partQtyController = TextEditingController(text: '1');

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
    } else {
      _loadDetails();
    }
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _solutionController.dispose();
    _recommendationsController.dispose();
    _partProductIdController.dispose();
    _partWarehouseIdController.dispose();
    _partQtyController.dispose();
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

  Future<void> _startService() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final service = AdminServiceOrderService(Supabase.instance.client);
      await service.startServiceOrder(ticketId: widget.ticketId);
      if (!mounted) return;

      UiHelpers.showFloatingSuccessToast(context, 'Servicio iniciado exitosamente.');
      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showErrorToast(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _registerPart() async {
    if (_serviceOrder == null) {
      UiHelpers.showErrorToast(context, 'Debes iniciar el servicio antes de registrar partes.');
      return;
    }

    final pId = _partProductIdController.text.trim();
    final wId = _partWarehouseIdController.text.trim();
    final qty = double.tryParse(_partQtyController.text.trim()) ?? 0.0;

    if (pId.isEmpty || wId.isEmpty || qty <= 0) {
      UiHelpers.showErrorToast(context, 'Ingresa ID de producto, almacén y cantidad > 0.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final service = AdminServiceOrderService(Supabase.instance.client);
      await service.registerPartUsage(
        serviceOrderId: _serviceOrder!.id,
        productId: pId,
        warehouseId: wId,
        quantity: qty,
      );

      if (!mounted) return;
      _partProductIdController.clear();
      _partQtyController.text = '1';
      UiHelpers.showFloatingSuccessToast(context, 'Refacción registrada en inventario.');
      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showErrorToast(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _completeService() async {
    if (_isSubmitting) return;

    if (_serviceOrder == null) {
      UiHelpers.showErrorToast(context, 'La orden de servicio no ha sido iniciada.');
      return;
    }

    try {
      AdminServiceOrderService.validateCompletionInput(
        diagnosis: _diagnosisController.text,
        solution: _solutionController.text,
      );
    } catch (e) {
      UiHelpers.showErrorToast(context, e.toString().replaceAll('ArgumentError: ', ''));
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
      );

      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(context, 'Orden de servicio completada exitosamente.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showErrorToast(context, e.toString().replaceAll('Exception: ', ''));
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
      UiHelpers.showFloatingSuccessToast(context, 'Ticket cerrado definitivamente.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showErrorToast(context, e.toString().replaceAll('Exception: ', ''));
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
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
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
                      const Icon(Icons.engineering_outlined, color: Color(0xFF0D9488)),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cliente: ${widget.clientName}',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                        ),
                        if (widget.equipmentSummary != null && widget.equipmentSummary!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Equipo: ${widget.equipmentSummary}',
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_serviceOrder == null && widget.currentTicketStatus != 'in_progress') ...[
                    // Botón para Iniciar Servicio
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _startService,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Iniciar Ejecución Técnica'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        hintText: 'Causa raíz identificada durante la revisión...',
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
                        hintText: 'Acciones correctivas, ajustes, calibración y pruebas realizadas...',
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
                        hintText: 'Condiciones de operación, fechas de mantenimiento sugeridas...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Refacciones Utilizadas
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Refacciones Físicas Empleadas',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        if (_serviceOrder?.partsUsed.isNotEmpty == true)
                          Text(
                            '${_serviceOrder!.partsUsed.length} registradas',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    if (_serviceOrder?.partsUsed.isEmpty ?? true)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Center(
                          child: Text(
                            'No se han registrado refacciones consumidas de almacén.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ),
                      )
                    else
                      ..._serviceOrder!.partsUsed.map(
                        (p) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.settings_suggest, size: 20, color: Color(0xFF0D9488)),
                          title: Text(p.productName ?? p.productId, style: const TextStyle(fontSize: 12.5)),
                          trailing: Text(
                            'Cant: ${p.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                          ),
                        ),
                      ),

                    if (!_isReadOnly) ...[
                      const SizedBox(height: 8),
                      // Formulario pequeño para agregar refacción
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _partProductIdController,
                                decoration: const InputDecoration(
                                  hintText: 'Product UUID',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _partWarehouseIdController,
                                decoration: const InputDecoration(
                                  hintText: 'Almacén UUID',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _partQtyController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  hintText: 'Cant',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Color(0xFF0D9488)),
                              onPressed: _isSubmitting ? null : _registerPart,
                            ),
                          ],
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
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Completar Orden de Servicio'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Cerrar Ticket Definitivamente'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF334155),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
