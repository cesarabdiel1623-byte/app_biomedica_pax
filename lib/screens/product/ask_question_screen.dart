import 'package:flutter/material.dart';
import '../../services/question_service.dart';
import '../../utils/ui_helpers.dart';

class AskQuestionScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const AskQuestionScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<AskQuestionScreen> createState() => _AskQuestionScreenState();
}

class _AskQuestionScreenState extends State<AskQuestionScreen> {
  static const _kPrimary = Color(0xFF0D9488);
  static const _kNavy = Color(0xFF1E3A5F);
  static const _kGreyBg = Color(0xFFF8FAFC);

  final TextEditingController _questionController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _submitQuestion() async {
    final text = _questionController.text.trim();
    if (text.isEmpty) {
      UiHelpers.showWarningToast(context, 'La pregunta no puede estar vacía.');
      return;
    }
    if (text.length > 500) {
      UiHelpers.showWarningToast(
        context,
        'La pregunta no puede exceder los 500 caracteres.',
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await QuestionService.askQuestion(widget.productId, text);
      if (mounted) {
        UiHelpers.showQuestionSubmittedToast(
          context,
          '✓ Tu pregunta fue enviada.',
        );
        Navigator.of(
          context,
        ).pop(true); // Return true to trigger reload of list
      }
    } catch (e) {
      if (mounted) {
        UiHelpers.showErrorToast(
          context,
          'Ocurrió un error al enviar tu pregunta. Por favor intenta de nuevo.',
        );
      }
      print('Error submitting question: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Preguntar sobre producto',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado descriptivo
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kPrimary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      color: _kPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¿Tienes alguna duda?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Nuestro equipo técnico te responderá a la brevedad.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Chips de sugerencias rápidas
              const Text(
                'Sugerencias rápidas:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _suggestionChip('¿Qué accesorios incluye la caja?'),
                  _suggestionChip('¿Es compatible con mi equipo?'),
                  _suggestionChip('¿Cuentan con factura y garantía?'),
                  _suggestionChip('¿Cuál es el tiempo de entrega?'),
                ],
              ),
              const SizedBox(height: 20),

              // Campo de texto para la pregunta
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _questionController,
                  maxLines: 5,
                  maxLength: 500,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: Color(0xFF0F172A),
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Escribe tu pregunta detallada aquí (especificaciones técnicas, voltaje, compatibilidad, etc.)...',
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade400,
                      height: 1.4,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                    border: InputBorder.none,
                    counterStyle: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Nota informativa moderna
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCFCE7)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      color: Color(0xFF16A34A),
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tu pregunta será revisada por nuestro equipo de ingeniería biomédica y se publicará junto con la respuesta para ayudar a la comunidad médica.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF166534),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Botón de Enviar Pregunta (54px, pastilla circular)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _submitQuestion,
                  icon: _isSending
                      ? const SizedBox.shrink()
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                  label: _isSending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Enviar pregunta',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    disabledBackgroundColor: _kPrimary.withValues(alpha: 0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return InkWell(
      onTap: () {
        setState(() {
          _questionController.text = text;
          _questionController.selection = TextSelection.fromPosition(
            TextPosition(offset: _questionController.text.length),
          );
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF475569),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
