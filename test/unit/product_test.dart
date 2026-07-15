import 'package:flutter_test/flutter_test.dart';
import 'package:gomedical_app/models/product.dart';
import 'package:flutter/material.dart';

void main() {
  group('Product Unit Tests - Getters & Basic Logic', () {
    test('conditionLabel returns correct Spanish string based on productCondition', () {
      final p1 = Product(
        id: '1', sku: 'S1', name: 'P1', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        productCondition: 'preowned', createdAt: DateTime.now(),
      );
      expect(p1.conditionLabel, 'Seminuevo');

      final p2 = Product(
        id: '2', sku: 'S2', name: 'P2', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        productCondition: 'new', createdAt: DateTime.now(),
      );
      expect(p2.conditionLabel, 'Nuevo');

      final p3 = Product(
        id: '3', sku: 'S3', name: 'P3', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        productCondition: 'remanufactured', createdAt: DateTime.now(),
      );
      expect(p3.conditionLabel, 'Remanofacturado');
    });

    test('stockStatusLabel returns correct value based on current and minimum stock', () {
      final p1 = Product(
        id: '1', sku: 'S1', name: 'P1', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        currentStock: 0, minimumStock: 2, createdAt: DateTime.now(),
      );
      expect(p1.stockStatusLabel, 'Sin stock');
      expect(p1.stockStatusColor, const Color(0xFFEF4444));

      final p2 = Product(
        id: '2', sku: 'S2', name: 'P2', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        currentStock: 1, minimumStock: 2, createdAt: DateTime.now(),
      );
      expect(p2.stockStatusLabel, 'Bajo stock');
      expect(p2.stockStatusColor, const Color(0xFFD97706));

      final p3 = Product(
        id: '3', sku: 'S3', name: 'P3', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        currentStock: 5, minimumStock: 2, createdAt: DateTime.now(),
      );
      expect(p3.stockStatusLabel, 'Disponible');
      expect(p3.stockStatusColor, const Color(0xFF16A34A));
    });

    test('hasDiscount and discountPercent return correct values', () {
      final pNoPromo = Product(
        id: '1', sku: 'S1', name: 'P1', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        createdAt: DateTime.now(),
      );
      expect(pNoPromo.hasDiscount, false);
      expect(pNoPromo.discountPercent, 0);

      final pPromo = Product(
        id: '2', sku: 'S2', name: 'P2', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 80.0, costPriceMxn: 60.0, oldPrice: 100.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        createdAt: DateTime.now(),
      );
      expect(pPromo.hasDiscount, true);
      expect(pPromo.discountPercent, 20);
    });

    test('categoryLabel converts category strings properly', () {
      final p = Product(
        id: '1', sku: 'S1', name: 'P1', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 100.0, costPriceMxn: 80.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        createdAt: DateTime.now(),
      );
      expect(p.categoryLabel, 'Equipos Médicos');
    });

    test('formattedPrice and formattedOldPrice format currency correct', () {
      final p = Product(
        id: '1', sku: 'S1', name: 'P1', category: 'equipo_medico', application: 'general',
        unitPriceMxn: 1250.50, costPriceMxn: 80.0, oldPrice: 1500.0, currency: 'MXN', unit: 'pz',
        isActive: true, requiresSerial: false, trackInventory: true,
        createdAt: DateTime.now(),
      );
      expect(p.formattedPrice, '\$1,250.50');
      expect(p.formattedOldPrice, '\$1,500.00');
    });
  });

  group('Product Unit Tests - JSON Parsing & Promotions', () {
    test('Product.fromJson parses percentage promotions correctly', () {
      final json = {
        'id': 'promo-1',
        'sku': 'SKU-PROMO',
        'name': 'Ultrasonido Pro',
        'category': 'ultrasonido_humano',
        'application': 'humano',
        'unit_price_mxn': 100000.0,
        'cost_price_mxn': 70000.0,
        'currency': 'MXN',
        'unit': 'unidad',
        'is_active': true,
        'requires_serial': true,
        'track_inventory': true,
        'created_at': '2026-01-01T00:00:00Z',
        'active_product_promotions': [
          {
            'id': 'prom-id-1',
            'product_id': 'promo-1',
            'discount_type': 'percentage',
            'discount_value': 15.0,
            'campaign_name': 'Buen Fin',
          }
        ]
      };

      final p = Product.fromJson(json);
      expect(p.unitPriceMxn, 85000.0);
      expect(p.oldPrice, 100000.0);
      expect(p.hasDiscount, true);
      expect(p.discountPercent, 15);
    });

    test('Product.fromJson parses fixed_amount promotions correctly', () {
      final json = {
        'id': 'promo-2',
        'sku': 'SKU-PROMO',
        'name': 'Consumible USG',
        'category': 'consumible',
        'application': 'general',
        'unit_price_mxn': 500.0,
        'cost_price_mxn': 300.0,
        'currency': 'MXN',
        'unit': 'pieza',
        'is_active': true,
        'requires_serial': false,
        'track_inventory': true,
        'created_at': '2026-01-01T00:00:00Z',
        'active_product_promotions': [
          {
            'id': 'prom-id-2',
            'product_id': 'promo-2',
            'discount_type': 'fixed_amount',
            'discount_value': 50.0,
          }
        ]
      };

      final p = Product.fromJson(json);
      expect(p.unitPriceMxn, 450.0);
      expect(p.oldPrice, 500.0);
      expect(p.discountPercent, 10);
    });

    test('Product.fromJson parses promotional_price correctly', () {
      final json = {
        'id': 'promo-3',
        'sku': 'SKU-PROMO',
        'name': 'Refaccion Especial',
        'category': 'refaccion',
        'application': 'general',
        'unit_price_mxn': 1200.0,
        'cost_price_mxn': 500.0,
        'currency': 'MXN',
        'unit': 'pieza',
        'is_active': true,
        'requires_serial': false,
        'track_inventory': true,
        'created_at': '2026-01-01T00:00:00Z',
        'active_product_promotions': [
          {
            'id': 'prom-id-3',
            'product_id': 'promo-3',
            'discount_type': 'promotional_price',
            'discount_value': 900.0,
          }
        ]
      };

      final p = Product.fromJson(json);
      expect(p.unitPriceMxn, 900.0);
      expect(p.oldPrice, 1200.0);
      expect(p.discountPercent, 25);
    });

    test('Product.fromJson parses sales_count correctly from real DB JSON', () {
      // Simulates the real JSON response from Supabase for Ultrasonido animal (sales_count: 120)
      final json = {
        'id': 'ab17a9b5-999d-4ac6-88a9-dd3fb7b895ff',
        'sku': 'SKU-USAN',
        'name': 'Ultrasonido animal',
        'category': 'ultrasonido_animal',
        'application': 'veterinario',
        'unit_price_mxn': 30000.0,
        'cost_price_mxn': 20000.0,
        'currency': 'MXN',
        'unit': 'pieza',
        'is_active': true,
        'requires_serial': false,
        'track_inventory': true,
        'created_at': '2026-01-01T00:00:00Z',
        'sales_count': 120,
      };

      final p = Product.fromJson(json);
      // Verifica que el salesCount se lee directo de la BD sin modificar
      expect(p.salesCount, 120);
    });
  });
}
