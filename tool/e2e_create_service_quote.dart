import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _defaultSupabaseUrl = 'https://hdxrlmknrkkagsfzncnb.supabase.co';
const String _defaultAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkeHJsbWtucmtrYWdzZnpuY25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NzAwMDYsImV4cCI6MjA5MzU0NjAwNn0.gzeSznxzye68BbwOFtzuLHm-fMpEIf-50YRQwA2JATA';

Future<void> main() async {
  final email = Platform.environment['E2E_STAFF_EMAIL']?.trim() ?? '';
  final password = Platform.environment['E2E_STAFF_PASSWORD']?.trim() ?? '';

  if (email.isEmpty || password.isEmpty) {
    stderr.writeln(
      'ERROR: Las variables de entorno E2E_STAFF_EMAIL y E2E_STAFF_PASSWORD son requeridas.',
    );
    stderr.writeln('Ejemplo PowerShell seguro (sin guardar en historial):');
    stderr.writeln(
      '  \$email = Read-Host "Staff Email"; \$pass = Read-Host "Staff Password" -AsSecureString; \$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(\$pass); \$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(\$BSTR)',
    );
    stderr.writeln(
      '  \$env:E2E_STAFF_EMAIL = \$email; \$env:E2E_STAFF_PASSWORD = \$password; dart run tool/e2e_create_service_quote.dart; \$env:E2E_STAFF_PASSWORD = \$null',
    );
    exit(1);
  }

  final url = Platform.environment['SUPABASE_URL'] ?? _defaultSupabaseUrl;
  final anonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? _defaultAnonKey;

  final client = SupabaseClient(url, anonKey);

  stdout.writeln('==================================================');
  stdout.writeln('E2E-3: CREACIÓN CONTROLADA DE COTIZACIÓN (STAFF)');
  stdout.writeln('==================================================');
  stdout.writeln('Autenticando usuario staff...');

  try {
    final authRes = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (authRes.user == null) {
      stderr.writeln(
        'AUTH: FAIL (Credenciales inválidas o usuario no encontrado)',
      );
      exit(1);
    }

    stdout.writeln('AUTH: OK');

    // 1. Payload de la prueba E2E (Servicios con precio y bonificación)
    const ticketId = '60d24722-724c-42aa-864b-f8669f238bb3';
    final items = [
      {
        'product_name_snapshot': 'Mantenimiento preventivo E2E',
        'quantity': 1,
        'unit_price': 100.00,
        'discount': 0.00,
      },
      {
        'product_name_snapshot': 'Diagnóstico técnico bonificado E2E',
        'quantity': 1,
        'unit_price': 50.00,
        'discount': 50.00,
      },
    ];

    stdout.writeln('Invocando RPC create_service_quote en modo draft...');

    final rpcRes = await client.rpc(
      'create_service_quote',
      params: {
        'p_ticket_id': ticketId,
        'p_items': items,
        'p_valid_until': '2026-08-27',
        'p_notes': 'PRUEBA E2E - NO ES SERVICIO REAL',
        'p_tax_exempt': false,
      },
    );

    if (rpcRes is! Map) {
      stderr.writeln('ERROR: Respuesta inesperada del servidor: $rpcRes');
      exit(1);
    }

    final data = Map<String, dynamic>.from(rpcRes);

    stdout.writeln('');
    stdout.writeln('==================================================');
    stdout.writeln('RESULTADO DE CREACIÓN DE COTIZACIÓN');
    stdout.writeln('==================================================');
    stdout.writeln('QUOTE CREATED: YES');
    stdout.writeln('QUOTE ID: ${data['quote_id']}');
    stdout.writeln('QUOTE NUMBER: ${data['quote_number']}');
    stdout.writeln('STATUS: ${data['status']}');
    stdout.writeln('SUBTOTAL: \$${data['subtotal']}');
    stdout.writeln('TAX: \$${data['tax']}');
    stdout.writeln('TOTAL: \$${data['total']}');
    stdout.writeln('ITEMS COUNT: ${data['item_count']}');
    stdout.writeln('==================================================');
  } on AuthException catch (e) {
    stderr.writeln('AUTH ERROR (${e.statusCode}): ${e.message}');
    exit(1);
  } on PostgrestException catch (e) {
    stderr.writeln('RPC ERROR (${e.code}): ${e.message}');
    if (e.details != null) {
      stderr.writeln('DETAILS: ${e.details}');
    }
    exit(1);
  } catch (e) {
    stderr.writeln('UNEXPECTED ERROR: $e');
    exit(1);
  } finally {
    try {
      await client.auth.signOut();
    } catch (_) {}
  }
}
