import 'package:flutter/material.dart';
import '../../product/category_products_screen.dart';
import '../home_screen.dart';

class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});
  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab> {
  int _selectedIndex = 0;

  static final _categories = [
    {
      'key': 'equipo_medico', 'label': 'Equipos\nMédicos',
      'icon': Icons.medical_services, 'color': const Color(0xFF0D9488),
      'subs': [
        {'label': 'Ultrasonido', 'icon': Icons.monitor_heart, 'color': const Color(0xFF0EA5E9)},
        {'label': 'Rayos X', 'icon': Icons.radio_button_checked, 'color': const Color(0xFF6366F1)},
        {'label': 'Monitores', 'icon': Icons.desktop_windows, 'color': const Color(0xFF0D9488)},
        {'label': 'ECG / Cardio', 'icon': Icons.favorite, 'color': const Color(0xFFEF4444)},
        {'label': 'Soporte Vida', 'icon': Icons.health_and_safety, 'color': const Color(0xFFF59E0B)},
        {'label': 'PACS Nube', 'icon': Icons.cloud, 'color': const Color(0xFF3B82F6)},
        {'label': 'Quirúrgico', 'icon': Icons.content_cut, 'color': const Color(0xFFEC4899)},
        {'label': 'Rehabilitación', 'icon': Icons.accessibility_new, 'color': const Color(0xFF10B981)},
        {'label': 'Oftalmología', 'icon': Icons.visibility, 'color': const Color(0xFF8B5CF6)},
      ],
    },
    {
      'key': 'ultrasonido_humano', 'label': 'Ultrasonido',
      'icon': Icons.monitor_heart, 'color': const Color(0xFF3B82F6),
      'subs': [
        {'label': 'Portátil', 'icon': Icons.monitor_heart, 'color': const Color(0xFF3B82F6)},
        {'label': 'Convexo', 'icon': Icons.sensors, 'color': const Color(0xFF0D9488)},
        {'label': 'Doppler Color', 'icon': Icons.waterfall_chart, 'color': const Color(0xFFEC4899)},
        {'label': 'PACS', 'icon': Icons.cloud, 'color': const Color(0xFF0EA5E9)},
      ],
    },
    {
      'key': 'consumible', 'label': 'Consumibles',
      'icon': Icons.water_drop, 'color': const Color(0xFF0EA5E9),
      'subs': [
        {'label': 'Gel USG', 'icon': Icons.water_drop, 'color': const Color(0xFF0EA5E9)},
        {'label': 'Papel Térmico', 'icon': Icons.receipt, 'color': const Color(0xFF6B7280)},
        {'label': 'Electrodos', 'icon': Icons.electrical_services, 'color': const Color(0xFFEF4444)},
        {'label': 'Guantes', 'icon': Icons.back_hand, 'color': const Color(0xFF3B82F6)},
        {'label': 'Sondas Foley', 'icon': Icons.device_hub, 'color': const Color(0xFF10B981)},
      ],
    },
    {
      'key': 'refaccion', 'label': 'Refacciones',
      'icon': Icons.build, 'color': const Color(0xFFEC4899),
      'subs': [
        {'label': 'Transductores', 'icon': Icons.sensors, 'color': const Color(0xFFEC4899)},
        {'label': 'Cables ECG', 'icon': Icons.cable, 'color': const Color(0xFFEF4444)},
        {'label': 'Pantallas', 'icon': Icons.monitor, 'color': const Color(0xFF3B82F6)},
        {'label': 'Baterías', 'icon': Icons.battery_charging_full, 'color': const Color(0xFFF59E0B)},
        {'label': 'Fuentes Poder', 'icon': Icons.power, 'color': const Color(0xFF6366F1)},
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final current = _categories[_selectedIndex];
    final subs = current['subs'] as List;
    final catColor = current['color'] as Color;
    final catLabel = (current['label'] as String).replaceAll('\n', ' ');
    return Column(
      children: [
        // Barra verde superior
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [catColor, catColor.withValues(alpha: 0.82)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                    onPressed: () => HomeScreen.showTab(0),
                  ),
                  const SizedBox(width: 10),
                  Icon(current['icon'] as IconData, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Text(
                    catLabel,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Contenido: sidebar + grid
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sidebar de categorias pegado a la barra verde
              Container(
                width: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 5,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _categories.length,
                  itemBuilder: (_, i) {
                    final cat = _categories[i];
                    final active = i == _selectedIndex;
                    final color = cat['color'] as Color;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          color: active ? color.withValues(alpha: 0.09) : Colors.white,
                          border: Border(
                            left: BorderSide(
                              color: active ? color : Colors.transparent,
                              width: 3.5,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              cat['icon'] as IconData,
                              size: 22,
                              color: active ? color : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cat['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.2,
                                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                color: active ? Colors.black87 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Grid de subcategorias
              Expanded(
                child: Container(
                  color: const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.all(12),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: subs.length,
                    itemBuilder: (_, i) {
                      final sub = subs[i];
                      final color = sub['color'] as Color;
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CategoryProductsScreen(
                                categoryKey: current['key'] as String,
                                subcategoryLabel: sub['label'] as String,
                                categoryLabel: catLabel,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200, width: 0.8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(sub['icon'] as IconData, color: color, size: 24),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  sub['label'] as String,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
