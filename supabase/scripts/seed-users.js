// seed-users.js — создаёт демо-пользователей через GoTrue Admin API
// и назначает роли/организации через SQL (psql по SSH-доступу недоступен — используем REST + миграцию).
// Запуск: node supabase/scripts/seed-users.js
const { loadEnv } = require('./db');
const env = loadEnv();
const ADMIN = { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
const PASSWORD = 'Demo1234!';

const ORG = {
  career:   '11111111-1111-1111-1111-111111111101',
  it:       '11111111-1111-1111-1111-111111111102',
  studclub: '11111111-1111-1111-1111-111111111103',
  yandex:   '11111111-1111-1111-1111-111111111104',
  sber:     '11111111-1111-1111-1111-111111111105',
  vk:       '11111111-1111-1111-1111-111111111106',
};

const USERS = [
  { email: 'superadmin@demo.mirea', name: 'Супер-админ',        role: 'super_admin',          org: null },
  { email: 'chiefmod@demo.mirea',   name: 'Главный модератор',  role: 'main_moderator',       org: null },
  { email: 'assist@demo.mirea',     name: 'Ассистент модератора', role: 'assistant_moderator', org: null },
  { email: 'career@demo.mirea',     name: 'Карьерный центр',    role: 'org_admin',            org: ORG.career },
  { email: 'partner@demo.mirea',    name: 'Яндекс HR',          role: 'org_admin',            org: ORG.yandex },
  { email: 'partner_emp@demo.mirea', name: 'Сотрудник Яндекс',  role: 'org_member',           org: ORG.yandex },
];

(async () => {
  const list = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users?per_page=200`, { headers: ADMIN });
  const { users: existing } = await list.json();
  const updates = [];
  for (const u of USERS) {
    let user = (existing || []).find(x => x.email === u.email);
    if (user) {
      console.log(`= ${u.email} уже существует (${user.id})`);
    } else {
      const r = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users`, {
        method: 'POST', headers: ADMIN,
        body: JSON.stringify({ email: u.email, password: PASSWORD, email_confirm: true, user_metadata: { full_name: u.name } }),
      });
      if (!r.ok) { console.error(`FAIL ${u.email}:`, r.status, await r.text()); process.exitCode = 1; continue; }
      user = await r.json();
      console.log(`+ создан ${u.email} (${user.id})`);
    }
    updates.push({ id: user.id, role: u.role, org: u.org });
  }
  // роли: из браузера/REST обновить profiles нельзя (service_role не ходит в pg, а anon не имеет прав) —
  // генерируем SQL для применения через psql (SSH-туннель / SQL Editor).
  const sql = updates.map(x =>
    `update public.profiles set role='${x.role}', organization_id=${x.org ? `'${x.org}'` : 'null'} where id='${x.id}';`
  ).join('\n');
  require('fs').writeFileSync(__dirname + '/../.roles-apply.sql', sql);
  console.log('\nSQL для назначения ролей записан в supabase/.roles-apply.sql:\n' + sql);
})();
