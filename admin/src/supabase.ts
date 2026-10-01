import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let client: SupabaseClient | null = null;

export function supa(): SupabaseClient {
  if (!client) {
    const url = import.meta.env.VITE_SUPABASE_URL as string;
    const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string;
    if (!url || !anon) throw new Error('Нет VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY (см. admin/.env)');
    client = createClient(url, anon);
  }
  return client;
}
