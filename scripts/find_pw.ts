import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://hdxrlmknrkkagsfzncnb.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkeHJsbWtucmtrYWdzZnpuY25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NzAwMDYsImV4cCI6MjA5MzU0NjAwNn0.gzeSznxzye68BbwOFtzuLHm-fMpEIf-50YRQwA2JATA';

async function main() {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const passwords = [
    'Cesar123!',
    'Cesar1234!',
    'Password123!',
    '12345678',
    '123456',
    'cesarpuerto10',
    'GoMedical2026!',
    'Test1234!',
  ];

  for (const pw of passwords) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: 'cesarpuerto10@gmail.com',
      password: pw,
    });
    if (!error && data.session) {
      console.log(`✓ Password matched: "${pw}"`);
      return;
    }
  }
}

main().catch(console.error);
