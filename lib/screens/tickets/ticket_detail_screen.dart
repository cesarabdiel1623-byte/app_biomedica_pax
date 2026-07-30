import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import '../../models/service_ticket.dart';
import '../../models/ticket_message.dart';
import '../../services/ticket_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/load_error_state.dart';

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
  bool _loading = true;
  String? _error;
  List<TicketMessage> _messages = [];
  bool _loadingMessages = true;
  bool _uploadingFile = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
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
    setState(() {
      if (_ticket == null) {
        _loading = true;
      }
      _error = null;
    });
    try {
      ServiceTicket? ticket;
      if (widget.ticketId != null && widget.ticketId!.isNotEmpty) {
        ticket = await TicketService.getTicketById(widget.ticketId!);
      } else if (widget.ticketNumber != null &&
          widget.ticketNumber!.isNotEmpty) {
        ticket = await TicketService.getTicketByNumber(widget.ticketNumber!);
      }
      if (mounted) {
        setState(() {
          _ticket = ticket;
          _loading = false;
        });
        if (ticket != null) {
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
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year} - $hour:$minute hrs';
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
        type: FileType.image,
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
            content: Text('Error al seleccionar imágenes: $e'),
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
                        final bytes = dialogFiles[idx].bytes!;
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
                        'No hay imágenes seleccionadas',
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
                            alignment: Alignment.topLeft,
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
                                                type: FileType.image,
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
            content: Text('Error al subir imágenes: $e'),
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
          ticket != null ? ticket.ticketNumber : 'Detalle de Ticket',
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
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: const Center(
                    child: CircularProgressIndicator(color: _kPrimary),
                  ),
                ),
              )
            : _error != null
            ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: _buildErrorView(),
              )
            : ticket == null
            ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: _buildNotFoundView(),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth > 900;

                  if (isDesktop) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
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
                                _buildInfoCard(
                                  title: 'Detalle del Reporte',
                                  icon: Icons.description_outlined,
                                  children: [
                                    _buildDetailSection(
                                      label: 'Asunto / Título',
                                      value: ticket.title,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildDetailSection(
                                      label: 'Descripción de la Falla',
                                      value:
                                          ticket.description ??
                                          'Sin descripción proporcionada.',
                                      isDescription: true,
                                    ),
                                  ],
                                ),
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
                    physics: const AlwaysScrollableScrollPhysics(),
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
                        _buildInfoCard(
                          title: 'Detalle del Reporte',
                          icon: Icons.description_outlined,
                          children: [
                            _buildDetailSection(
                              label: 'Asunto / Título',
                              value: ticket.title,
                            ),
                            const SizedBox(height: 16),
                            _buildDetailSection(
                              label: 'Descripción de la Falla',
                              value:
                                  ticket.description ??
                                  'Sin descripción proporcionada.',
                              isDescription: true,
                            ),
                          ],
                        ),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ticket.ticketNumber,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
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
      genericTitle: 'Error al cargar el detalle del ticket',
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
              'No se encontró el ticket',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'El ticket de servicio solicitado podría no existir o no tener permisos para verlo.',
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
    final hasCaption = msg.message.isNotEmpty && msg.message != 'Envío de foto';

    Widget timeRow({bool light = true}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
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
                          msg.message,
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
              msg.message,
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
