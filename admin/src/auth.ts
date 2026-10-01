import { supa } from './supabase';

export type Role = 'super_admin' | 'main_moderator' | 'assistant_moderator' | 'org_admin' | 'org_member';

export interface Profile {
  id: string;
  role: Role;
  organization_id: string | null;
  full_name: string;
}

export const DEMO_ACCOUNTS: { label: string; email: string }[] = [
  { label: 'Супер-админ', email: 'superadmin@demo.mirea' },
  { label: 'Главный', email: 'chiefmod@demo.mirea' },
  { label: 'Ассистент', email: 'assist@demo.mirea' },
  { label: 'Карьерный центр', email: 'career@demo.mirea' },
  { label: 'Яндекс (админ)', email: 'partner@demo.mirea' },
  { label: 'Яндекс (сотрудник)', email: 'partner_emp@demo.mirea' },
];

export const DEMO_PASSWORD = 'Demo1234!';

export async function signIn(email: string, password: string) {
  const { error } = await supa().auth.signInWithPassword({ email, password });
  if (error) throw error;
}

export async function signOut() {
  await supa().auth.signOut();
}

export async function currentProfile(): Promise<Profile | null> {
  const { data } = await supa().auth.getSession();
  const uid = data.session?.user.id;
  if (!uid) return null;
  const { data: p, error } = await supa().from('profiles').select('*').eq('id', uid).single();
  if (error) throw error;
  return p as Profile;
}
