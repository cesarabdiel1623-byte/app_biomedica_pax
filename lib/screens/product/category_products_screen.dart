import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/cart_service.dart';
import '../../core/theme/app_colors.dart';
import '../product/product_detail_screen.dart';

const _kPrimary = AppColors.primary;
const _kNavy = AppColors.textPrimary;
const _kGreen = AppColors.secondary;
const _kRed = AppColors.error;

class CategoryProductsScreen extends StatefulWidget {
  final String categoryKey;
  final String categoryLabel;
  final String subcategoryLabel;

  const CategoryProductsScreen({
    super.key,
    required this.categoryKey,
    required this.categoryLabel,
    required this.subcategoryLabel,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  List<Product> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  // Mapea la categoría de la UI al enum de la base de datos
  String get _dbCategoryKey {
    switch (widget.categoryKey) {
      case 'veterinaria':
        return 'ultrasonido_veterinario';
      default:
        return widget.categoryKey;
    }
  }

  // Mapea la subcategoría de la UI al valor esperado en base de datos
  String get _dbSubcategoryKey {
    final sub = widget.subcategoryLabel.toLowerCase().trim();
    if (sub.contains('ultrasonido')) return 'ultrasonido';
    if (sub.contains('rayos x')) return 'rayos_x';
    if (sub.contains('monitores')) return 'monitores';
    if (sub.contains('ecg')) return 'ecg';
    if (sub.contains('soporte vida') || sub.contains('soporte de vida'))
      return 'soporte_vida';
    if (sub.contains('pacs')) return 'pacs';
    if (sub.contains('quirúrgico') || sub.contains('quirurgico'))
      return 'quirurgico';
    if (sub.contains('rehabilitación') || sub.contains('rehabilitacion'))
      return 'rehabilitacion';
    if (sub.contains('oftalmología') || sub.contains('oftalmologia'))
      return 'oftalmologia';
    if (sub.contains('portátil') || sub.contains('portatil')) return 'portatil';
    if (sub.contains('convexo')) return 'convexo';
    if (sub.contains('doppler')) return 'doppler_color';
    if (sub.contains('veterinario')) return 'veterinario';
    if (sub.contains('monitor vet')) return 'monitor_vet';
    if (sub.contains('usg vet')) return 'usg_vet';
    if (sub.contains('anestesia')) return 'anestesia';
    if (sub.contains('dental')) return 'dental_vet';
    if (sub.contains('química') || sub.contains('quimica'))
      return 'quimica_clinica';
    if (sub.contains('hematología') || sub.contains('hematologia'))
      return 'hematologia';
    if (sub.contains('urianálisis') || sub.contains('urianalisis'))
      return 'urianalisis';
    if (sub.contains('microscopía') || sub.contains('microscopia'))
      return 'microscopia';
    if (sub.contains('centrífugas') || sub.contains('centrifugas'))
      return 'centrifugas';
    if (sub.contains('gel')) return 'gel';
    if (sub.contains('papel')) return 'papel_termico';
    if (sub.contains('electrodo')) return 'electrodos';
    if (sub.contains('guante')) return 'guantes';
    if (sub.contains('foley') || sub.contains('sonda')) return 'sondas_foley';
    if (sub.contains('transductor') || sub.contains('sonda')) return 'sondas';
    if (sub.contains('cable')) return 'cables_ecg';
    if (sub.contains('pantalla')) return 'pantallas';
    if (sub.contains('batería') || sub.contains('bateria')) return 'baterias';
    if (sub.contains('fuente')) return 'fuentes_poder';
    if (sub.contains('preventivo')) return 'preventivo';
    if (sub.contains('correctivo')) return 'correctivo';
    if (sub.contains('calibración') || sub.contains('calibracion'))
      return 'calibracion';
    if (sub.contains('instalación') || sub.contains('instalacion'))
      return 'instalacion';
    if (sub.contains('capacitación') || sub.contains('capacitacion'))
      return 'capacitacion';
    if (sub.contains('garantía') || sub.contains('garantia')) return 'garantia';
    return sub;
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dbCategory = _dbCategoryKey;
      final dbSubcategory = _dbSubcategoryKey;

      // 1. Intentar obtener productos con la categoría y subcategoría exactas
      final client = Supabase.instance.client;
      final response = await client
          .from('products')
          .select('''
            *,
            product_media(*),
            product_specs(*)
          ''')
          .eq('is_active', true)
          .eq('category', dbCategory)
          .eq('subcategory', dbSubcategory)
          .order('name');

      var list = (response as List)
          .map((json) => Product.fromJson(json))
          .toList();

      // 2. Si no arroja resultados, buscar todos los de la categoría y filtrar por palabras clave
      if (list.isEmpty) {
        final allCatProducts = await ProductService.getAllProducts(
          category: dbCategory,
        );
        final keyword = widget.subcategoryLabel.toLowerCase().trim();

        list = allCatProducts.where((p) {
          final name = p.name.toLowerCase();
          final desc = (p.description ?? '').toLowerCase();
          final sub = (p.subcategory ?? '').toLowerCase();

          // Palabras clave específicas según la subcategoría
          if (keyword == 'ultrasonido') {
            return name.contains('ultrasonido') ||
                name.contains('ecógrafo') ||
                name.contains('usg');
          } else if (keyword == 'pacs nube' || keyword == 'pacs') {
            return name.contains('pacs') ||
                name.contains('cloud') ||
                name.contains('nube');
          } else if (keyword == 'rayos x') {
            return name.contains('rayos') || name.contains('rx');
          } else if (keyword == 'ecg / cardio') {
            return name.contains('ecg') ||
                name.contains('electro') ||
                name.contains('cardio');
          } else if (keyword == 'soporte vida') {
            return name.contains('desfibrilador') ||
                name.contains('ventilador') ||
                name.contains('respirador') ||
                name.contains('dea');
          } else if (keyword == 'gel usg') {
            return name.contains('gel');
          } else if (keyword == 'papel térmico') {
            return name.contains('papel');
          } else if (keyword == 'transductores') {
            return name.contains('transductor') || name.contains('sonda');
          }

          // Filtro por defecto: contiene la palabra clave
          return name.contains(keyword) ||
              desc.contains(keyword) ||
              sub.contains(keyword);
        }).toList();
      }

      if (mounted) {
        setState(() {
          _products = list;
          _loading = false;
        });
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

  @override
  Widget build(BuildContext context) {
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
        centerTitle: false,
        shape: const Border(
          bottom: BorderSide(
            color: AppColors.border,
            width: 1.0,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subcategoryLabel.isNotEmpty ? widget.subcategoryLabel : widget.categoryLabel,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (widget.subcategoryLabel.isNotEmpty)
              Text(
                widget.categoryLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              const Text(
                'Error al cargar productos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadProducts,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.production_quantity_limits_outlined,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No hay en existencia',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Actualmente no contamos con productos disponibles para la subcategoría "${widget.subcategoryLabel}".',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Volver a Categorías'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _kPrimary,
      onRefresh: _loadProducts,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 280,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _products.length,
        itemBuilder: (context, i) => _ProductCard(product: _products[i]),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: product.id),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Imagen + cart button + badge ──────────
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                children: [
                  // Imagen
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      color: AppColors.background.withOpacity(0.4),
                      padding: const EdgeInsets.all(12),
                      child: product.mainImageUrl != null
                          ? Image.network(
                              product.mainImageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  // Badge de descuento en imagen (esquina sup izq)
                  if (product.hasDiscount)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${product.discountPercent}% OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // Botón carrito (esquina inf der)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: GestureDetector(
                      onTap: () async {
                        try {
                          await CartService.addToCart(product.id);
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✓ ${product.name} al carrito'),
                                duration: const Duration(seconds: 1),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                        } catch (e) {
                          final msg = e.toString().replaceAll(
                            'Exception: ',
                            '',
                          );
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                backgroundColor: AppColors.error,
                              ),
                            );
                        }
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Info del producto ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nombre
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Precio anterior y actual
                  Row(
                    children: [
                      Text(
                        product.formattedPrice,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      if (product.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            product.formattedOldPrice,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Brand/Modelo
                  Text(
                    (product.brand ?? product.commercialBrand) ?? 'Médico',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // Shipping & Stock pills/chips
                  Row(
                    children: [
                      // Stock pill
                      _buildStockPill(product),
                      const SizedBox(width: 6),
                      // Free shipping badge
                      if (product.hasFreeShipping)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.softHighlight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Envío gratis',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.darkTeal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockPill(Product p) {
    if (!p.trackInventory) return const SizedBox.shrink();
    Color bg;
    Color fg;
    String text;
    if (p.stock != null) {
      if (p.stock! <= 0) {
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFEF4444);
        text = 'Sin stock';
      } else if (p.stockStatus == 'low_stock' || p.stock! <= 5) {
        bg = AppColors.accent.withOpacity(0.18);
        fg = const Color(0xFFD97706);
        text = '${p.stock} dispon. (¡Últimas!)';
      } else {
        bg = AppColors.background;
        fg = AppColors.primary;
        text = '${p.stock} disponibles';
      }
    } else {
      bg = AppColors.softHighlight.withOpacity(0.3);
      fg = AppColors.darkTeal;
      text = 'Stock no disponible';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _placeholder() => Center(
    child: Icon(
      Icons.medical_services_outlined,
      color: AppColors.primary.withOpacity(0.2),
      size: 32,
    ),
  );
}
