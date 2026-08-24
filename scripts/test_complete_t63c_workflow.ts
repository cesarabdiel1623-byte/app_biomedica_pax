import { createClient } from '@supabase/supabase-js';
import * as fs from 'fs';
import * as path from 'path';
// @ts-ignore
import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs';
// @ts-ignore
import { createCanvas } from '@napi-rs/canvas';

const SUPABASE_URL = 'https://hdxrlmknrkkagsfzncnb.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkeHJsbWtucmtrYWdzZnpuY25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NzAwMDYsImV4cCI6MjA5MzU0NjAwNn0.gzeSznxzye68BbwOFtzuLHm-fMpEIf-50YRQwA2JATA';

const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/generate-service-order-pdf`;

const OWNER_TICKET_ID = '4904b2a5-914e-4883-8876-d005cf6189fd'; // TCK-20260817-90B49A25 (cesar puerto)
const OTHER_CLIENT_TICKET_ID = 'ab04dc09-25b5-44fe-bb7a-80ef39c07b33'; // TCK-20260810-A3B5792B (other client)
const NON_EXISTENT_TICKET_ID = '00000000-0000-0000-0000-000000000000';

async function renderPdfToPng(pdfBuffer: Uint8Array, pngPath: string) {
  const loadingTask = pdfjsLib.getDocument({ data: new Uint8Array(pdfBuffer) });
  const pdfDoc = await loadingTask.promise;
  const page = await pdfDoc.getPage(1);
  const scale = 2.0;
  const viewport = page.getViewport({ scale });
  const canvas = createCanvas(viewport.width, viewport.height);
  const ctx = canvas.getContext('2d');
  await page.render({ canvasContext: ctx, viewport }).promise;
  fs.writeFileSync(pngPath, canvas.toBuffer('image/png'));
}

async function main() {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  console.log('Authenticating as ticket owner (cesarpuerto10@gmail.com)...');
  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
    email: 'cesarpuerto10@gmail.com',
    password: '123456',
  });

  if (authError || !authData.session) {
    throw new Error(`Authentication failed: ${authError?.message}`);
  }

  const ownerToken = authData.session.access_token;
  console.log(`✓ Owner authenticated successfully (User ID: ${authData.user.id})\n`);

  // --- 1. PRUEBA 401 SIN JWT ---
  console.log('--- TEST 1: Request without JWT (Expect 401) ---');
  const resNoAuth = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ticket_id: OWNER_TICKET_ID }),
  });
  console.log(`Status: ${resNoAuth.status}`);
  if (resNoAuth.status !== 401) throw new Error(`Expected 401, got ${resNoAuth.status}`);
  console.log('✓ Test 1 passed: 401 without JWT\n');

  // --- 2. PRUEBA 401 TOKEN INVÁLIDO ---
  console.log('--- TEST 2: Request with invalid JWT (Expect 401) ---');
  const resBadAuth = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer invalid_token',
    },
    body: JSON.stringify({ ticket_id: OWNER_TICKET_ID }),
  });
  console.log(`Status: ${resBadAuth.status}`);
  if (resBadAuth.status !== 401) throw new Error(`Expected 401, got ${resBadAuth.status}`);
  console.log('✓ Test 2 passed: 401 with invalid JWT\n');

  // --- 3. PRUEBA 400 BODY INVÁLIDO ---
  console.log('--- TEST 3: Request with malformed ticket_id (Expect 400) ---');
  const resBadBody = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${ownerToken}`,
    },
    body: JSON.stringify({ ticket_id: 'not-a-uuid' }),
  });
  console.log(`Status: ${resBadBody.status}`);
  if (resBadBody.status !== 400) throw new Error(`Expected 400, got ${resBadBody.status}`);
  console.log('✓ Test 3 passed: 400 for malformed UUID\n');

  // --- 4. PRUEBA 404 TICKET INEXISTENTE ---
  console.log('--- TEST 4: Request with non-existent ticket_id (Expect 404) ---');
  const resNotFound = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${ownerToken}`,
    },
    body: JSON.stringify({ ticket_id: NON_EXISTENT_TICKET_ID }),
  });
  console.log(`Status: ${resNotFound.status}`);
  if (resNotFound.status !== 404) throw new Error(`Expected 404, got ${resNotFound.status}`);
  console.log('✓ Test 4 passed: 404 for non-existent ticket\n');

  // --- 5. PRUEBA 403 OWNERSHIP (TICKET DE OTRO CLIENTE) ---
  console.log('--- TEST 5: Request for ticket belonging to another client (Expect 403) ---');
  const resForbidden = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${ownerToken}`,
    },
    body: JSON.stringify({ ticket_id: OTHER_CLIENT_TICKET_ID }),
  });
  console.log(`Status: ${resForbidden.status}`);
  const forbiddenBody = await resForbidden.json();
  console.log('Body:', forbiddenBody);
  if (resForbidden.status !== 403) throw new Error(`Expected 403, got ${resForbidden.status}`);
  console.log('✓ Test 5 passed: 403 Forbidden when accessing another client\'s ticket\n');

  // --- 6. PRUEBA 200 PROPIETARIO REAL ---
  console.log('--- TEST 6: Request for own ticket TCK-20260817-90B49A25 (Expect 200) ---');
  const resSuccess = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${ownerToken}`,
    },
    body: JSON.stringify({ ticket_id: OWNER_TICKET_ID }),
  });
  console.log(`Status: ${resSuccess.status}`);
  const successBody = await resSuccess.json();
  console.log('Response Body:', {
    ok: successBody.ok,
    document_type: successBody.document_type,
    ticket_number: successBody.ticket_number,
    path: successBody.path,
    expires_in: successBody.expires_in,
    signed_url_preview: successBody.signed_url ? `${successBody.signed_url.slice(0, 75)}...` : null,
  });

  if (resSuccess.status !== 200 || !successBody.ok || !successBody.signed_url) {
    throw new Error(`Expected 200 with signed_url, got ${resSuccess.status}: ${JSON.stringify(successBody)}`);
  }
  console.log('✓ Test 6 passed: Edge Function generated PDF and returned Signed URL!\n');

  // --- 7. DESCARGA Y VALIDACIÓN VISUAL DEL PDF ---
  console.log('Downloading generated PDF via Signed URL...');
  const pdfDownloadRes = await fetch(successBody.signed_url);
  if (!pdfDownloadRes.ok) {
    throw new Error(`Failed to download PDF from Signed URL: ${pdfDownloadRes.status}`);
  }
  const downloadedBytes = new Uint8Array(await pdfDownloadRes.arrayBuffer());
  console.log(`✓ Downloaded ${downloadedBytes.length} bytes`);

  const tmpDir = path.resolve(__dirname, '../tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  const downloadedPdfPath = path.join(tmpDir, 'TCK-20260817-90B49A25_edge_download.pdf');
  const downloadedPngPath = path.join(tmpDir, 'TCK-20260817-90B49A25_edge_download.png');
  fs.writeFileSync(downloadedPdfPath, downloadedBytes);
  console.log(`Saved downloaded PDF to: ${downloadedPdfPath}`);

  console.log('Rendering downloaded PDF to high-resolution PNG for visual validation...');
  await renderPdfToPng(downloadedBytes, downloadedPngPath);
  console.log(`Saved PNG to: ${downloadedPngPath}`);

  // --- 8. PRUEBA DE IDEMPOTENCIA ---
  console.log('\n--- TEST 8: Idempotency (Repeat generation for same ticket) ---');
  const resRepeat = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${ownerToken}`,
    },
    body: JSON.stringify({ ticket_id: OWNER_TICKET_ID }),
  });
  console.log(`Status: ${resRepeat.status}`);
  const repeatBody = await resRepeat.json();
  if (resRepeat.status !== 200 || repeatBody.path !== successBody.path) {
    throw new Error('Idempotency failed: different path returned');
  }
  console.log(`✓ Test 8 passed: Same storage path reused (${repeatBody.path})\n`);

  console.log('═══════════════════════════════════════════════════════');
  console.log('ALL EDGE FUNCTION TESTS PASSED (100% SUCCESS)');
  console.log('═══════════════════════════════════════════════════════');
}

main().catch((err) => {
  console.error('Test workflow failed:', err);
  process.exit(1);
});
