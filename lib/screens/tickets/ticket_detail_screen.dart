import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../models/quote.dart';
import '../../models/service_completion.dart';
import '../../models/service_order_presentation.dart';
import '../../models/service_ticket.dart';
import '../../models/ticket_message.dart';
import '../../services/admin_quote_service.dart';
import '../../services/mercado_pago_service.dart';
import '../../services/service_order_pdf_service.dart';
import '../../services/ticket_service.dart';
import '../../utils/price_formatter.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';
import '../../widgets/service_completion_card.dart';
import '../profile/orders_screen.dart';
import 'admin_create_quote_sheet.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kBg = Color(0xFFF8FAFC);
const _kRed = Color(0xFFEF4444);

class TicketDetailScreen extends StatefulWidget {
  final String? ticketId;
  final String? ticketNumber;

  const TicketDetailScreen({super.key, this.ticketId, this.ticketNumber})
    : assert(
        ticketId != null || ticketNumber != null,
        'ticketId or ticketNumber required',
      );

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  ServiceTicket? _ticket;
  ServiceQuote? _serviceQuote;
  ServiceCompletion? _serviceCompletion;
  bool _loading = true;
  bool _loadingQuote = false;
  bool _loadingCompletion = false;
  bool _submittingQuoteResponse = false;
  bool _submittingQuotePayment = false;
  String? _error;
  List<TicketMessage> _messages = [];
  bool _loadingMessages = true;
  bool _uploadingFile = false;
  bool _generatingServiceOrderPdf = false;
  bool _generatingFinalServiceOrderPdf = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ServiceOrderPdfService _serviceOrderPdfService =
      ServiceOrderPdfService();
  RealtimeChannel? _chatChannel;

