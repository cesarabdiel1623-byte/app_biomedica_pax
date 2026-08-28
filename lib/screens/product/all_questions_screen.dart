import 'package:flutter/material.dart';
import '../../services/question_service.dart';
import '../../utils/ui_helpers.dart';
import 'ask_question_screen.dart';

class AllProductQuestionsScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const AllProductQuestionsScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<AllProductQuestionsScreen> createState() =>
      _AllProductQuestionsScreenState();
}

class _AllProductQuestionsScreenState extends State<AllProductQuestionsScreen> {
  static const _kPrimary = Color(0xFF0D9488);
  static const _kNavy = Color(0xFF1E3A5F);
  static const _kGreyBg = Color(0xFFF8FAFC);

  List<ProductQuestion> _questions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _loading = true);
    }
    try {
      final list = await QuestionService.getProductQuestions(widget.productId);
      setState(() {
        _questions = list;
      });
    } catch (e) {
      debugPrint('Error loading questions: $e');
    } finally {
      setState(() => _loading = false);
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
          'Preguntas del producto',
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
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kPrimary))
            : _questions.isEmpty
            ? RefreshIndicator(
                onRefresh: () => _loadQuestions(showSpinner: false),
                color: _kPrimary,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(child: _buildEmptyState()),
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _loadQuestions(showSpinner: false),
                color: _kPrimary,
                child: ListView.separated(
                  physics: UiHelpers.refreshScrollPhysics,
                  padding: const EdgeInsets.all(16),
                  itemCount: _questions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final q = _questions[index];
                    final dateStr =
                        '${q.createdAt.day.toString().padLeft(2, '0')}/${q.createdAt.month.toString().padLeft(2, '0')}/${q.createdAt.year}';
                    final answer = q.answerText;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2F1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'P',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _kPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      q.questionText,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        color: Color(0xFF1F2937),
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (answer != null && answer.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'R',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      answer,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF4B5563),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AskQuestionScreen(
                productId: widget.productId,
                productName: widget.productName,
              ),
            ),
          );
          if (result == true) {
            _loadQuestions();
          }
        },
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.add_comment_rounded, color: Colors.white),
        label: const Text(
          'Preguntar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'Aún no hay preguntas para este producto.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
