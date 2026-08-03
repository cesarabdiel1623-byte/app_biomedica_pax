import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/cart_service.dart';
import '../../core/theme/app_colors.dart';
import '../home/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kPrimary = AppColors.primary;
const _kGreen = AppColors.secondary;
const _kRed = AppColors.error;

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  bool _loading = true;
  int _currentImage = 0;
  bool _descExpanded = false;
  bool _loadingDirectBuy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ProductService.getProductById(widget.productId);
      if (mounted)
        setState(() {
          _product = p;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _validateStock(Product p) async {
    if (!p.trackInventory) return true;
    try {
      final response = await Supabase.instance.client
          .from('product_inventory_availability')
          .select('available_stock, stock_status')
          .eq('product_id', p.id)
          .maybeSingle();
      
      if (response == null) return true;
      
      final availableStockStr = response['available_stock']?.toString() ?? '0';
      final availableStock = double.tryParse(availableStockStr)?.round() ?? 0;
      if (availableStock <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Agotado. Sin stock disponible.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  Future<void> _buyNow(Product p) async {
    setState(() => _loadingDirectBuy = true);
    final hasStock = await _validateStock(p);
    if (!hasStock) {
      setState(() => _loadingDirectBuy = false);
      return;
    }
    try {
      // 1. Add to cart
      await CartService.addToCart(p.id);

      // 2. Fetch cart items to get accurate total
      final items = await CartService.getCartItems();
      final subtotal = items.fold<double>(0, (s, i) => s + i.subtotal);
      final total = subtotal * 1.16;

      if (!mounted) return;
      setState(() => _loadingDirectBuy = false);

      // 3. Show CheckoutSheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => CheckoutSheet(
          total: total,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
            onPressed: () => Navigator.maybePop(context),
          ),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_product == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
            onPressed: () => Navigator.maybePop(context),
          ),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: const Center(child: Text('Producto no encontrado')),
      );
    }
    final p = _product!;
    final images = p.images.isNotEmpty ? p.images : [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        shape: const Border(
          bottom: BorderSide(
            color: AppColors.border,
            width: 1.0,
          ),
        ),
        title: const Text(
          'Detalle del Producto',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image gallery in clean container card
            Container(
              margin: const EdgeInsets.all(16),
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    PageView.builder(
                      itemCount: images.isEmpty ? 1 : images.length,
                      onPageChanged: (i) => setState(() => _currentImage = i),
                      itemBuilder: (_, i) {
                        final url = images.isNotEmpty
                            ? images[i].filePath
                            : p.mainImageUrl;
                        return Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(16),
                          child: url != null
                              ? Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.medical_services_outlined,
                                    size: 60,
                                    color: AppColors.border,
                                  ),
                                )
                              : const Icon(
                                  Icons.medical_services_outlined,
                                  size: 60,
                                  color: AppColors.border,
                                ),
                        );
                      },
                    ),
                    // Dots
                    if (images.length > 1)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            images.length,
                            (i) => Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _currentImage
                                    ? AppColors.primary
                                    : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // Product info in white card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border.withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      p.categoryLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Name
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Brand & Model
                  Text(
                    'Marca: ${p.brand ?? "-"}  ·  Modelo: ${p.model ?? "-"}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  Text(
                    'SKU: ${p.sku}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),

                  // Prices
                  if (p.hasDiscount)
                    Row(
                      children: [
                        Text(
                          p.formattedOldPrice,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade400,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '¡Descuento!',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text(
                    p.formattedPrice,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Indicators: Shipping, Warranty, Stock
                  _buildDetailPills(p),
                ],
              ),
            ),

            // Description in white card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border.withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Descripción',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.description ?? 'Sin descripción.',
                    maxLines: _descExpanded ? 100 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  if ((p.description?.length ?? 0) > 100)
                    GestureDetector(
                      onTap: () => setState(() => _descExpanded = !_descExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _descExpanded ? 'Ver menos' : 'Ver más',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Specs in soft highlight background card
            if (p.specs.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.softHighlight.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.softHighlight.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Especificaciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...p.specs.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                s.specKey,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.specValue,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 100), // space for bottom buttons
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Add to cart button: primary color, white text
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loadingDirectBuy
                        ? null
                        : () async {
                            final hasStock = await _validateStock(p);
                            if (!hasStock) return;
                            try {
                              await CartService.addToCart(p.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${p.name} agregado al carrito'),
                                    duration: const Duration(seconds: 1),
                                    backgroundColor: AppColors.primary,
                                  ),
                                );
                              }
                            } catch (e) {
                              final msg = e.toString().replaceAll('Exception: ', '');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(msg),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text(
                      'Al Carrito',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Direct checkout button: secondary/accent color, dark text
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loadingDirectBuy ? null : () => _buyNow(p),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _loadingDirectBuy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.textPrimary,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.flash_on, size: 18),
                    label: Text(
                      _loadingDirectBuy ? 'Cargando...' : 'Comprar Ahora',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPills(Product p) {
    // 1. Shipping info
    final shipBg = p.hasFreeShipping
        ? AppColors.softHighlight
        : Colors.grey.shade100;
    final shipFg = p.hasFreeShipping
        ? AppColors.darkTeal
        : AppColors.textSecondary;
    final shipText = p.shippingInfo ?? 'Consultar envío';

    // 2. Warranty info
    final warBg = AppColors.background;
    final warFg = AppColors.primary;
    final warText = p.warrantyText ?? 'Garantía oficial Go Medical';

    // 3. Stock/Availability info
    Color stockBg = AppColors.softHighlight.withOpacity(0.3);
    Color stockFg = AppColors.darkTeal;
    String stockText = 'Stock no administrado';
    
    if (p.trackInventory) {
      if (p.stock != null) {
        if (p.stock! <= 0) {
          stockBg = const Color(0xFFFEE2E2);
          stockFg = const Color(0xFFEF4444);
          stockText = 'Sin stock';
        } else if (p.stockStatus == 'low_stock' || p.stock! <= 5) {
          stockBg = AppColors.accent.withOpacity(0.18);
          stockFg = const Color(0xFFD97706);
          stockText = 'Stock disponible: ${p.stock} unidades (¡Pocas piezas!)';
        } else {
          stockBg = AppColors.background;
          stockFg = AppColors.primary;
          stockText = 'Stock disponible: ${p.stock} unidades';
        }
      } else {
        stockBg = AppColors.softHighlight.withOpacity(0.3);
        stockFg = AppColors.darkTeal;
        stockText = 'Stock no disponible';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pillRow(Icons.local_shipping_outlined, shipText, shipFg, shipBg),
        const SizedBox(height: 8),
        _pillRow(Icons.verified_user_outlined, warText, warFg, warBg),
        if (p.trackInventory) ...[
          const SizedBox(height: 8),
          _pillRow(Icons.inventory_2_outlined, stockText, stockFg, stockBg),
        ],
      ],
    );
  }

  Widget _pillRow(IconData icon, String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: fg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