  String get _effectiveTicketId => _ticket?.id ?? widget.ticketId ?? '';

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadTicket() async {
    if (!mounted) return;
    final isInitial = _ticket == null;
    setState(() {
      if (isInitial) {
        _loading = true;
      }
      _error = null;
    });
    try {
      Future<ServiceTicket?> fetchFuture;
      if (widget.ticketId != null && widget.ticketId!.isNotEmpty) {
        fetchFuture = TicketService.getTicketById(widget.ticketId!);
      } else if (widget.ticketNumber != null &&
          widget.ticketNumber!.isNotEmpty) {
        fetchFuture = TicketService.getTicketByNumber(widget.ticketNumber!);
      } else {
        fetchFuture = Future.value(null);
      }

      final results = await Future.wait([
        fetchFuture.timeout(const Duration(seconds: 30)),
        if (isInitial) Future.delayed(const Duration(seconds: 2)),
      ]);

      final ticket = results[0] as ServiceTicket?;
      if (mounted) {
        setState(() {
          _ticket = ticket;
          _loading = false;
        });
        if (ticket != null) {
          _loadQuote();
          _loadServiceCompletion();
          _loadMessages();
          _subscribeToChat();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadQuote() async {
    final ticketId = _effectiveTicketId.trim();
    if (ticketId.isEmpty) return;
    setState(() => _loadingQuote = true);
    try {
      final quote = await TicketService.getRelevantServiceQuote(ticketId);
      if (mounted) {
        setState(() {
          _serviceQuote = quote;
          _loadingQuote = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading service quote: $e');
      if (mounted) {
        setState(() {
          _loadingQuote = false;
        });
      }
    }
  }

  Future<void> _loadServiceCompletion() async {
    final ticketId = _effectiveTicketId.trim();
    if (ticketId.isEmpty) return;
    setState(() => _loadingCompletion = true);
    try {
      final completion = await TicketService.getServiceCompletion(ticketId);
      if (mounted) {
        setState(() {
          _serviceCompletion = completion;
          _loadingCompletion = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading service completion: $e');
      if (mounted) {
        setState(() {
          _loadingCompletion = false;
        });
      }
    }
  }

  Future<void> _confirmAcceptQuote(ServiceQuote quote) async {
    if (_submittingQuoteResponse) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: _kPrimary, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '¿Aceptar cotización?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Al aceptar la cotización Folio ${quote.quoteNumber} por un total de ${formatFinancialPrice(quote.total)}, se confirmará la propuesta económica para proceder con el servicio técnico.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Aceptar Cotización',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submittingQuoteResponse = true);
    try {
      await TicketService.acceptServiceQuote(quote.id);
      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(
        context,
        'Cotización aceptada exitosamente.',
      );
      await _loadQuote();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      UiHelpers.showErrorToast(
        context,
        'No se pudo aceptar la cotización: $msg',
      );
    } finally {
      if (mounted) {
        setState(() => _submittingQuoteResponse = false);
      }
    }
  }

  Future<void> _confirmRejectQuote(ServiceQuote quote) async {
    if (_submittingQuoteResponse) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: _kRed, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '¿Rechazar cotización?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '¿Confirmas que deseas rechazar la cotización Folio ${quote.quoteNumber}? Esta acción no se puede deshacer.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Rechazar Cotización',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submittingQuoteResponse = true);
    try {
      await TicketService.rejectServiceQuote(quote.id);
      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(context, 'Cotización rechazada.');
      await _loadQuote();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      UiHelpers.showErrorToast(
        context,
        'No se pudo rechazar la cotización: $msg',
      );
    } finally {
      if (mounted) {
        setState(() => _submittingQuoteResponse = false);
      }
    }
  }

  Future<void> _startQuotePayment(ServiceQuote quote) async {
    if (_submittingQuotePayment) return;

    setState(() => _submittingQuotePayment = true);
    try {
      final service = MercadoPagoService(Supabase.instance.client);
      final result = await service.startServiceQuotePayment(quoteId: quote.id);

      if (!mounted) return;

      if (result.alreadyPaid) {
        UiHelpers.showFloatingSuccessToast(
          context,
          'Esta cotización ya cuenta con un pago aprobado.',
        );
      } else {
        UiHelpers.showFloatingSuccessToast(
          context,
          'Abriendo Mercado Pago para completar tu pago...',
        );
      }

      // Al volver o tras la respuesta, refrescar la cotización y el ticket
      if (mounted) {
        await _loadQuote();
        await _loadTicket();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      UiHelpers.showErrorToast(context, 'No se pudo iniciar el pago: $msg');
    } finally {
      if (mounted) {
        setState(() => _submittingQuotePayment = false);
      }
    }
  }

  void _viewConvertedOrder(ServiceQuote quote) {
    if (quote.clientId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrdersScreen(clientId: quote.clientId),
        ),
      );
    }
  }

  Future<void> _openCreateQuoteSheet(ServiceTicket ticket) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AdminCreateQuoteSheet(
        ticketId: ticket.id,
        ticketNumber: ticket.ticketNumber,
        clientId: ticket.clientId ?? '',
        clientName: ticket.clientName ?? 'Cliente',
        equipmentSummary: ticket.equipmentSummary,
      ),
    );

    if (result == true && mounted) {
      await _loadQuote();
      await _loadTicket();
    }
  }

  Future<void> _confirmSendQuote(ServiceQuote quote) async {
    if (_submittingQuoteResponse) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.send_rounded, color: _kPrimary, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '¿Enviar cotización al cliente?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Se enviará formalmente la cotización Folio ${quote.quoteNumber} por un total de ${formatFinancialPrice(quote.total)} al cliente. El cliente podrá revisarla y proceder al pago.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Enviar al Cliente',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submittingQuoteResponse = true);
    try {
      final adminService = AdminQuoteService(Supabase.instance.client);
      await adminService.sendServiceQuote(quoteId: quote.id);
      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(
        context,
        'Cotización enviada al cliente exitosamente.',
      );
      await _loadQuote();
      await _loadTicket();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      UiHelpers.showErrorToast(
        context,
        'No se pudo enviar la cotización: $msg',
      );
    } finally {
      if (mounted) {
        setState(() => _submittingQuoteResponse = false);
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await TicketService.getTicketMessages(_effectiveTicketId);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loadingMessages = false;
        });
        _scrollToBottom();
        TicketService.markMessagesAsRead(_effectiveTicketId);
      }
    } catch (e) {
      debugPrint('Error loading chat messages: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _subscribeToChat() {
    _chatChannel?.unsubscribe();
    final client = Supabase.instance.client;

    _chatChannel = client
        .channel(
          'public:service_ticket_messages:ticket_id=eq.$_effectiveTicketId',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: _effectiveTicketId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            if (record.isEmpty) return;
            final newId = record['id'] as String?;
            if (newId != null) {
              final index = _messages.indexWhere((m) => m.id == newId);

              final res = await client
                  .from('service_ticket_messages')
                  .select('*, profiles:sender_profile_id(full_name)')
                  .eq('id', newId)
                  .eq('is_internal', false)
                  .maybeSingle();

              if (res != null && mounted) {
                final messageJson = Map<String, dynamic>.from(res);
                messageJson['attachment_url'] =
                    await TicketService.resolveAttachmentUrl(
                      messageJson['attachment_url'] as String?,
                    );
                final msg = TicketMessage.fromJson(messageJson);
                if (!msg.isInternal) {
                  setState(() {
                    if (index == -1) {
                      _messages.add(msg);
                      _scrollToBottom();

                      if (msg.senderType != 'client') {
                        TicketService.markMessagesAsRead(_effectiveTicketId);
                      }
                    } else {
                      _messages[index] = msg;
                    }
                  });
                }
              }
            }
          },
        );

    _chatChannel!.subscribe();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return const Color(0xFF3B82F6);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'resolved':
        return const Color(0xFF16A34A);
      case 'closed':
        return Colors.grey;
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical':
        return const Color(0xFF7C3AED);
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year} - $hour:$minute hrs';
  }

  bool get _canChat {
    final status = _ticket?.status.toLowerCase();
    return status != 'resolved' &&
        status != 'closed' &&
        status != 'cancelled' &&
        status != 'canceled';
  }

  Widget _buildChatCard(ServiceTicket ticket) {
    final curUserId = Supabase.instance.client.auth.currentUser?.id;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, color: _kPrimary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Chat de Soporte Técnico',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _kNavy,
                  ),
                ),
                const Spacer(),
                if (_loadingMessages)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kPrimary,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            color: const Color(0xFFF8FAFC),
            child: _loadingMessages
                ? const Center(
                    child: CircularProgressIndicator(color: _kPrimary),
                  )
                : _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _kPrimary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: _kPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Sin mensajes aún',
                          style: TextStyle(
                            color: _kNavy,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Envía un mensaje para comunicarte con el equipo de soporte técnico.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe =
                          msg.senderType == 'client' &&
                          msg.senderProfileId == curUserId;
                      return _ChatBubbleItem(
                        key: ValueKey(msg.id),
                        message: msg,
                        isMe: isMe,
                        curUserId: curUserId,
                        onAttachmentTap: () =>
                            _openAttachment(msg.attachmentUrl!),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          if (_canChat)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: _uploadingFile
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kPrimary,
                            ),
                          )
                        : const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Color(0xFF64748B),
                            size: 24,
                          ),
                    onPressed: _uploadingFile ? null : _pickAndUploadImage,
                    tooltip: 'Adjuntar imágenes',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: _kPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ticket resuelto/cerrado. Chat archivado.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await TicketService.sendTicketMessage(_effectiveTicketId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar mensaje: $e'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  void _openAttachment(String attachmentUrl) {
    final trustedUrl = UiHelpers.sanitizeTrustedRemoteUrl(attachmentUrl);
    if (trustedUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El adjunto no pudo validarse de forma segura.'),
          backgroundColor: _kRed,
        ),
      );
      return;
    }

