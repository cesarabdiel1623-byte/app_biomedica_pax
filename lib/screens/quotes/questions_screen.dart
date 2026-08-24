import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/question_service.dart';
import '../product/product_detail_screen.dart';
import '../product/ask_question_screen.dart';
import '../../utils/ui_helpers.dart';

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
  final Set<String> _deletingIds = {};

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
      final results = await Future.wait([
        QuestionService.getClientQuestions().timeout(
          const Duration(seconds: 30),
        ),
        if (showSpinner) Future.delayed(const Duration(seconds: 2)),
      ]);
      if (mounted) {
        setState(() {
          _questions = results[0] as List<ProductQuestion>;
        });
      }
    } catch (e) {
      debugPrint('Error al obtener preguntas: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: const Text(
                  'Eliminar pregunta',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
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
          title: const Text(
            '¿Eliminar pregunta?',
            style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy),
          ),
          content: const Text('Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context); // close dialog
                _deleteQuestion(q);
              },
              child: const Text(
                'Eliminar',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteQuestion(ProductQuestion q) async {
    if (_deletingIds.contains(q.id)) return;
    setState(() => _deletingIds.add(q.id));
    try {
      await QuestionService.deleteQuestion(q.id);
      if (mounted) {
        setState(() {
          _questions.removeWhere((item) => item.id == q.id);
          _expandedIds.remove(q.id);
        });
        UiHelpers.showFloatingSuccessToast(context, 'Pregunta eliminada.');
      }
    } catch (_) {
      if (mounted) {
        UiHelpers.showFloatingDeleteToast(
          context,
          'No se pudo eliminar la pregunta. Inténtalo nuevamente.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingIds.remove(q.id));
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
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
              onRefresh: () => _loadQuestions(showSpinner: false),
              color: _kPrimary,
              child: ListView.separated(
                physics: UiHelpers.refreshScrollPhysics,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: _questions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
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
    final productIsAvailable = product != null && product.isActive;
    final isDeleting = _deletingIds.contains(q.id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: const Color(0xFFF8FAFC),
            child: InkWell(
              onTap: productIsAvailable ? () => _openProduct(product) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                child: Row(
                  children: [
                    _buildProductImage(product),
                    const SizedBox(width: 12),
                    Expanded(
                      child: product == null
                          ? const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Producto no disponible',
                                  style: TextStyle(
                                    color: _kNavy,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'La publicación fue retirada del catálogo.',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _kNavy,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  productIsAvailable
                                      ? product.formattedPrice
                                      : 'Publicación no disponible',
                                  style: TextStyle(
                                    color: productIsAvailable
                                        ? _kPrimary
                                        : const Color(0xFF64748B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    if (productIsAvailable)
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                    IconButton(
                      tooltip: 'Más opciones',
                      onPressed: isDeleting ? null : () => _showOptionsMenu(q),
                      icon: isDeleting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                color: _kPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.more_vert_rounded,
                              color: Color(0xFF64748B),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

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
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
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
                            fontSize: 15,
                            fontWeight: isExpanded
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _kNavy,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              hasAnswer
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.schedule_rounded,
                              size: 15,
                              color: hasAnswer
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              hasAnswer ? 'Respondida' : 'Esperando respuesta',
                              style: TextStyle(
                                color: hasAnswer
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '·',
                              style: TextStyle(color: Color(0xFFCBD5E1)),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                dateStr,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF64748B),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: hasAnswer
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCCFBF1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.support_agent_rounded,
                                size: 18,
                                color: _kPrimary,
                              ),
                              SizedBox(width: 7),
                              Text(
                                'Respuesta de Go Medical',
                                style: TextStyle(
                                  color: _kNavy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            q.answers.first.answerText,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: _kTextGrey,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatDate(q.answers.first.createdAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          color: Color(0xFF94A3B8),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu pregunta está pendiente de respuesta.',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
          if (productIsAvailable) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _openProduct(product),
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: const Text('Ver producto'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AskQuestionScreen(
                            productId: product.id,
                            productName: product.name,
                          ),
                        ),
                      );
                      if (mounted) {
                        await _loadQuestions(showSpinner: false);
                      }
                    },
                    icon: const Icon(Icons.add_comment_outlined, size: 17),
                    label: const Text('Preguntar'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openProduct(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(productId: product.id),
      ),
    );
  }

  Widget _buildProductImage(Product? product) {
    final imageUrl = product?.mainImageUrl;
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.inventory_2_outlined,
                color: Color(0xFF94A3B8),
                size: 25,
              ),
            )
          : const Icon(
              Icons.inventory_2_outlined,
              color: Color(0xFF94A3B8),
              size: 25,
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.question_answer_outlined,
              color: Colors.grey.shade400,
              size: 64,
            ),
            const SizedBox(height: 12),
            const Text(
              'No has realizado preguntas',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Las consultas que realices sobre nuestros equipos médicos aparecerán en esta sección.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
