import { createClient } from '@supabase/supabase-js';
import * as fs from 'fs';
import * as path from 'path';

const SUPABASE_URL = 'https://hdxrlmknrkkagsfzncnb.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkeHJsbWtucmtrYWdzZnpuY25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NzAwMDYsImV4cCI6MjA5MzU0NjAwNn0.gzeSznxzye68BbwOFtzuLHm-fMpEIf-50YRQwA2JATA';

const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/generate-service-order-pdf`;
const REAL_TICKET_ID = '4904b2a5-914e-4883-8876-d005cf6189fd';

async function main() {
  console.log('--- TEST 1: Calling without Authorization header (Expect 401) ---');
  const resNoAuth = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ticket_id: REAL_TICKET_ID }),
  });
  console.log(`Status: ${resNoAuth.status}`);
  const bodyNoAuth = await resNoAuth.json();
  console.log('Body:', bodyNoAuth);
  if (resNoAuth.status !== 401) {
    throw new Error(`Expected 401 but got ${resNoAuth.status}`);
  }
  console.log('✓ Test 1 passed: 401 returned without auth token\n');

  console.log('--- TEST 2: Calling with invalid token (Expect 401) ---');
  const resBadAuth = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer invalid_fake_jwt_token',
    },
    body: JSON.stringify({ ticket_id: REAL_TICKET_ID }),
  });
  console.log(`Status: ${resBadAuth.status}`);
  const bodyBadAuth = await resBadAuth.json();
  console.log('Body:', bodyBadAuth);
  if (resBadAuth.status !== 401) {
    throw new Error(`Expected 401 but got ${resBadAuth.status}`);
  }
  console.log('✓ Test 2 passed: 401 returned for invalid token\n');

  console.log('--- TEST 3: Calling OPTIONS (Expect 200 / ok) ---');
  const resOptions = await fetch(FUNCTION_URL, {
    method: 'OPTIONS',
  });
  console.log(`Status: ${resOptions.status}`);
  console.log('✓ Test 3 passed: OPTIONS returned 200\n');
}

main().catch((err) => {
  console.error('Error during test:', err);
  process.exit(1);
});