    if (_isVideoAttachment(trustedUrl)) {
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        useSafeArea: false,
        builder: (_) => _VideoAttachmentViewer(videoUrl: trustedUrl),
      );
      return;
    }

    _showFullImageLightbox(trustedUrl);
  }

  Future<void> _openServiceOrderPdf() async {
    if (_generatingServiceOrderPdf) return;

    final ticketId = _effectiveTicketId.trim();
    if (ticketId.isEmpty) {
      UiHelpers.showErrorToast(
        context,
        'No se encontró el ticket de servicio.',
      );
      return;
    }

    setState(() {
      _generatingServiceOrderPdf = true;
    });

    try {
      final result = await _serviceOrderPdfService.generate(ticketId: ticketId);
      if (!mounted) return;

      final trustedUrl = UiHelpers.sanitizeTrustedRemoteUrl(result.signedUrl);
      if (trustedUrl == null) {
        UiHelpers.showErrorToast(
          context,
          'La orden de servicio no pudo validarse de forma segura.',
        );
        return;
      }

      final launched = await launchUrl(
        Uri.parse(trustedUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        UiHelpers.showErrorToast(
          context,
          'No se pudo abrir la orden de servicio.',
        );
      }
    } on ServiceOrderPdfException catch (e) {
      debugPrint(
        'ServiceOrderPdfService failed: status=${e.status ?? 'unknown'}',
      );
      if (mounted) {
        UiHelpers.showErrorToast(context, e.message);
      }
    } catch (e) {
      debugPrint('ServiceOrderPdfService failed: ${e.runtimeType}');
      if (mounted) {
        UiHelpers.showErrorToast(
          context,
          'No se pudo generar la orden de servicio.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingServiceOrderPdf = false;
        });
      }
    }
  }

  Future<void> _openFinalServiceOrderPdf() async {
    if (_generatingFinalServiceOrderPdf) return;

    final ticketId = _effectiveTicketId.trim();
    if (ticketId.isEmpty) {
      UiHelpers.showErrorToast(
        context,
        'No se encontró el ticket de servicio.',
      );
      return;
    }

    setState(() {
      _generatingFinalServiceOrderPdf = true;
    });

    try {
      final result = await _serviceOrderPdfService.generate(
        ticketId: ticketId,
        documentType: 'final',
      );
      if (!mounted) return;

      final trustedUrl = UiHelpers.sanitizeTrustedRemoteUrl(result.signedUrl);
      if (trustedUrl == null) {
        UiHelpers.showErrorToast(
          context,
          'La orden de servicio no pudo validarse de forma segura.',
        );
        return;
      }

      final launched = await launchUrl(
        Uri.parse(trustedUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        UiHelpers.showErrorToast(
          context,
          'No se pudo abrir la orden de servicio.',
        );
      }
    } on ServiceOrderPdfException catch (e) {
      debugPrint(
        'ServiceOrderPdfService final failed: status=${e.status ?? 'unknown'}',
      );
      if (mounted) {
        UiHelpers.showErrorToast(context, e.message);
      }
    } catch (e) {
      debugPrint('ServiceOrderPdfService final failed: ${e.runtimeType}');
      if (mounted) {
        UiHelpers.showErrorToast(
          context,
          'No se pudo generar la orden de servicio final.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingFinalServiceOrderPdf = false;
        });
      }
    }
  }

  void _showFullImageLightbox(String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      builder: (context) {
        return Scaffold(
          backgroundColor: Colors.black.withValues(alpha: 0.95),
          body: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.65),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingFile) return;
    setState(() {
      _uploadingFile = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _uploadingFile = false;
        });
        return;
      }

      final validFiles = result.files.where((f) => f.bytes != null).toList();
      if (validFiles.isEmpty) {
        setState(() {
          _uploadingFile = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudieron leer los bytes de los archivos.'),
              backgroundColor: _kRed,
            ),
          );
        }
        return;
      }

      await _showMultiImagePreviewDialog(validFiles);
    } catch (e) {
      setState(() {
        _uploadingFile = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar archivos: $e'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  Future<void> _showMultiImagePreviewDialog(List<PlatformFile> files) async {
    final captionController = TextEditingController();
    int currentIndex = 0;

    List<PlatformFile> dialogFiles = List.from(files);
    final PageController pageController = PageController();

    Widget buildThumbnailsList(StateSetter setDialogState) {
      return SizedBox(
        height: 70,
        child: Center(
          child: ListView.separated(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemCount: dialogFiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final file = dialogFiles[idx];
              final isSelected = idx == currentIndex;

              return GestureDetector(
                onTap: () {
                  setDialogState(() {
                    currentIndex = idx;
                  });
                  pageController.jumpToPage(idx);
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Image.memory(
                          file.bytes!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        if (isSelected)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.4),
                              child: Center(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    setDialogState(() {
                                      dialogFiles.removeAt(idx);
                                      if (currentIndex >= dialogFiles.length &&
                                          dialogFiles.isNotEmpty) {
                                        currentIndex = dialogFiles.length - 1;
                                      }
                                    });
                                    if (dialogFiles.isEmpty) {
                                      Navigator.pop(context);
                                    } else {
                                      pageController.jumpToPage(currentIndex);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (context) {
        bool isSent = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  if (dialogFiles.isNotEmpty)
                    PageView.builder(
                      controller: pageController,
                      itemCount: dialogFiles.length,
                      onPageChanged: (idx) {
                        setDialogState(() {
                          currentIndex = idx;
                        });
                      },
                      itemBuilder: (context, idx) {
                        final file = dialogFiles[idx];
                        final bytes = file.bytes!;
                        return InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                        );
                      },
                    )
                  else
                    const Center(
                      child: Text(
                        'No hay archivos seleccionados',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.65),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Align(
                            alignment: Alignment.topRight,
                            child: CircleAvatar(
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.4,
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (dialogFiles.isNotEmpty)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85),
                              Colors.transparent,
                            ],
                            stops: const [0.65, 1.0],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (dialogFiles.length > 1) ...[
                                  buildThumbnailsList(setDialogState),
                                  const SizedBox(height: 16),
                                ],

                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () async {
                                        try {
                                          final addResult =
                                              await FilePicker.pickFiles(
                                                type: FileType.custom,
                                                allowedExtensions: [
                                                  'jpg',
                                                  'jpeg',
                                                  'png',
                                                  'webp',
                                                ],
                                                allowMultiple: true,
                                                withData: true,
                                              );
                                          if (addResult != null &&
                                              addResult.files.isNotEmpty) {
                                            final newFiles = addResult.files
                                                .where((f) => f.bytes != null)
                                                .toList();
                                            if (newFiles.isNotEmpty) {
                                              setDialogState(() {
                                                dialogFiles.addAll(newFiles);
                                              });
                                            }
                                          }
                                        } catch (e) {
                                          debugPrint(
                                            'Error picking additional files: $e',
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.15,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.add_photo_alternate_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.25,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        child: TextField(
                                          controller: captionController,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                          maxLines: 4,
                                          minLines: 1,
                                          decoration: InputDecoration(
                                            hintText: 'Añade un comentario...',
                                            hintStyle: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 14,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 10,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    GestureDetector(
                                      onTap: isSent
                                          ? null
                                          : () {
                                              setDialogState(() {
                                                isSent = true;
                                              });
                                              Navigator.pop(context, {
                                                'caption': captionController
                                                    .text
                                                    .trim(),
                                                'files': dialogFiles,
                                              });
                                            },
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: isSent
                                              ? Colors.grey.shade600
                                              : _kPrimary,
                                          shape: BoxShape.circle,
                                          boxShadow: isSent
                                              ? []
                                              : [
                                                  BoxShadow(
                                                    color: _kPrimary.withValues(
                                                      alpha: 0.4,
                                                    ),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                        ),
                                        child: Icon(
                                          Icons.send_rounded,
                                          color: isSent
                                              ? Colors.white.withValues(
                                                  alpha: 0.5,
                                                )
                                              : Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      final caption = result['caption'] ?? '';
      final List<PlatformFile> finalFiles = List<PlatformFile>.from(
        result['files'] ?? dialogFiles,
      );
      await _uploadAndSendMultipleImages(finalFiles, caption);
    } else {
      setState(() {
        _uploadingFile = false;
      });
    }
  }

  Future<void> _uploadAndSendMultipleImages(
    List<PlatformFile> files,
    String caption,
  ) async {
    try {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final bytes = file.bytes!;

        final attachmentUrl = await TicketService.uploadChatAttachment(
          _effectiveTicketId,
          file.name,
          bytes,
        );

        final msgText = (i == 0 && caption.isNotEmpty)
            ? caption
            : 'Envío de foto';

        await TicketService.sendTicketMessage(
          _effectiveTicketId,
          msgText,
          attachmentUrl: attachmentUrl,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir archivos: $e'),
            backgroundColor: _kRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingFile = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(
          ticket != null ? ticket.ticketNumber : 'Detalle del Servicio',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF0D9488)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _loadTicket,
        child: _loading
            ? SingleChildScrollView(
                physics: UiHelpers.refreshScrollPhysics,
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: const Center(
                    child: CircularProgressIndicator(color: _kPrimary),
                  ),
                ),
              )
            : _error != null
            ? SingleChildScrollView(
                physics: UiHelpers.refreshScrollPhysics,
                child: _buildErrorView(),
              )
            : ticket == null
            ? SingleChildScrollView(
                physics: UiHelpers.refreshScrollPhysics,
                child: _buildNotFoundView(),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth > 900;

                  if (isDesktop) {
                    return SingleChildScrollView(
                      physics: UiHelpers.refreshScrollPhysics,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeaderCard(ticket),
                                const SizedBox(height: 16),
                                _buildInfoCard(
                                  title: 'Información General',
                                  icon: Icons.info_outline,
                                  children: _buildGeneralInfoFields(ticket),
                                ),
                                const SizedBox(height: 16),
                                _buildServiceOrderCard(ticket),
                                const SizedBox(height: 16),
                                _buildQuoteSection(ticket),
                                if (_serviceCompletion != null &&
                                    _serviceCompletion!.isCompleted) ...[
                                  const SizedBox(height: 16),
                                  ServiceCompletionCard(
                                    serviceCompletion: _serviceCompletion!,
                                    onDownloadReportPdf:
                                        _openFinalServiceOrderPdf,
                                    isDownloadingPdf:
                                        _generatingFinalServiceOrderPdf,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: _buildChatCard(ticket)),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    physics: UiHelpers.refreshScrollPhysics,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeaderCard(ticket),
                        const SizedBox(height: 16),
                        _buildInfoCard(
                          title: 'Información General',
                          icon: Icons.info_outline,
                          children: _buildGeneralInfoFields(ticket),
                        ),
                        const SizedBox(height: 16),
                        _buildServiceOrderCard(ticket),
                        const SizedBox(height: 16),
                        _buildQuoteSection(ticket),
                        if (_serviceCompletion != null &&
                            _serviceCompletion!.isCompleted) ...[
                          const SizedBox(height: 16),
                          ServiceCompletionCard(
                            serviceCompletion: _serviceCompletion!,
                            onDownloadReportPdf: _openFinalServiceOrderPdf,
                            isDownloadingPdf: _generatingFinalServiceOrderPdf,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildChatCard(ticket),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildHeaderCard(ServiceTicket ticket) {
    final statusColor = _statusColor(ticket.status);
    final priorityColor = _priorityColor(ticket.priority);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.ticketNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kNavy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  ticket.statusLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Urgencia: ',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ticket.priorityLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: priorityColor,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                _formatDate(ticket.createdAt).split(' - ').first,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGeneralInfoFields(ServiceTicket ticket) {
    final hasTechnician =
        ticket.assignedTechnicianCustomName != null &&
        ticket.assignedTechnicianCustomName!.isNotEmpty;
    final String techValue = hasTechnician
        ? ticket.assignedTechnicianCustomName!
        : 'Por asignar';

    final fields = <Widget>[
      _buildDetailRow(
        label: 'Cliente',
        value: ticket.clientName ?? 'No especificado',
        icon: Icons.business,
      ),
      _buildDetailRow(
        label: 'Tipo de Servicio',
        value: ticket.typeLabel,
        icon: Icons.build_circle_outlined,
      ),
      _buildDetailRow(
        label: 'Fecha de Reporte',
        value: _formatDate(ticket.createdAt),
        icon: Icons.calendar_today_outlined,
      ),
      _buildDetailRow(
        label: 'Última Actualización',
        value: ticket.updatedAt != null
            ? _formatDate(ticket.updatedAt!)
            : 'Sin actualizaciones',
        icon: Icons.update,
      ),
      _buildDetailRow(
        label: 'Técnico Asignado',
        value: techValue,
        icon: Icons.person_outline,
        valueColor: !hasTechnician ? Colors.orange.shade800 : null,
      ),
    ];

    if (ticket.scheduledStartAt != null) {
      fields.add(
        _buildDetailRow(
          label: 'Fecha Programada',
          value: _formatDate(ticket.scheduledStartAt!),
          icon: Icons.alarm,
          valueColor: const Color(0xFF16A34A),
        ),
      );
    } else if (ticket.requestedServiceDate != null &&
        ticket.requestedServiceDate!.isNotEmpty) {
      fields.add(
        _buildDetailRow(
          label: 'Fecha de Servicio Solicitada',
          value: ticket.requestedServiceDate!,
          icon: Icons.calendar_today,
        ),
      );
    }

    if (ticket.serviceAddress != null && ticket.serviceAddress!.isNotEmpty) {
      final cityPart =
          ticket.serviceCity != null && ticket.serviceCity!.isNotEmpty
          ? ', ${ticket.serviceCity}'
          : '';
      final statePart =
          ticket.serviceState != null && ticket.serviceState!.isNotEmpty
          ? ', ${ticket.serviceState}'
          : '';
      fields.add(
        _buildDetailRow(
          label: 'Dirección del Servicio',
          value: '${ticket.serviceAddress}$cityPart$statePart',
          icon: Icons.location_on_outlined,
        ),
      );
    }

    if (ticket.serviceLocation != null && ticket.serviceLocation!.isNotEmpty) {
      fields.add(
        _buildDetailRow(
          label: 'Área / Ubicación',
          value: ticket.serviceLocation!,
          icon: Icons.place_outlined,
        ),
      );
    }

    if (ticket.contactName != null && ticket.contactName!.isNotEmpty) {
      fields.add(
        _buildDetailRow(
          label: 'Responsable',
          value: ticket.contactName!,
          icon: Icons.contacts_outlined,
        ),
      );
    }
    if (ticket.contactPhone != null && ticket.contactPhone!.isNotEmpty) {
      fields.add(
        _buildDetailRow(
          label: 'Teléfono Contacto',
          value: ticket.contactPhone!,
          icon: Icons.phone_android_outlined,
        ),
      );
    }
    if (ticket.contactEmail != null && ticket.contactEmail!.isNotEmpty) {
      fields.add(
        _buildDetailRow(
          label: 'Email Contacto',
          value: ticket.contactEmail!,
          icon: Icons.email_outlined,
        ),
      );
    }

    if (ticket.errorCode != null && ticket.errorCode!.isNotEmpty) {
      fields.add(
        _buildDetailRow(
          label: 'Código de Error',
          value: ticket.errorCode!,
          icon: Icons.bug_report_outlined,
          valueColor: const Color(0xFFEF4444),
        ),
      );
    }

    return fields;
  }

  Color _quoteStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'converted':
        return const Color(0xFF16A34A);
      case 'sent':
        return const Color(0xFF0284C7);
      case 'draft':
        return Colors.grey;
      case 'rejected':
      case 'expired':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  Widget _buildQuoteSection(ServiceTicket ticket) {
    if (_loadingQuote) {
      return _buildInfoCard(
        title: 'COTIZACIÓN DE SERVICIO',
        icon: Icons.request_quote_outlined,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _kPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_serviceQuote == null) {
      return _buildEmptyQuoteCard(ticket);
    }

    return _buildQuoteCard(_serviceQuote!, ticket);
  }

  Widget _buildEmptyQuoteCard(ServiceTicket ticket) {
    final isAssignedOrBeyond =
        ticket.status.toLowerCase() == 'assigned' ||
        ticket.status.toLowerCase() == 'in_progress' ||
        ticket.status.toLowerCase() == 'resolved' ||
        ticket.status.toLowerCase() == 'closed';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.request_quote_outlined,
                color: _kPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'COTIZACIÓN DE SERVICIO',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _kNavy,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'SIN COTIZACIÓN',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (isAssignedOrBeyond) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFFD97706),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aviso administrativo: Este ticket se encuentra en estado "${ticket.statusLabel}". Puedes generar la cotización formal en cualquier momento para registrar la propuesta económica.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Text(
              'Este ticket de servicio aún no cuenta con una cotización económica registrada.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openCreateQuoteSheet(ticket),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_chart_outlined, size: 18),
              label: const Text(
                'Crear cotización',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard(ServiceQuote quote, ServiceTicket ticket) {
    final statusColor = _quoteStatusColor(quote.status);
    final validDate = quote.validUntil;
    final validStr = validDate != null
        ? '${validDate.day}/${validDate.month}/${validDate.year}'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.request_quote_outlined, color: _kPrimary, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'COTIZACIÓN DE SERVICIO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _kNavy,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                quote.quoteNumber,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _kNavy,
                ),
              ),
              if (validStr != null)
                Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.event_outlined,
                            size: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      TextSpan(
                        text: 'Válida hasta: $validStr',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  quote.statusLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Text(
            'CONCEPTOS INCLUIDOS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          if (quote.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sin partidas desglosadas.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            )
          else
            ...quote.items.map((item) {
              final formattedUnit = formatFinancialPrice(item.unitPrice);
              final formattedLineTotal = formatFinancialPrice(
                item.totalLinePrice,
              );
              final hasDiscount = item.hasDiscount;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productNameSnapshot,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _kNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${item.quantity.toInt()} x $formattedUnit',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (!hasDiscount)
                          Text(
                            formattedLineTotal,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _kNavy,
                            ),
                          ),
                      ],
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Bonificación / Descuento:',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '-${formatFinancialPrice(item.discount)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Importe partida:',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            formattedLineTotal,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: _kNavy,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),

          const SizedBox(height: 8),

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
                    Text(
                      'Subtotal',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      formatFinancialPrice(quote.subtotal),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _kNavy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'IVA (${(quote.taxPct * 100).toInt()}%)',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      formatFinancialPrice(quote.tax),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _kNavy,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, thickness: 0.8),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL COTIZADO',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _kNavy,
                      ),
                    ),
                    Text(
                      formatFinancialPrice(quote.total),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _kPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (quote.notes != null && quote.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDetailSection(
              label: 'Observaciones del presupuesto',
              value: quote.notes!.trim(),
              isDescription: true,
            ),
          ],

          const SizedBox(height: 14),

          if (quote.isDraft) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.edit_note_outlined,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cotización en borrador',
                          style: TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Esta propuesta aún no ha sido enviada al cliente. Puedes revisarla y enviarla cuando esté lista.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openCreateQuoteSheet(ticket),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kNavy,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'Modificar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _submittingQuoteResponse
                        ? null
                        : () => _confirmSendQuote(quote),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _submittingQuoteResponse
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: const Text(
                      'Enviar al Cliente',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (quote.isSent) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.forward_to_inbox_outlined,
                    color: Color(0xFF0284C7),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cotización enviada al cliente',
                          style: TextStyle(
                            color: Color(0xFF0369A1),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'La propuesta económica fue enviada. Esperando confirmación o respuesta del cliente.',
                          style: TextStyle(
                            color: Color(0xFF0284C7),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submittingQuoteResponse
                        ? null
                        : () => _confirmRejectQuote(quote),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kRed,
                      side: const BorderSide(color: _kRed),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Rechazar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submittingQuoteResponse
                        ? null
                        : () => _confirmAcceptQuote(quote),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _submittingQuoteResponse
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Aceptar Cotización',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ] else if (quote.isApproved) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cotización aceptada',
                          style: TextStyle(
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'La propuesta económica ha sido confirmada. Procede con el pago para continuar con el servicio.',
                          style: TextStyle(
                            color: Color(0xFF15803D),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submittingQuotePayment
                    ? null
                    : () => _startQuotePayment(quote),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF009EE3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _submittingQuotePayment
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.payment_outlined, size: 18),
                label: Text(
                  _submittingQuotePayment
                      ? 'Iniciando Mercado Pago...'
                      : 'Pagar Cotización (${formatFinancialPrice(quote.total)})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ] else if (quote.isRejected) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cancel, color: Color(0xFFDC2626), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cotización rechazada',
                      style: TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openCreateQuoteSheet(ticket),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Crear nueva cotización',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ] else if (quote.isExpired) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.schedule, color: Color(0xFFD97706), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cotización vencida',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openCreateQuoteSheet(ticket),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Crear nueva cotización',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ] else if (quote.isConverted) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: Color(0xFF0D9488), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cotización pagada / convertida en compra',
                          style: TextStyle(
                            color: Color(0xFF115E59),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'El pago fue acreditado y la orden está registrada.',
                          style: TextStyle(
                            color: Color(0xFF0F766E),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (quote.convertedOrderId != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _viewConvertedOrder(quote),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D9488),
                    side: const BorderSide(color: Color(0xFF0D9488)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: const Text(
                    'Ver en Mis Compras',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildServiceOrderCard(ServiceTicket ticket) {
    final order = ServiceOrderPresentation.fromTicket(ticket);
    final evidence = _evidenceSummary(order);

    return _buildInfoCard(
      title: 'ORDEN DE SERVICIO',
      icon: Icons.assignment_outlined,
      children: [
        _buildServiceOrderPdfAction(),
        const SizedBox(height: 16),
        _buildOrderSection('DATOS DEL EQUIPO', [
          _orderField('Equipo', order.equipmentName, Icons.settings_outlined),
          _orderField('Marca', order.equipmentBrand, Icons.sell_outlined),
          _orderField(
            'Modelo',
            order.equipmentModel,
            Icons.view_in_ar_outlined,
          ),
          _orderField(
            'Número de serie',
            order.serialNumber,
            Icons.tag_outlined,
          ),
          _orderField(
            'Equipo operando',
            order.equipmentOperating,
            Icons.power_settings_new_outlined,
          ),
        ]),
        _buildOrderSection('TIPO DE SERVICIO', [
          _orderField(
            'Servicio solicitado',
            order.serviceTypeLabel,
            Icons.build_circle_outlined,
          ),
        ]),
        _buildOrderSection('DATOS DEL CLIENTE', [
          _orderField('Cliente', order.clientName, Icons.business_outlined),
          _orderField(
            'Institución',
            order.institution,
            Icons.local_hospital_outlined,
          ),
          _orderField(
            'Área / departamento',
            order.department,
            Icons.meeting_room_outlined,
          ),
          _orderField(
            'Responsable',
            order.responsible,
            Icons.contacts_outlined,
          ),
          _orderField('Teléfono', order.phone, Icons.phone_android_outlined),
          _orderField('Correo', order.email, Icons.email_outlined),
          _orderField('Dirección', order.address, Icons.location_on_outlined),
        ]),
        if (order.intakeDetails.isNotEmpty)
          _buildOrderSection('DATOS ADICIONALES', [
            for (final entry in order.intakeDetails.entries)
              _orderField(entry.key, entry.value, Icons.fact_check_outlined),
          ]),
        if (order.failureDescription != null)
          _buildDetailSection(
            label: order.descriptionLabel,
            value: order.failureDescription!,
            isDescription: true,
          ),
        if (evidence != null) ...[
          const SizedBox(height: 16),
          _buildDetailSection(
            label: 'Evidencias',
            value: evidence,
            isDescription: true,
          ),
        ],
      ],
    );
  }

  Widget _buildServiceOrderPdfAction() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.18)),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: _kPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Documento generado con la información registrada para este servicio.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: _kNavy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    _PreliminaryChip(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _generatingServiceOrderPdf
                  ? null
                  : _openServiceOrderPdf,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _generatingServiceOrderPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kPrimary,
                      ),
                    )
                  : const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                _generatingServiceOrderPdf
                    ? 'Generando orden...'
                    : 'Ver orden de servicio',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSection(String title, List<_ServiceOrderField?> fields) {
    final visibleFields = fields.whereType<_ServiceOrderField>().toList();
    if (visibleFields.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _kNavy,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          for (final field in visibleFields)
            _buildDetailRow(
              label: field.label,
              value: field.value,
              icon: field.icon,
            ),
        ],
      ),
    );
  }

  _ServiceOrderField? _orderField(String label, String? value, IconData icon) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return _ServiceOrderField(label: label, value: trimmed, icon: icon);
  }

  String? _evidenceSummary(ServiceOrderPresentation order) {
    final realAttachments = _messages
        .where((message) => message.attachmentUrl?.trim().isNotEmpty == true)
        .length;
    if (realAttachments > 0) {
      final suffix = realAttachments == 1 ? 'adjunto' : 'adjuntos';
      return '$realAttachments $suffix disponibles en el chat de soporte técnico.';
    }
    return order.legacyEvidenceSummary;
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _kNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection({
    required String label,
    required String value,
    bool isDescription = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              color: _kNavy,
              height: isDescription ? 1.4 : 1.2,
              fontWeight: isDescription ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return LoadErrorState(
      error: _error,
      onRetry: _loadTicket,
      genericTitle: 'Error al cargar el detalle del servicio',
      genericMessage: 'No pudimos cargar esta conversación por el momento.',
    );
  }

  Widget _buildNotFoundView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se encontró el servicio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'El servicio solicitado podría no existir o no tener permisos para verlo.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isVideoAttachment(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm');
}

class _ServiceOrderField {
  final String label;
  final String value;
  final IconData icon;

  const _ServiceOrderField({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _PreliminaryChip extends StatelessWidget {
  const _PreliminaryChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: const Text(
        'Preliminar',
        style: TextStyle(
          color: Color(0xFF0369A1),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VideoAttachmentViewer extends StatefulWidget {
  final String videoUrl;

  const _VideoAttachmentViewer({required this.videoUrl});

  @override
  State<_VideoAttachmentViewer> createState() => _VideoAttachmentViewerState();
}

class _VideoAttachmentViewerState extends State<_VideoAttachmentViewer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeVideo;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _initializeVideo = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: FutureBuilder<void>(
                future: _initializeVideo,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const CircularProgressIndicator(color: Colors.white);
                  }
                  if (snapshot.hasError || !_controller.value.isInitialized) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No se pudo reproducir este video.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }

                  return GestureDetector(
                    onTap: _togglePlayback,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                        if (!_controller.value.isPlaying)
                          const Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 64,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubbleItem extends StatefulWidget {
  final TicketMessage message;
  final bool isMe;
  final String? curUserId;
  final VoidCallback onAttachmentTap;

  const _ChatBubbleItem({
    super.key,
    required this.message,
    required this.isMe,
    required this.curUserId,
    required this.onAttachmentTap,
  });

  @override
  State<_ChatBubbleItem> createState() => _ChatBubbleItemState();
}

class _ChatBubbleItemState extends State<_ChatBubbleItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    // Spring scale effect (elastic out)
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    // Spring slide up effect
    _slideAnimation = Tween<double>(
      begin: 30.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0.0, _slideAnimation.value),
          child: Transform.scale(scale: _scaleAnimation.value, child: child),
        );
      },
      child: _buildBubbleContent(),
    );
  }

  Widget _buildBubbleContent() {
    final msg = widget.message;
    final isMe = widget.isMe;
    final trustedAttachmentUrl = UiHelpers.sanitizeTrustedRemoteUrl(
      msg.attachmentUrl,
    );
    final messageText = msg.message.trim();
    final displayMessage = messageText.isNotEmpty
        ? messageText
        : (msg.attachmentUrl != null
              ? 'No se pudo cargar el adjunto.'
              : 'Mensaje sin contenido.');
    final hasCaption =
        messageText.isNotEmpty &&
        messageText != 'Envío de foto' &&
        messageText != 'Envío de imagen';

    Widget timeRow({bool light = true}) {
      final localCreatedAt = msg.createdAt.toLocal();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${localCreatedAt.hour.toString().padLeft(2, '0')}:${localCreatedAt.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              color: light
                  ? Colors.white.withValues(alpha: 0.75)
                  : const Color(0xFF94A3B8),
              fontSize: 9,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 3),
            Icon(
              (msg.readAt != null || msg.deliveredAt != null)
                  ? Icons.done_all
                  : Icons.done,
              size: 11,
              color: msg.readAt != null
                  ? const Color(0xFF00E5FF)
                  : (msg.deliveredAt != null
                        ? Colors.white.withValues(alpha: 0.65)
                        : Colors.white.withValues(alpha: 0.4)),
            ),
          ],
        ],
      );
    }

    Widget? senderLabel = !isMe
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              msg.senderName ?? 'Soporte',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _kPrimary,
              ),
            ),
          )
        : null;

    final bubbleRadius = isMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          );

    Widget bubbleWidget;
    if (trustedAttachmentUrl != null) {
      final attachmentUrl = trustedAttachmentUrl;
      final isVideo = _isVideoAttachment(attachmentUrl);
      bubbleWidget = Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
          minWidth: 160,
        ),
        decoration: BoxDecoration(
          color: hasCaption
              ? (isMe ? _kPrimary : Colors.white)
              : Colors.transparent,
          borderRadius: bubbleRadius,
          boxShadow: hasCaption
              ? [
                  BoxShadow(
                    color: isMe
                        ? _kPrimary.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
          border: hasCaption && !isMe
              ? Border.all(color: const Color(0xFFE2E8F0))
              : null,
        ),
        child: ClipRRect(
          borderRadius: bubbleRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (senderLabel != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: senderLabel,
                ),
              GestureDetector(
                onTap: widget.onAttachmentTap,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      color: Colors.white,
                      width: double.infinity,
                      height: 200,
                      child: isVideo
                          ? const ColoredBox(
                              color: Color(0xFFF1F5F9),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.play_circle_outline,
                                      color: _kPrimary,
                                      size: 52,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Reproducir video',
                                      style: TextStyle(
                                        color: _kNavy,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Image.network(
                              attachmentUrl,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.contain,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: const Color(0xFFF8FAFC),
                                      child: const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _kPrimary,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                              errorBuilder: (_, _, _) => Container(
                                color: const Color(0xFFF1F5F9),
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.grey,
                                  size: 28,
                                ),
                              ),
                            ),
                    ),
                    if (!hasCaption)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: timeRow(light: true),
                        ),
                      ),
                  ],
                ),
              ),
              if (hasCaption)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          displayMessage,
                          style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      timeRow(light: isMe),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      bubbleWidget = Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          color: isMe ? _kPrimary : Colors.white,
          borderRadius: bubbleRadius,
          boxShadow: [
            BoxShadow(
              color: isMe
                  ? _kPrimary.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ?senderLabel,
            Text(
              displayMessage,
              style: TextStyle(
                color: isMe ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: timeRow(light: isMe),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) ...[
          CircleAvatar(
            radius: 13,
            backgroundColor: _kPrimary.withValues(alpha: 0.1),
            child: Text(
              (msg.senderName ?? 'Soporte').substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _kPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bubbleWidget,
        if (isMe) ...[
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 13,
            backgroundColor: const Color(0xFFF1F5F9),
            child: const Icon(
              Icons.person_outline_rounded,
              size: 14,
              color: _kNavy,
            ),
          ),
        ],
      ],
    );
  }
}
