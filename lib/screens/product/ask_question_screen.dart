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
    if (text.length < 10) {
      UiHelpers.showWarningToast(context, 'La pregunta debe tener al menos 10 caracteres.');
      return;
    }
    if (text.length > 500) {
      UiHelpers.showWarningToast(context, 'La pregunta no puede exceder los 500 caracteres.');
      return;
    }

    setState(() => _isSending = true);

    try {
      await QuestionService.askQuestion(widget.productId, text);
      if (mounted) {
        UiHelpers.showQuestionSubmittedToast(
          context,
          '✓ Tu pregunta fue enviada. El equipo de Go Medical la responderá pronto.',
        );
        Navigator.of(context).pop(true); // Return true to trigger reload of list
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
      backgroundColor: _kGreyBg,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Preguntar sobre producto',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escribe tu pregunta',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: _kNavy),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _questionController,
                maxLines: 6,
                maxLength: 500,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14, color: Colors.black, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Ej. ¿El equipo cuenta con certificación COFEPRIS y qué accesorios incluye la caja?',
                  hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade400),
                  contentPadding: const EdgeInsets.all(16),
                  filled: true,
                  fillColor: Colors.white,
                  counterStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              
              // Helper note card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA), // Light teal bg
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCCFBF1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: _kPrimary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu pregunta será revisada por nuestro equipo técnico y se publicará junto con la respuesta correspondiente.',
                        style: TextStyle(fontSize: 11.5, color: Colors.teal.shade800, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _submitQuestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    disabledBackgroundColor: _kPrimary.withValues(alpha: 0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Enviar pregunta',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
