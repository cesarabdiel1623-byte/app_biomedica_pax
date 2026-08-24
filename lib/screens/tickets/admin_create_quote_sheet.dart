import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/admin_quote_service.dart';
import '../../utils/price_formatter.dart';
import '../../utils/ui_helpers.dart';

class _ItemEntry {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController(text: '1');
  final TextEditingController priceController = TextEditingController(text: '0');
  final TextEditingController discountController = TextEditingController(text: '0');

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    discountController.dispose();
  }

  AdminQuoteItemDraft toDraft() {
    final qty = double.tryParse(qtyController.text.trim()) ?? 1.0;
    final price = double.tryParse(priceController.text.trim()) ?? 0.0;
    final discount = double.tryParse(discountController.text.trim()) ?? 0.0;

    return AdminQuoteItemDraft(
      productNameSnapshot: nameController.text.trim(),
      quantity: qty > 0 ? qty : 1.0,
      unitPrice: price >= 0 ? price : 0.0,
      discount: discount >= 0 ? discount : 0.0,
    );
  }
}

class AdminCreateQuoteSheet extends StatefulWidget {
  final String ticketId;
  final String ticketNumber;
  final String clientId;
  final String clientName;
  final String? equipmentSummary;

  const AdminCreateQuoteSheet({
    super.key,
    required this.ticketId,
    required this.ticketNumber,
    required this.clientId,
    required this.clientName,
    this.equipmentSummary,
  });

  @override
  State<AdminCreateQuoteSheet> createState() => _AdminCreateQuoteSheetState();
}

class _AdminCreateQuoteSheetState extends State<AdminCreateQuoteSheet> {
  final List<_ItemEntry> _items = [];
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _internalNotesController = TextEditingController();
  DateTime? _validUntil;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Iniciar con al menos una partida por defecto
    _addNewItem(defaultName: 'Mantenimiento Preventivo');
    // Vigencia sugerida: 15 días posteriores
    _validUntil = DateTime.now().add(const Duration(days: 15));
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _notesController.dispose();
    _internalNotesController.dispose();
    super.dispose();
  }

  void _addNewItem({String defaultName = ''}) {
    final entry = _ItemEntry();
    if (defaultName.isNotEmpty) {
      entry.nameController.text = defaultName;
    }
    setState(() {
      _items.add(entry);
    });
  }

  void _removeItem(int index) {
    if (_items.length <= 1) {
      UiHelpers.showErrorToast(
        context,
        'La cotización debe tener al menos un concepto.',
      );
      return;
    }
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  AdminQuotePreviewTotals get _previewTotals {
    final drafts = _items.map((e) => e.toDraft()).toList();
    return AdminQuotePreviewTotals.calculate(drafts);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _pickValidUntilDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? DateTime.now().add(const Duration(days: 15)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) {
      setState(() => _validUntil = picked);
    }
  }

  Future<void> _submitQuote({required bool sendImmediately}) async {
    if (_isSubmitting) return;

    // 1. Validaciones previas de UI
    final drafts = <AdminQuoteItemDraft>[];
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i].toDraft();
      try {
        item.validate();
        drafts.add(item);
      } catch (e) {
        UiHelpers.showErrorToast(
          context,
          'Partida #${i + 1}: ${e.toString().replaceAll('ArgumentError: ', '')}',
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final adminService = AdminQuoteService(Supabase.instance.client);

      // Crear borrador mediante RPC atómica
      final result = await adminService.createServiceQuoteDraft(
        serviceTicketId: widget.ticketId,
        items: drafts,
        validUntil: _validUntil,
        notes: _notesController.text.trim(),
      );

      final quoteId = result['quote_id']?.toString() ?? '';

      // Si se solicitó enviar inmediatamente al cliente
      if (sendImmediately && quoteId.isNotEmpty) {
        await adminService.sendServiceQuote(quoteId: quoteId);
      }

      if (!mounted) return;

      UiHelpers.showFloatingSuccessToast(
        context,
        sendImmediately
            ? 'Cotización enviada al cliente exitosamente.'
            : 'Cotización guardada en borrador.',
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      UiHelpers.showErrorToast(
        context,
        'Error al procesar la cotización: $msg',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _previewTotals;

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
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
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
                const Icon(Icons.request_quote_outlined, color: Color(0xFF0D9488)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nueva Cotización de Servicio',
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

            // Datos informativos (Solo lectura)
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
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Cliente: ${widget.clientName}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.confirmation_number_outlined, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        'Ticket: ${widget.ticketNumber}',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                  if (widget.equipmentSummary != null && widget.equipmentSummary!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.biotech_outlined, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Equipo: ${widget.equipmentSummary}',
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Selector de Vigencia
            InkWell(
              onTap: _pickValidUntilDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 18, color: Color(0xFF0D9488)),
                    const SizedBox(width: 8),
                    const Text('Válida hasta: ', style: TextStyle(fontSize: 13)),
                    Text(
                      _validUntil != null ? _formatDate(_validUntil!) : 'Sin vigencia',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Lista de Conceptos de Servicio
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Conceptos de Servicio',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                TextButton.icon(
                  onPressed: () => _addNewItem(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Agregar Concepto', style: TextStyle(fontSize: 12.5)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0D9488),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final draft = item.toDraft();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${idx + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: item.nameController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Ej. Diagnóstico técnico / Mantenimiento',
                              isDense: true,
                              border: UnderlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                            ),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_items.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _removeItem(idx),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Cantidad
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: item.qtyController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Cant.',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Precio Unitario
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: item.priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'P. Unitario (\$)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Descuento
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: item.discountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Desc. (\$)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total partida: ${formatFinancialPrice(draft.totalLinePrice)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D9488),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            // Notas para el cliente
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas para el cliente (Opcional)',
                hintText: 'Tiempos de entrega, términos o condiciones del servicio...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),

            // Resumen de Totales (PREVIEW)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal estimado:', style: TextStyle(fontSize: 13)),
                      Text(formatFinancialPrice(totals.subtotal), style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('IVA (16%):', style: TextStyle(fontSize: 13)),
                      Text(formatFinancialPrice(totals.tax), style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL ESTIMADO:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        formatFinancialPrice(totals.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0D9488),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Botones de acción
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => _submitQuote(sendImmediately: false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar Borrador'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _submitQuote(sendImmediately: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Enviar al Cliente'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
