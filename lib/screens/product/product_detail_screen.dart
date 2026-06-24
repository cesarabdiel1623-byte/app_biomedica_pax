import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/cart_service.dart';
import '../../services/search_service.dart';
import '../../services/quote_service.dart';
import 'quote_cart_screen.dart';
import '../home/home_screen.dart';

const _kPrimary = Color(0xFF0D9488);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFEF4444);
const _kNavy = Color(0xFF1E3A5F);

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
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final p = await ProductService.getProductById(widget.productId);
      if (p != null) {
        await SearchService.addToRecentlyViewed(p);
      }
      if (mounted) setState(() { _product = p; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buyNow(Product p) async {
    setState(() => _loadingDirectBuy = true);
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
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
        appBar: AppBar(backgroundColor: _kPrimary, foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }
    if (_product == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: _kPrimary, foregroundColor: Colors.white),
        body: const Center(child: Text('Producto no encontrado')),
      );
    }
    final p = _product!;
    final images = p.images.isNotEmpty ? p.images : [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Detalle', style: TextStyle(fontSize: 16)),
      ),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image gallery
          SizedBox(
            height: 280,
            child: Stack(children: [
              PageView.builder(
                itemCount: images.isEmpty ? 1 : images.length,
                onPageChanged: (i) => setState(() => _currentImage = i),
                itemBuilder: (_, i) {
                  final url = images.isNotEmpty ? images[i].filePath : p.mainImageUrl;
                  return Container(
                    color: const Color(0xFFF5F5F5),
                    child: url != null
                      ? Image.network(url, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.medical_services, size: 60, color: Colors.grey))
                      : const Icon(Icons.medical_services, size: 60, color: Colors.grey),
                  );
                },
              ),
              // Dots
              if (images.length > 1)
                Positioned(bottom: 8, left: 0, right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(images.length, (i) => Container(
                      width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        color: i == _currentImage ? _kPrimary : Colors.grey.shade400),
                    )),
                  ),
                ),
            ]),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)),
                child: Text(p.categoryLabel, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
              ),
              const SizedBox(height: 10),
              if (p.activePromotion != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kRed.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign, color: _kRed, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Campaña: ${p.activePromotion!.campaignName ?? "Oferta Especial"}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kRed),
                            ),
                            if (p.activePromotion!.endsAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Vence: ${_formatDate(p.activePromotion!.endsAt!)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Prices
              if (p.hasDiscount) Row(children: [
                Text(p.formattedOldPrice, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: _kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
                  child: Text('${p.discountPercent}% OFF', style: const TextStyle(fontSize: 11, color: _kGreen, fontWeight: FontWeight.bold)),
                ),
              ]),
              Text(p.formattedPrice, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
              const SizedBox(height: 10),
              // Name
              Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.3)),
              const SizedBox(height: 6),
              // Brand + model
              Text('Marca: ${p.brand ?? "-"} · Modelo: ${p.model ?? "-"}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              Text('SKU: ${p.sku}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 14),
              // Shipping, warranty, availability
              _infoRow(Icons.local_shipping_outlined, p.shippingInfo ?? 'Consultar', p.hasFreeShipping ? _kGreen : Colors.grey.shade700),
              _infoRow(Icons.verified_user_outlined, p.warrantyText ?? 'Consultar', Colors.grey.shade700),
              _infoRow(
                Icons.inventory_2_outlined,
                p.stockStatusLabel,
                p.stockStatusColor,
              ),
              const SizedBox(height: 16),
              // Description
              const Divider(),
              const SizedBox(height: 8),
              const Text('Descripción', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(p.description ?? 'Sin descripción.',
                maxLines: _descExpanded ? 100 : 3, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5)),
              if ((p.description?.length ?? 0) > 100)
                GestureDetector(
                  onTap: () => setState(() => _descExpanded = !_descExpanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_descExpanded ? 'Ver menos' : 'Ver más',
                      style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              // Specs
              if (p.specs.isNotEmpty) ...[
                const SizedBox(height: 16), const Divider(), const SizedBox(height: 8),
                const Text('Especificaciones', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...p.specs.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(width: 120, child: Text(s.specKey,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
                    Expanded(child: Text(s.specValue,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  ]),
                )),
              ],
              const SizedBox(height: 80), // Space for bottom button
            ]),
          ),
        ]),
      ),
      // Bottom bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Add to cart button
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _loadingDirectBuy ? null : () async {
                          try {
                            await CartService.addToCart(p.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              final controller = ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ ${p.name} al carrito'),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: _kPrimary,
                                  action: SnackBarAction(
                                    label: 'VER CARRITO',
                                    textColor: Colors.white,
                                    onPressed: () {
                                      Navigator.popUntil(context, (route) => route.isFirst);
                                      HomeScreen.showTab(2);
                                    },
                                  ),
                                ),
                              );
                              Future.delayed(const Duration(seconds: 2), () {
                                try { controller.close(); } catch (_) {}
                              });
                            }
                          } catch (e) {
                            final msg = e.toString().replaceAll('Exception: ', '');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(msg), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPrimary,
                          side: const BorderSide(color: _kPrimary, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                        label: const Text('Al Carrito', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Buy Now button
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _loadingDirectBuy ? null : () => _buyNow(p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        icon: _loadingDirectBuy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.flash_on, size: 20),
                        label: Text(
                          _loadingDirectBuy ? 'Cargando...' : 'Comprar Ahora',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Add to Quote button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _loadingDirectBuy ? null : () async {
                    try {
                      await QuoteService.addToQuote(p);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        final controller = ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ ${p.name} añadido a cotización'),
                            duration: const Duration(seconds: 2),
                            backgroundColor: _kNavy,
                            action: SnackBarAction(
                              label: 'VER BOLSA',
                              textColor: Colors.white,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const QuoteCartScreen()),
                                );
                              },
                            ),
                          ),
                        );
                        Future.delayed(const Duration(seconds: 2), () {
                          try { controller.close(); } catch (_) {}
                        });
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kNavy, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.request_quote_outlined, size: 20),
                  label: const Text('Cotizar este Producto', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500))),
    ]),
  );

  String _formatDate(DateTime dt) {
    final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day $month $year, $hour:$min';
  }
}
