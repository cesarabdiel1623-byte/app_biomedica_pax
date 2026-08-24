import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/product.dart';
import '../../services/review_service.dart';
import '../../utils/ui_helpers.dart';

class WriteReviewScreen extends StatefulWidget {
  final Product product;
  final ProductReview? existingReview;

  const WriteReviewScreen({
    super.key,
    required this.product,
    this.existingReview,
  });

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  static const _primary = Color(0xFF0D9488);
  static const _navy = Color(0xFF172B4D);
  static const _background = Colors.white;
  static const _border = Color(0xFFD9DEE7);
  static const _star = Color(0xFFF6B800);
  static const _maxPhotos = 5;

  late int _rating;
  late final TextEditingController _commentController;
  final List<String> _uploadedPhotos = [];
  bool _isUploadingPhoto = false;
  bool _isSaving = false;
  bool _isDeleting = false;

  bool get _isEditing => widget.existingReview != null;
  bool get _isBusy => _isUploadingPhoto || _isSaving || _isDeleting;
  bool get _canSave =>
      _rating > 0 && _commentController.text.trim().isNotEmpty && !_isBusy;

  @override
  void initState() {
    super.initState();
    _rating = widget.existingReview?.rating ?? 0;
    _commentController = TextEditingController(
      text: widget.existingReview?.comment ?? '',
    );
    _uploadedPhotos.addAll(widget.existingReview?.images ?? const []);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_uploadedPhotos.length >= _maxPhotos) {
      await _showLimitWarning(
        icon: Icons.photo_library_outlined,
        title: 'Límite de fotos alcanzado',
        message: 'Puedes agregar un máximo de 5 fotos por opinión.',
      );
      return;
    }
    if (_isUploadingPhoto) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final url = await ReviewService.uploadReviewPhoto(
        widget.product.id,
        bytes,
        picked.name,
      );
      if (!mounted) return;
      setState(() => _uploadedPhotos.add(url));
    } catch (error) {
      if (mounted) {
        UiHelpers.showFloatingDeleteToast(
          context,
          'No se pudo subir la foto. Intenta nuevamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }



  Future<void> _showLimitWarning({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFE6F5F3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _primary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(foregroundColor: _primary),
            child: const Text(
              'Entendido',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReview() async {
    FocusScope.of(context).unfocus();

    if (_rating == 0) {
      UiHelpers.showFloatingDeleteToast(
        context,
        'Selecciona una calificación.',
      );
      return;
    }
    if (_commentController.text.trim().isEmpty) {
      UiHelpers.showFloatingDeleteToast(
        context,
        'Escribe un comentario sobre el producto.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await ReviewService.updateReview(
          productId: widget.product.id,
          reviewId: widget.existingReview!.id,
          rating: _rating,
          comment: _commentController.text.trim(),
          imageUrls: _uploadedPhotos,
        );
      } else {
        await ReviewService.addReview(
          productId: widget.product.id,
          rating: _rating,
          comment: _commentController.text.trim(),
          imageUrls: _uploadedPhotos,
        );
      }

      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(
        context,
        _isEditing
            ? 'Opinión actualizada correctamente.'
            : 'Gracias por compartir tu opinión.',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Error al guardar opinión: $error');
      setState(() => _isSaving = false);
      UiHelpers.showFloatingDeleteToast(
        context,
        'No se pudo guardar la opinión. Intenta nuevamente.',
      );
    }
  }

  Future<void> _deleteReview() async {
    if (!_isEditing || _isBusy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar opinión'),
        content: const Text(
          'Esta acción eliminará tu calificación, comentario y archivos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: const Text(
              'Eliminar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await ReviewService.deleteReview(widget.existingReview!.id);
      if (!mounted) return;
      UiHelpers.showFloatingSuccessToast(context, 'Opinión eliminada.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      UiHelpers.showFloatingDeleteToast(
        context,
        'No se pudo eliminar la opinión. Intenta nuevamente.',
      );
    }
  }

  String get _ratingLabel {
    switch (_rating) {
      case 1:
        return 'Malo';
      case 2:
        return 'Regular';
      case 3:
        return 'Bueno';
      case 4:
        return 'Muy bueno';
      case 5:
        return 'Excelente';
      default:
        return 'Toca una estrella para calificar';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Editar opinión' : 'Calificar producto',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        elevation: 0,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProductSummary(),
            _buildRatingSection(),
            _buildMediaSection(),
            _buildCommentSection(),
            _buildActionsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSummary() {
    final product = widget.product;
    final imageUrl = product.mainImageUrl;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? UiHelpers.networkImage(imageUrl, fit: BoxFit.cover)
                  : const Icon(
                      Icons.shopping_bag_outlined,
                      color: _primary,
                      size: 28,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.isActive == false) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.orange,
                        size: 14,
                      ),
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
                  const SizedBox(height: 3),
                ],
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.formattedPrice,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSection() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
      child: Column(
        children: [
          const Text(
            '¿Qué te pareció el producto?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _navy,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 17),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              return Semantics(
                button: true,
                label: '$value de 5 estrellas',
                child: IconButton(
                  onPressed: () => setState(() => _rating = value),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(
                    value <= _rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 42,
                    color: value <= _rating ? _star : const Color(0xFFC8CDD5),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _ratingLabel,
            style: TextStyle(
              color: _rating == 0 ? const Color(0xFF6B7280) : _primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaSection() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Muestra el producto que recibiste',
            style: TextStyle(
              color: _navy,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _MediaPickerButton(
                    icon: Icons.add_to_photos_outlined,
                    label: 'Agregar',
                    loading: _isUploadingPhoto,
                    onTap: _pickImage,
                  ),
                ),
                ...List.generate(_uploadedPhotos.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _ReviewPhoto(
                      url: _uploadedPhotos[index],
                      onRemove: () {
                        setState(() => _uploadedPhotos.removeAt(index));
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentSection() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cuéntanos acerca del producto',
            style: TextStyle(
              color: _navy,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Comenta sobre su desempeño, calidad y facilidad de uso.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _commentController,
            minLines: 4,
            maxLines: 6,
            maxLength: 100,
            onChanged: (_) {
              if (mounted) setState(() {});
            },
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: '¿Qué le dirías a otras personas sobre este producto?',
              hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 14,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _canSave ? _saveReview : null,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                disabledBackgroundColor: const Color(0xFFB7CBC9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _isEditing ? 'Guardar cambios' : 'Guardar opinión',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isBusy ? null : _deleteReview,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  disabledBackgroundColor: const Color(0xFFE9A8A8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: _isDeleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Eliminar opinión',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaPickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _MediaPickerButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: OutlinedButton(
        onPressed: loading ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _WriteReviewScreenState._primary,
          side: const BorderSide(
            color: _WriteReviewScreenState._primary,
            width: 1.5,
          ),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: _WriteReviewScreenState._primary,
                  strokeWidth: 2,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 29),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }
}



class _ReviewPhoto extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;

  const _ReviewPhoto({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: UiHelpers.networkImage(
                url,
                fit: BoxFit.cover,
                iconSize: 26,
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: IconButton.filled(
              onPressed: onRemove,
              tooltip: 'Quitar foto',
              icon: const Icon(Icons.close_rounded, size: 17),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xCC111827),
                foregroundColor: Colors.white,
                minimumSize: const Size(30, 30),
                maximumSize: const Size(30, 30),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
