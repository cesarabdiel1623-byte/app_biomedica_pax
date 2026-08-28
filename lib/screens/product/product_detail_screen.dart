import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../home/widgets/staggered_fade_slide.dart';
import '../home/home_screen.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/cart_service.dart';
import '../../services/search_service.dart';
import '../../services/quote_service.dart';
import '../../services/favorite_service.dart';
import '../../services/review_service.dart';
import '../../widgets/review_video_tile.dart';
import '../../services/question_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/standard_section_header.dart';
import '../home/widgets/checkout_sheet.dart';
import 'search_screen.dart';
import '../auth/login_screen.dart';
import 'ask_question_screen.dart';
import 'all_questions_screen.dart';
import 'all_reviews_screen.dart';
import 'quote_cart_screen.dart';

const _kPrimary = Color(0xFF0D9488);
const _kNavy = Color(0xFF1E3A5F);
const _kAmber = Color(0xFFF59E0B);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF0D9488);
const _kLightBlue = Color(0xFFE0F2F1);

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  final String? searchQuery;
  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.searchQuery,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  bool _loading = true;
  int _currentImage = 0;
  bool _isFavorite = false;
  int _quantity = 1;
  List<Product> _similarProducts = [];
  List<ProductReview> _reviews = [];
  List<ProductQuestion> _questions = [];
  bool _loadingQuestions = true;
  bool _loadingDirectBuy = false;
  bool _loadingAddToCart = false;
  bool _loadingAddToQuote = false;
  bool _addedToCartSuccess = false;
  bool _addedToQuoteSuccess = false;
  bool _hasPurchased = false;
  ProductReview? _userReview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      if (!silent) {
        setState(() {
          _loading = true;
        });
      }
      final p = await ProductService.getProductById(widget.productId);
      if (p != null) {
        try {
          await SearchService.addToRecentlyViewed(p);
        } catch (e) {
          print('Error adding to recently viewed: $e');
        }
        bool isFav = false;
        try {
          isFav = await FavoriteService.isFavorite(widget.productId);
        } catch (e) {
          print('Error loading favorite status: $e');
        }

        List<Product> similar = [];
        try {
          similar = await ProductService.getSimilarProducts(
            widget.productId,
            p.category,
            categoryId: p.categoryId,
            subcategory: p.subcategory,
            subcategoryId: p.subcategoryId,
          );
        } catch (e) {
          print('Error loading similar products: $e');
        }

        List<ProductReview> reviewsList = [];
        try {
          reviewsList = await ReviewService.getReviews(widget.productId);
        } catch (e) {
          print('Error loading product reviews: $e');
        }

        List<ProductQuestion> questionsList = [];
        try {
          questionsList = await QuestionService.getProductQuestions(
            widget.productId,
          );
        } catch (e) {
          print('Error loading product questions: $e');
        }

        bool hasPurchased = false;
        ProductReview? userReview;
        try {
          hasPurchased = await ReviewService.hasPurchasedProduct(
            widget.productId,
          );
          userReview = await ReviewService.getProductReviewByClient(
            widget.productId,
          );
        } catch (e) {
          print('Error loading purchase/review status: $e');
        }

        if (mounted) {
          setState(() {
            _product = p;
            _isFavorite = isFav;
            _similarProducts = similar;
            _reviews = reviewsList;
            _questions = questionsList;
            _hasPurchased = hasPurchased;
            _userReview = userReview;
            _loadingQuestions = false;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadReviewsSilently() async {
    try {
      final reviewsList = await ReviewService.getReviews(widget.productId);
      final userReview = await ReviewService.getProductReviewByClient(
        widget.productId,
      );
      if (mounted) {
        setState(() {
          _reviews = reviewsList;
          _userReview = userReview;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    try {
      final newState = await FavoriteService.toggleFavorite(widget.productId);
      setState(() {
        _isFavorite = newState;
      });
      if (mounted) {
        final name = _product?.name ?? 'Producto';
        if (newState) {
          UiHelpers.showAddFavoriteToast(context, name);
        } else {
          UiHelpers.showRemoveFavoriteToast(context, name);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _kRed),
        );
      }
    }
  }

  Future<bool> _addToCart() async {
    if (_product == null) return false;
    if (_loadingAddToCart) return false;
    if (_isUnavailable(_product!)) {
      await _requestQuote(_product!);
      return false;
    }
    final inCartQty = CartService.getProductQtyInCart(_product!.id);
    if (_product!.stock != null && inCartQty + _quantity > _product!.stock!) {
      UiHelpers.showStockLimitToast(
        context,
        _product!.stock!,
        bottomMargin: 12,
      );
      return false;
    }
    setState(() => _loadingAddToCart = true);
    UiHelpers.showAddToCartSuccessToast(
      context,
      _product!.name,
      _quantity,
      bottomMargin: 12,
    );
    try {
      await CartService.addToCart(_product!.id, quantity: _quantity);
      if (mounted) {
        setState(() {
          _addedToCartSuccess = true;
          _addedToQuoteSuccess = false;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        final errStr = e.toString();
        if (errStr.contains('stock_limit_reached')) {
          final stock =
              int.tryParse(errStr.split(':').last) ?? _product!.stock ?? 0;
          UiHelpers.showStockLimitToast(context, stock, bottomMargin: 12);
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          UiHelpers.showErrorToast(
            context,
            'Error al agregar al carrito: ${errStr.replaceAll('Exception: ', '')}',
          );
        }
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _loadingAddToCart = false);
      }
    }
  }

  Future<void> _buyNow(Product p) async {
    if (_isUnavailable(p)) {
      await _requestQuote(p);
      return;
    }
    setState(() => _loadingDirectBuy = true);
    try {
      // 1. Add to cart with chosen quantity
      await CartService.addToCart(p.id, quantity: _quantity);

      // 2. Fetch cart items to get accurate total
      final items = await CartService.getCartItems();
      final couponCleanup = items.isNotEmpty
          ? await CartService.clearInvalidPersistedCouponIfAny()
          : null;
      final subtotal = items.fold<double>(0, (s, i) => s + i.subtotal);
      final total = subtotal * 1.16;

      if (!mounted) return;
      setState(() => _loadingDirectBuy = false);

      if (couponCleanup?.removed == true) {
        final code = couponCleanup!.code?.trim().isNotEmpty == true
            ? couponCleanup.code!.trim()
            : 'guardado';
        UiHelpers.showWarningToast(
          context,
          couponCleanup.reason == 'not_combinable'
              ? 'El cupón $code no se puede combinar con la promoción activa y fue retirado del carrito.'
              : 'El cupón $code ya no aplica a este carrito y fue retirado.',
          bottomMargin: 88,
        );
      }

      // 3. Show CheckoutSheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => CheckoutSheet(
          cartId: items.isNotEmpty ? items.first.cartId : '',
          subtotal: subtotal,
          total: total,
          cartPricingAmounts: couponCleanup?.amounts,
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Compra completada con éxito'),
                backgroundColor: _kPrimary,
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loadingDirectBuy = false);
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _isUnavailable(Product p) {
    final status = p.stockStatusLabel.toLowerCase();
    return status.contains('sin stock') || status.contains('agotado');
  }

  bool _canRequest(Product p) => !_isUnavailable(p);

  String _availabilityTitle(Product p) {
    final status = p.stockStatusLabel;
    if (status == 'Disponible') return 'Producto disponible';
    return status;
  }

  String _availabilitySubtitle(Product p) {
    final status = p.stockStatusLabel.toLowerCase();
    if (status.contains('sin stock') || status.contains('agotado')) {
      return 'Consulta disponibilidad y alternativas para este producto.';
    }
    if (status.contains('bajo')) {
      return 'Quedan pocas unidades disponibles.';
    }
    if (status.contains('pedido')) {
      return 'Disponible bajo pedido.';
    }
    return 'Listo para agregar al carrito.';
  }

  String _shippingTitle(Product p) {
    final info = p.shippingInfo?.trim();
    if (info != null && info.isNotEmpty) return info;
    return 'Entrega nacional disponible';
  }

  String _shippingSubtitle(Product p) {
    if (p.leadTimeDays != null && p.leadTimeDays! > 0) {
      final label = p.leadTimeDays == 1
          ? '1 día hábil'
          : '${p.leadTimeDays} días hábiles';
      return 'Tiempo estimado: $label.';
    }
    return 'Ver más detalles y formas de entrega.';
  }

  String _warrantyTitle(Product p) {
    final warranty = p.warrantyText?.trim();
    if (warranty != null && warranty.isNotEmpty) return warranty;
    return 'Garantía por confirmar';
  }

  Future<void> _requestQuote(Product p) async {
    if (_loadingAddToQuote) return;
    setState(() => _loadingAddToQuote = true);
    try {
      await QuoteService.addToQuote(p, quantity: _quantity);
      if (mounted) {
        setState(() {
          _addedToQuoteSuccess = true;
          _addedToCartSuccess = false;
          _loadingAddToQuote = false;
        });
        UiHelpers.showAddToQuoteSuccessToast(context, p.name, bottomMargin: 12);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAddToQuote = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openFullScreenGallery(List<String> urls, int initialIndex) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, _, _) {
          int localIndex = initialIndex;
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text(
                    '${localIndex + 1} de ${urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  centerTitle: true,
                ),
                body: PageView.builder(
                  controller: PageController(initialPage: initialIndex),
                  itemCount: urls.length,
                  onPageChanged: (idx) {
                    setModalState(() {
                      localIndex = idx;
                    });
                  },
                  itemBuilder: (context, idx) {
                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Center(
                        child: UiHelpers.networkImage(
                          urls[idx],
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showPaymentMethodsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tirador superior de arrastre centrado
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Título limpio sin X
                const Text(
                  'Medios de pago',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF1F5F9),
                ),
                const SizedBox(height: 16),

                // ── Mercado Pago Info ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _mercadoPagoBadge(size: 42, padding: 5),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paga con Mercado Pago',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Elige tu método preferido al finalizar tu compra.',
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

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                  ),
                ),

                // ── Tarjetas de Crédito y Débito ──
                const Text(
                  'Tarjetas de crédito y débito',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Acreditación instantánea con tarjetas participantes.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _paymentAsset(
                      'assets/images/payments/visa_v3.svg',
                      width: 56,
                      height: 30,
                    ),
                    const SizedBox(width: 16),
                    _paymentAsset(
                      'assets/images/payments/mastercard_v3.svg',
                      width: 48,
                      height: 30,
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                  ),
                ),

                // ── Pago en Efectivo ──
                const Text(
                  'Efectivo en puntos de pago',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Paga en tiendas OXXO con código de barras generado al instante.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                _paymentAsset(
                  'assets/images/payments/oxxo_v3.svg',
                  width: 68,
                  height: 34,
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                  ),
                ),

                // ── Pie de Seguridad ──
                const Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: Color(0xFF16A34A),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tus transacciones están encriptadas y protegidas por Mercado Pago.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _paymentAsset(
    String assetPath, {
    required double width,
    double height = 36,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: SvgPicture.asset(assetPath, fit: BoxFit.contain),
    );
  }

  Widget _mercadoPagoBadge({double size = 28, double padding = 4}) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        shape: BoxShape.circle,
      ),
      child: SvgPicture.asset(
        'assets/images/payments/mercadopago_v3.svg',
        fit: BoxFit.contain,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _kPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      leading: StandardBackButton(onPressed: () => Navigator.of(context).pop()),
      titleSpacing: 4,
      toolbarHeight: 56,
      title: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SearchScreen(initialQuery: widget.searchQuery),
            ),
          );
        },
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.grey.shade500, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.searchQuery ?? 'Buscar equipo médico',
                  style: TextStyle(
                    color: widget.searchQuery != null
                        ? const Color(0xFF1E3A5F)
                        : Colors.grey.shade500,
                    fontSize: 14,
                    fontWeight: widget.searchQuery != null
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: const [SizedBox(width: 16)],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }
    if (_product == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: const Center(child: Text('Producto no encontrado')),
      );
    }
    final p = _product!;
    final images = p.images.isNotEmpty ? p.images : [];
    final List<String> imageUrls = [];
    if (images.isNotEmpty) {
      imageUrls.addAll(images.map((img) => img.filePath));
    }
    if (imageUrls.isEmpty &&
        p.mainImageUrl != null &&
        p.mainImageUrl!.isNotEmpty) {
      imageUrls.add(p.mainImageUrl!);
    }

    // Usar solo datos reales de opiniones (sin datos inventados)
    final double ratingVal;
    final int reviewsCountVal;
    if (_reviews.isEmpty) {
      ratingVal = 0.0;
      reviewsCountVal = 0;
    } else {
      ratingVal =
          _reviews.fold<double>(0.0, (s, r) => s + r.rating) / _reviews.length;
      reviewsCountVal = _reviews.length;
    }
    final canRequest = _canRequest(p);
    final maxQuantity = p.stock ?? 99;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera: Condición y Ventas ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Text(
                    p.salesCount > 0
                        ? 'Nuevo  |  ${_formatSoldCount(p.salesCount)}'
                        : 'Nuevo',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (p.salesCount >= 50) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'MÁS VENDIDO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Título del Producto ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                p.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  height: 1.3,
                  letterSpacing: -0.3,
                ),
              ),
            ),

            // ── Valoración y Calificaciones (Clickeable) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: InkWell(
                onTap: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => AllProductReviewsScreen(
                            productId: p.id,
                            productName: p.name,
                          ),
                        ),
                      )
                      .then((_) => _loadReviewsSilently());
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _starsWidget(ratingVal),
                      const SizedBox(width: 8),
                      Text(
                        reviewsCountVal == 0
                            ? 'Sin calificaciones aún'
                            : '${ratingVal.toStringAsFixed(1)} (${_formatOpinionsCount(reviewsCountVal)})',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Galería de Imágenes Limpia ──
            SizedBox(
              height: 300,
              width: double.infinity,
              child: Stack(
                children: [
                  PageView.builder(
                    itemCount: imageUrls.length,
                    onPageChanged: (i) => setState(() => _currentImage = i),
                    itemBuilder: (_, i) {
                      final url = imageUrls[i];
                      return GestureDetector(
                        onTap: () => _openFullScreenGallery(imageUrls, i),
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: url.isNotEmpty
                              ? UiHelpers.networkImage(
                                  url,
                                  fit: BoxFit.contain,
                                  iconSize: 76,
                                )
                              : Icon(
                                  Icons.medical_services_outlined,
                                  size: 76,
                                  color: Colors.grey.shade300,
                                ),
                        ),
                      );
                    },
                  ),
                  // Botón flotante de favorito circular
                  Positioned(
                    top: 8,
                    right: 16,
                    child: GestureDetector(
                      onTap: _toggleFavorite,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border_rounded,
                          color: _isFavorite ? _kRed : const Color(0xFF64748B),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  // Paginador en pastilla circular
                  if (imageUrls.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentImage + 1} / ${imageUrls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            // ── Bloque de Precio ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.hasDiscount) ...[
                    Text(
                      'Antes: ${p.formattedOldPrice}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        decoration: TextDecoration.lineThrough,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        p.formattedPrice,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (p.hasDiscount) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '-${p.discountPercent}% OFF',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: Color(0xFF0D9488),
                      ),
                      SizedBox(width: 5),
                      Text(
                        'IVA incluido • Facturación disponible',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Enlace a medios de pago limpio y sutil
                  InkWell(
                    onTap: _showPaymentMethodsSheet,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          _mercadoPagoBadge(size: 24, padding: 3),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Paga en hasta 12 meses con Mercado Pago',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Color(0xFF2563EB),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            // ── Beneficios: Disponibilidad, Envío y Garantía ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _benefitRow(
                    Icons.inventory_2_outlined,
                    _availabilityTitle(p),
                    _availabilitySubtitle(p),
                    p.stockStatusColor,
                  ),
                  const SizedBox(height: 12),
                  _benefitRow(
                    Icons.local_shipping_outlined,
                    _shippingTitle(p),
                    _shippingSubtitle(p),
                    _kPrimary,
                  ),
                  const SizedBox(height: 12),
                  _benefitRow(
                    Icons.verified_user_outlined,
                    _warrantyTitle(p),
                    'Consulta cobertura y condiciones al finalizar tu compra.',
                    const Color(0xFF3B82F6),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            // ── Selector de Cantidad con bordes circulares ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cantidad',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        canRequest ? _stockQuantityLabel(p) : 'Agotado',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  if (canRequest)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(24),
                              ),
                              onTap: _quantity > 1
                                  ? () => setState(() {
                                      _quantity--;
                                      _addedToCartSuccess = false;
                                      _addedToQuoteSuccess = false;
                                    })
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Icon(
                                  Icons.remove,
                                  size: 16,
                                  color: _quantity > 1
                                      ? _kPrimary
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '$_quantity',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(24),
                              ),
                              onTap: _quantity < maxQuantity
                                  ? () => setState(() {
                                      _quantity++;
                                      _addedToCartSuccess = false;
                                      _addedToQuoteSuccess = false;
                                    })
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Icon(
                                  Icons.add,
                                  size: 16,
                                  color: _quantity < maxQuantity
                                      ? _kPrimary
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ── Botones de Acción con Bordes Circulares (Pills) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // 1. Agregar al carrito / Ver carrito (Verde Teal Circular)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: _addedToCartSuccess
                        ? ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                              HomeScreen.showTab(2);
                            },
                            icon: const Icon(
                              Icons.shopping_cart_outlined,
                              size: 22,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Ver carrito',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed:
                                (canRequest &&
                                    !_loadingAddToCart &&
                                    !_loadingAddToQuote)
                                ? _addToCart
                                : null,
                            icon: _loadingAddToCart
                                ? const SizedBox.shrink()
                                : const Icon(
                                    Icons.add_shopping_cart_rounded,
                                    size: 22,
                                    color: Colors.white,
                                  ),
                            label: _loadingAddToCart
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Text(
                                    canRequest
                                        ? 'Agregar al carrito'
                                        : 'Agotado',
                                    style: const TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),

                  // 2. Cotizar / Solicitar Cotización (Azul Sólido Circular)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: _addedToQuoteSuccess
                        ? ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const QuoteCartScreen(),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.description_outlined,
                              size: 22,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Ver cotización',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3483FA),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed:
                                (!_loadingAddToQuote && !_loadingAddToCart)
                                ? () => _requestQuote(p)
                                : null,
                            icon: _loadingAddToQuote
                                ? const SizedBox.shrink()
                                : const Icon(
                                    Icons.request_quote_outlined,
                                    size: 22,
                                    color: Colors.white,
                                  ),
                            label: _loadingAddToQuote
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : const Text(
                                    'Solicitar Cotización',
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3483FA),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                  ),
                  if (!canRequest) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Consulta este producto para revisar opciones disponibles.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // ── Detalles del Producto (Limpio sobre fondo blanco) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Detalles del producto',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (p.description != null && p.description!.isNotEmpty)
                    Text(
                      p.description!,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF475569),
                        height: 1.55,
                      ),
                    )
                  else
                    const Text(
                      'Sin descripción disponible.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),

                  const SizedBox(height: 14),

                  InkWell(
                    onTap: () => _showProductDetailsSheet(p),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 18,
                            color: _kPrimary,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Ver ficha técnica y especificaciones',
                            style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          Spacer(),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: _kPrimary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // ── Preguntas y respuestas ──
            StaggeredFadeSlide(index: 0, child: _buildQuestionsSection(p)),

            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // ── Opiniones del Producto (Reseñas) ──
            StaggeredFadeSlide(index: 1, child: _buildReviewsSection(p)),

            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            _buildSimilarProductsSection(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _formatOpinionsCount(int count) {
    if (count >= 1000000) {
      final int millions = count ~/ 1000000;
      if (millions == 1) {
        return 'más de 1 millón de opiniones';
      }
      return 'más de $millions millones de opiniones';
    } else if (count >= 1000) {
      final int thousands = count ~/ 1000;
      return 'más de $thousands mil opiniones';
    } else {
      return '$count opinio${count == 1 ? 'n' : 'nes'}';
    }
  }

  Widget _starsWidget(double rating) {
    int fullStars = rating.floor();
    bool hasHalf = (rating - fullStars) >= 0.4;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < fullStars) {
          return const Icon(Icons.star_rounded, color: _kAmber, size: 16);
        } else if (index == fullStars && hasHalf) {
          return const Icon(Icons.star_half_rounded, color: _kAmber, size: 16);
        } else {
          return const Icon(
            Icons.star_border_rounded,
            color: Color(0xFFCBD5E1),
            size: 16,
          );
        }
      }),
    );
  }

  Widget _benefitRow(
    IconData icon,
    String title,
    String subtitle,
    Color iconColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Bottom sheet con 2 pestañas: Descripción y Características
  void _showProductDetailsSheet(Product p) {
    // Generar tabla de especificaciones consolidada
    final specs = <Map<String, String>>[];

    if (p.brand != null && p.brand!.isNotEmpty) {
      specs.add({'key': 'Marca', 'value': p.brand!});
    } else if (p.commercialBrand != null && p.commercialBrand!.isNotEmpty) {
      specs.add({'key': 'Marca', 'value': p.commercialBrand!});
    }
    if (p.model != null && p.model!.isNotEmpty) {
      specs.add({'key': 'Modelo', 'value': p.model!});
    }
    if (p.productCondition != null) {
      specs.add({'key': 'Condición', 'value': p.conditionLabel});
    }
    if (p.warrantyText != null && p.warrantyText!.isNotEmpty) {
      specs.add({'key': 'Garantía', 'value': p.warrantyText!});
    }
    if (p.sku.isNotEmpty) {
      specs.add({'key': 'SKU', 'value': p.sku});
    }

    // Añadir especificaciones dinámicas de la tabla product_specs
    for (final s in p.specs) {
      if (s.specKey.isNotEmpty && s.specValue.isNotEmpty) {
        if (!specs.any((item) => item['key'] == s.specKey)) {
          specs.add({'key': s.specKey, 'value': s.specValue});
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ProductDetailsSheetContent(product: p, specs: specs);
      },
    );
  }

  Future<void> _reloadQuestions() async {
    try {
      final list = await QuestionService.getProductQuestions(widget.productId);
      if (mounted) {
        setState(() {
          _questions = list;
        });
      }
    } catch (e) {
      print('Error reloading questions: $e');
    }
  }

  Widget _buildQuestionsSection(Product p) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final isLoggedIn = currentUser != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preguntas',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Consulta dudas frecuentes o haz una pregunta sobre este producto.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              if (!isLoggedIn) {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    )
                    .then((_) {
                      _load(silent: true);
                    });
              } else {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => AskQuestionScreen(
                          productId: p.id,
                          productName: p.name,
                        ),
                      ),
                    )
                    .then((result) {
                      if (result == true) {
                        _reloadQuestions();
                      }
                    });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Preguntar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => AllProductQuestionsScreen(
                        productId: p.id,
                        productName: p.name,
                      ),
                    ),
                  )
                  .then((_) => _reloadQuestions());
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'Ver más preguntas y respuestas',
                  style: TextStyle(
                    color: _kPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: _kPrimary, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection(Product p) {
    // Extraer todas las imágenes de comentarios
    final commentPhotos = <String>[];
    for (final rev in _reviews) {
      commentPhotos.addAll(rev.images);
    }

    final double ratingVal = _reviews.isEmpty
        ? 0.0
        : _reviews.fold<double>(0.0, (s, r) => s + r.rating) / _reviews.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Opiniones del producto',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 40,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sé el primero en calificar este producto',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Comparte tu opinión con otros profesionales de la salud.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            // Resumen de calificaciones
            Row(
              children: [
                Text(
                  ratingVal.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _starsWidget(ratingVal),
                    const SizedBox(height: 4),
                    Text(
                      'Promedio entre ${_reviews.length} opiniones',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carrusel de imágenes de opiniones si existen
            if (commentPhotos.isNotEmpty) ...[
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: commentPhotos.length,
                  itemBuilder: (_, idx) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                        image: DecorationImage(
                          image: NetworkImage(commentPhotos[idx]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Lista de opiniones (últimas 3 opiniones)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: min(_reviews.length, 3),
              itemBuilder: (_, idx) {
                final rev = _reviews[idx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _starsWidget(rev.rating.toDouble()),
                          Text(
                            _formatDate(rev.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rev.clientName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (rev.comment != null && rev.comment!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          rev.comment!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (rev.images.isNotEmpty || rev.videos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: rev.images.length + rev.videos.length,
                            itemBuilder: (_, i) {
                              if (i >= rev.images.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ReviewVideoTile(
                                    url: rev.videos[i - rev.images.length],
                                    width: 48,
                                    height: 48,
                                  ),
                                );
                              }
                              return GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => Dialog(
                                      backgroundColor: Colors.transparent,
                                      insetPadding: const EdgeInsets.all(12),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          InteractiveViewer(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                rev.images[i],
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 28,
                                              ),
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    image: DecorationImage(
                                      image: NetworkImage(rev.images[i]),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Divider(height: 1, color: Colors.grey.shade100),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => AllProductReviewsScreen(
                        productId: p.id,
                        productName: p.name,
                      ),
                    ),
                  )
                  .then((_) => _loadReviewsSilently());
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'Ver todas las opiniones',
                  style: TextStyle(
                    color: _kPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: _kPrimary, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarProductsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'También podrían gustarte',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_similarProducts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Buscando productos relacionados...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _similarProducts.length,
              itemBuilder: (_, idx) {
                final sp = _similarProducts[idx];
                return GestureDetector(
                  onTap: () async {
                    final res = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(
                          productId: sp.id,
                          searchQuery: widget.searchQuery,
                        ),
                      ),
                    );
                    if (res == true && mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image
                        Container(
                          height: 100,
                          width: double.infinity,
                          color: const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.all(8),
                          child: sp.mainImageUrl != null
                              ? UiHelpers.networkImage(
                                  sp.mainImageUrl!,
                                  fit: BoxFit.contain,
                                  iconSize: 28,
                                )
                              : Icon(
                                  Icons.medical_services_outlined,
                                  color: Colors.grey.shade300,
                                  size: 28,
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sp.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF1F2937),
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                sp.formattedPrice,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              if (sp.hasDiscount) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      sp.formattedOldPrice,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade400,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${sp.discountPercent}%',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _kGreen,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
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
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day $month $year, $hour:$min';
  }

  static String _formatMoney(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '$buffer.$decPart';
  }

  /// Formatea el conteo real de ventas de la BD (sin datos inventados).
  String _formatSoldCount(int count) {
    if (count <= 0) return '';
    if (count < 1000) return '+$count vendidos';
    if (count < 1000000) {
      final miles = count / 1000;
      if (miles == miles.roundToDouble()) {
        return '+${miles.toInt()} mil vendidos';
      }
      return '+${miles.toStringAsFixed(1)} mil vendidos';
    }
    final millones = count / 1000000;
    return '+${millones.toStringAsFixed(1)} M vendidos';
  }

  String _stockQuantityLabel(Product p) {
    final stock = p.stock;
    if (stock == null) return 'por confirmar';
    if (stock == 1) return '1 disponible';
    return '$stock disponibles';
  }
}

class ProductDetailsSheetContent extends StatefulWidget {
  final Product product;
  final List<Map<String, String>> specs;
  const ProductDetailsSheetContent({
    super.key,
    required this.product,
    required this.specs,
  });

  @override
  State<ProductDetailsSheetContent> createState() =>
      _ProductDetailsSheetContentState();
}

class _ProductDetailsSheetContentState extends State<ProductDetailsSheetContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _descriptionKey = GlobalKey();
  final GlobalKey _specsKey = GlobalKey();
  bool _isScrollingFromTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    // Limpia cualquier SnackBar pendiente al salir de la pantalla
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isScrollingFromTab) return;
    final specsContext = _specsKey.currentContext;
    if (specsContext != null) {
      final box = specsContext.findRenderObject() as RenderBox?;
      if (box != null) {
        final position = box.localToGlobal(Offset.zero);
        if (position.dy < MediaQuery.of(context).size.height * 0.45) {
          if (_tabController.index != 1) {
            _tabController.animateTo(1);
          }
          return;
        }
      }
    }
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
  }

  void _scrollToSection(int index) async {
    _isScrollingFromTab = true;
    _tabController.animateTo(index);
    final targetContext = index == 0
        ? _descriptionKey.currentContext
        : _specsKey.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    _isScrollingFromTab = false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Título
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Detalles del producto',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Pestañas
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF0D9488), // _kPrimary
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF0D9488), // _kPrimary
            indicatorWeight: 2.5,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
            ),
            onTap: _scrollToSection,
            tabs: const [
              Tab(text: 'Descripción'),
              Tab(text: 'Características'),
            ],
          ),

          // Contenido de la misma hoja (Scroll único)
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tab 1: Descripción
                  Container(
                    key: _descriptionKey,
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.description?.isNotEmpty == true
                              ? widget.product.description!
                              : 'Este producto no tiene descripción detallada todavía.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Divisor visual entre secciones
                  Divider(height: 32, color: Colors.grey.shade200),

                  // Tab 2: Características
                  Container(
                    key: _specsKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Características principales',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.specs.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: widget.specs.asMap().entries.map((e) {
                                final idx = e.key;
                                final item = e.value;
                                return Column(
                                  children: [
                                    Container(
                                      color: idx.isEven
                                          ? Colors.grey.shade50
                                          : Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              item['key'] ?? '',
                                              style:
                                                  item['key'] ==
                                                      'Método de pago'
                                                  ? const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF3483FA),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    )
                                                  : TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              item['value'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.black,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (idx < widget.specs.length - 1)
                                      Divider(
                                        height: 1,
                                        color: Colors.grey.shade100,
                                      ),
                                  ],
                                );
                              }).toList(),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'No hay especificaciones adicionales para este producto.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
