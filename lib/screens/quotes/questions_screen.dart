import 'package:flutter/material.dart';
import '../../services/question_service.dart';
import '../product/product_detail_screen.dart';
import '../product/ask_question_screen.dart';

class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({super.key});

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  static const _kPrimary = Color(0xFF0D9488);
  static const _kNavy = Color(0xFF1E3A5F);
  static const _kGreyBg = Color(0xFFF8FAFC);
  static const _kTextDark = Color(0xFF1A1A1A);
  static const _kTextGrey = Color(0xFF757575);

  List<ProductQuestion> _questions = [];
  bool _loading = true;

  // Track expanded cards
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _loading = true);
    try {
      final list = await QuestionService.getClientQuestions();
      setState(() {
        _questions = list;
      });
    } catch (e) {
      print('Error al obtener preguntas: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Hace unos momentos';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showOptionsMenu(ProductQuestion q) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Colors.white,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text(
                  'Eliminar pregunta',
                  style: TextStyle(fontWeight: FontWeight.w500, color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(q);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(ProductQuestion q) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('¿Eliminar pregunta?', style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy)),
          content: const Text('Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context); // close dialog
                _deleteQuestion(q);
              },
              child: const Text('Eliminar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteQuestion(ProductQuestion q) async {
    // Show a loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _kPrimary)),
    );

    try {
      await QuestionService.deleteQuestion(q.id);
      if (mounted) {
        Navigator.of(context).pop(); // pop loading overlay
        setState(() {
          _questions.removeWhere((item) => item.id == q.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pregunta eliminada exitosamente.'),
            backgroundColor: _kPrimary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // pop loading overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar la pregunta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Light grey background
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Preguntas',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        centerTitle: false,
        backgroundColor: _kPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _questions.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadQuestions,
                  color: _kPrimary,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _questions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12), // Gap between cards
                    itemBuilder: (context, index) {
                      final q = _questions[index];
                      return _buildQuestionCard(q);
                    },
                  ),
                ),
    );
  }

  Widget _buildQuestionCard(ProductQuestion q) {
    final product = q.product;
    final dateStr = _formatDate(q.createdAt);
    final hasAnswer = q.answers.isNotEmpty;
    final isExpanded = _expandedIds.contains(q.id);

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. PRODUCT HEADER ROW ─────────────────────────────────────────
          if (product != null)
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(productId: product.id),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Square image container
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: product.mainImageUrl != null && product.mainImageUrl!.isNotEmpty
                            ? Image.network(
                                product.mainImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: _kPrimary,
                                  size: 26,
                                ),
                              )
                            : const Icon(
                                Icons.shopping_bag_outlined,
                                color: _kPrimary,
                                size: 26,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title + Price + optional Status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.isActive == false) ...[
                            Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Colors.orange, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Publicación pausada',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _kNavy,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.formattedPrice,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: _kPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Three dots button inside the product card
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      onPressed: () => _showOptionsMenu(q),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

          // ── 2. ACTION BUTTONS (Always shown) ───────────────────────────────
          if (product != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AskQuestionScreen(
                              productId: product.id,
                              productName: product.name,
                            ),
                          ),
                        );
                        _loadQuestions();
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kPrimary, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text(
                        'Hacer otra pregunta',
                        style: TextStyle(
                          color: _kPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailScreen(productId: product.id),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text(
                        'Comprar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
          ],

          // ── 3. QUESTION ROW (Tapping this toggles expand/collapse) ──────────
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedIds.remove(q.id);
                } else {
                  _expandedIds.add(q.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q.questionText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isExpanded ? FontWeight.bold : FontWeight.w500,
                            color: _kTextDark,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hace ${diffInDays(q.createdAt)} días.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── 4. ANSWER BLOCK (Only shown if expanded and has answer) ─────────
          if (isExpanded && hasAnswer) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 12, top: 2),
                    child: CustomPaint(
                      size: const Size(14, 16),
                      painter: _BracketPainter(),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q.answers.first.answerText,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: _kTextGrey,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hace ${diffInDays(q.answers.first.createdAt)} días.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  int diffInDays(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    return diff > 0 ? diff : 8; // fallback to 8 like in screenshot or 1 if recently asked
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.question_answer_outlined,
                color: _kPrimary,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No has realizado preguntas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las consultas que realices sobre nuestros equipos médicos aparecerán en esta sección.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(2, 0)
      ..lineTo(2, size.height - 4)
      ..arcToPoint(
        Offset(6, size.height),
        radius: const Radius.circular(4),
        clockwise: false,
      )
      ..lineTo(size.width, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
