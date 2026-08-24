import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://hdxrlmknrkkagsfzncnb.supabase.co';
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkeHJsbWtucmtrYWdzZnpuY25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NzAwMDYsImV4cCI6MjA5MzU0NjAwNn0.gzeSznxzye68BbwOFtzuLHm-fMpEIf-50YRQwA2JATA';

async function main() {
  const email = process.env.E2E_STAFF_EMAIL?.trim();
  const password = process.env.E2E_STAFF_PASSWORD?.trim();

  if (!email || !password) {
    console.error('ERROR: Variables E2E_STAFF_EMAIL y E2E_STAFF_PASSWORD requeridas.');
    process.exit(1);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  console.log('==================================================');
  console.log('E2E-3: CREACIÓN CONTROLADA DE COTIZACIÓN (STAFF)');
  console.log('==================================================');
  console.log('Autenticando usuario staff...');

  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (authError || !authData.user) {
    console.error('AUTH: FAIL -', authError?.message || 'Usuario no encontrado');
    process.exit(1);
  }

  console.log('AUTH: OK');

  const ticketId = '60d24722-724c-42aa-864b-f8669f238bb3';
  const items = [
    {
      product_name_snapshot: 'Mantenimiento preventivo E2E',
      quantity: 1,
      unit_price: 100.0,
      discount: 0.0,
    },
    {
      product_name_snapshot: 'Diagnóstico técnico bonificado E2E',
      quantity: 1,
      unit_price: 50.0,
      discount: 50.0,
    },
  ];

  console.log('Invocando RPC create_service_quote en modo draft...');

  const { data: rpcData, error: rpcError } = await supabase.rpc('create_service_quote', {
    p_ticket_id: ticketId,
    p_items: items,
    p_valid_until: '2026-08-27',
    p_notes: 'PRUEBA E2E - NO ES SERVICIO REAL',
    p_tax_exempt: false,
  });

  if (rpcError) {
    console.error('RPC ERROR:', rpcError.message);
    if (rpcError.details) console.error('DETAILS:', rpcError.details);
    process.exit(1);
  }

  console.log('');
  console.log('==================================================');
  console.log('RESULTADO DE CREACIÓN DE COTIZACIÓN');
  console.log('==================================================');
  console.log('QUOTE CREATED: YES');
  console.log(`QUOTE ID: ${rpcData.quote_id}`);
  console.log(`QUOTE NUMBER: ${rpcData.quote_number}`);
  console.log(`STATUS: ${rpcData.status}`);
  console.log(`SUBTOTAL: $${rpcData.subtotal}`);
  console.log(`TAX: $${rpcData.tax}`);
  console.log(`TOTAL: $${rpcData.total}`);
  console.log(`ITEMS COUNT: ${rpcData.item_count}`);
  console.log('==================================================');

  await supabase.auth.signOut();
}

main().catch((err) => {
  console.error('UNEXPECTED ERROR:', err);
  process.exit(1);
});
