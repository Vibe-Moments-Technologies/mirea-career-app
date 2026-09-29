// smoke-test.js — проверка RLS/RPC через REST (этап 1, критерий готовности №1–2)
const { loadEnv } = require('./db');
const env = loadEnv();
const PASSWORD = 'Demo1234!';
let pass = 0, fail = 0;
function check(name, cond, extra = '') {
  if (cond) { pass++; console.log('  PASS', name); }
  else { fail++; console.log('  FAIL', name, extra); }
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function request(url, opts, tries = 5) {
  for (let i = 0; ; i++) {
    try {
      const r = await fetch(url, opts);
      const text = await r.text();          // читаем тело внутри retry: "terminated" случается здесь
      let json = null;
      try { json = JSON.parse(text); } catch {}
      return { status: r.status, json, text };
    } catch (e) {
      if (i >= tries - 1) throw e;
      await sleep(700 * (i + 1));
    }
  }
}

async function api(path, { method = 'GET', token = env.ANON_KEY, body } = {}) {
  return request(`${env.SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: env.ANON_KEY,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: method === 'POST' ? 'return=representation' : undefined,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

async function rpc(fn, args, token = env.ANON_KEY) {
  return request(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: env.ANON_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
}

async function login(email) {
  const { json } = await request(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  if (!json?.access_token) throw new Error(`login failed ${email}: ${JSON.stringify(json).slice(0, 200)}`);
  return json.access_token;
}

const PUBLISHED = '22222222-2222-2222-2222-222222222201';
const PENDING   = '22222222-2222-2222-2222-222222222209'; // pending_review (Яндекс)
const READY     = '22222222-2222-2222-2222-22222222220a'; // reviewed_ready (Сбер)
const DRAFT     = '22222222-2222-2222-2222-22222222220b'; // draft (Студклуб)

(async () => {
  console.log('== 1. Аноним: чтение ==');
  {
    const { status, json } = await api('posts?select=id,status');
    check('anon GET posts -> 200', status === 200, `status=${status}`);
    check('anon видит только published', Array.isArray(json) && json.length > 0 && json.every(p => p.status === 'published'),
      JSON.stringify(json?.map?.(p => p.status)));
  }

  console.log('== 2. Аноним: запись запрещена ==');
  {
    const r = await api(`posts?id=eq.${PUBLISHED}`, { method: 'PATCH', body: { status: 'draft' } });
    check('anon PATCH status отклоняется', r.status >= 400, `status=${r.status}`);
    const r2 = await api(`posts?id=eq.${PUBLISHED}`, { method: 'PATCH', body: { views_count: 99999 } });
    check('anon PATCH счётчика отклоняется', r2.status >= 400, `status=${r2.status}`);
    const r3 = await api('posts', { method: 'POST', body: { organization_id: '11111111-1111-1111-1111-111111111104', title: 'x', description: 'x', type: 'event' } });
    check('anon INSERT отклоняется', r3.status >= 400, `status=${r3.status}`);
  }

  console.log('== 3. RPC-счётчики (anon) ==');
  {
    const before = await api(`posts?id=eq.${PUBLISHED}&select=views_count,favorites_count`);
    const v0 = before.json[0].views_count, f0 = before.json[0].favorites_count;
    const rv = await rpc('increment_post_views', { target_post_id: PUBLISHED });
    check('increment_post_views -> 2xx', rv.status < 300, rv.text.slice(0, 100));
    const rf1 = await rpc('modify_post_favorites', { target_post_id: PUBLISHED, delta: 1 });
    const rf2 = await rpc('modify_post_favorites', { target_post_id: PUBLISHED, delta: -1 });
    const rfBad = await rpc('modify_post_favorites', { target_post_id: PUBLISHED, delta: 5 });
    check('favorites ±1 -> 2xx', rf1.status < 300 && rf2.status < 300, rf1.text + rf2.text);
    check('favorites delta=5 отклоняется', rfBad.status >= 400, rfBad.text.slice(0, 100));
    const after = await api(`posts?id=eq.${PUBLISHED}&select=views_count,favorites_count`);
    check('views +1, favorites без изменения', after.json[0].views_count === v0 + 1 && after.json[0].favorites_count === f0,
      `${v0}->${after.json[0].views_count}, ${f0}->${after.json[0].favorites_count}`);
    const rd = await rpc('increment_post_views', { target_post_id: DRAFT });
    const draftAfter = await api(`posts?id=eq.${DRAFT}&select=views_count`, { token: await login('chiefmod@demo.mirea') });
    check('RPC на черновик не накручивает', draftAfter.json[0].views_count === 0, JSON.stringify(draftAfter.json));
  }

  console.log('== 4. Автор (partner_emp, org_member Яндекс) ==');
  const empTok = await login('partner_emp@demo.mirea');
  let tempId = null;
  {
    const mine = await api('posts?select=id,status&organization_id=eq.11111111-1111-1111-1111-111111111104', { token: empTok });
    check('сотрудник видит посты своей org (вкл. неопубликованные)', mine.status === 200 && mine.json.some(p => p.id === PENDING), `status=${mine.status}`);
    const other = await api(`posts?id=eq.${DRAFT}&select=id`, { token: empTok });
    check('чужой черновик не виден', other.status === 200 && other.json.length === 0, JSON.stringify(other.json));
    const pub = await api(`posts?id=eq.${PENDING}`, { method: 'PATCH', token: empTok, body: { status: 'published' } });
    check('автор НЕ может опубликовать', pub.status >= 400, `status=${pub.status}`);
    const ins = await api('posts', { method: 'POST', token: empTok, body: {
      organization_id: '11111111-1111-1111-1111-111111111104', title: 'Тест сотрудника (smoke)', description: 'описание', type: 'event', status: 'draft' } });
    check('автор создаёт draft в своей org', ins.status < 300 && ins.json?.[0]?.id, `status=${ins.status}`);
    tempId = ins.json?.[0]?.id;
    if (tempId) {
      const send = await api(`posts?id=eq.${tempId}`, { method: 'PATCH', token: empTok, body: { status: 'pending_review' } });
      check('draft -> pending_review разрешён автору', send.status < 300, `status=${send.status}`);
      const wrongOrg = await api('posts', { method: 'POST', token: empTok, body: {
        organization_id: '11111111-1111-1111-1111-111111111105', title: 'x', description: 'x', type: 'event' } });
      check('пост в чужую org отклоняется', wrongOrg.status >= 400, `status=${wrongOrg.status}`);
    }
  }

  console.log('== 5. Ассистент модератора ==');
  const assistTok = await login('assist@demo.mirea');
  {
    const queue = await api('posts?select=id,status&status=eq.pending_review', { token: assistTok });
    check('ассистент видит очередь pending_review (temp-пост)', queue.status === 200 && queue.json.some(p => p.id === tempId), JSON.stringify(queue.json?.map?.(p => p.id)));
    const ok = await api(`posts?id=eq.${tempId}`, { method: 'PATCH', token: assistTok, body: { status: 'reviewed_ready' } });
    check('pending_review -> reviewed_ready разрешён', ok.status < 300, `status=${ok.status}`);
    const pub = await api(`posts?id=eq.${tempId}`, { method: 'PATCH', token: assistTok, body: { status: 'published' } });
    check('ассистент НЕ может опубликовать', pub.status >= 400, `status=${pub.status}`);
    const feat = await api(`posts?id=eq.${tempId}`, { method: 'PATCH', token: assistTok, body: { is_featured: true } });
    check('ассистент НЕ может менять featured', feat.status >= 400, `status=${feat.status}`);
    const note = await api('rejection_notes', { method: 'POST', token: assistTok, body: { post_id: tempId, note: 'smoke-заметка' } });
    check('ассистент пишет rejection_note', note.status < 300, `status=${note.status}`);
  }

  console.log('== 6. Главный модератор ==');
  const chiefTok = await login('chiefmod@demo.mirea');
  {
    const all = await api('posts?select=id,status', { token: chiefTok });
    check('главный видит все статусы', all.status === 200 && new Set(all.json.map(p => p.status)).size >= 3, JSON.stringify([...new Set(all.json?.map?.(p => p.status) || [])]));
    const pub = await api(`posts?id=eq.${tempId}`, { method: 'PATCH', token: chiefTok, body: { status: 'published', is_featured: true } });
    check('reviewed_ready -> published + featured разрешён', pub.status < 300, `status=${pub.status}`);
    const checkPub = await api(`posts?id=eq.${tempId}&select=status,published_at,is_featured`, { token: chiefTok });
    check('published_at выставлен триггером', !!checkPub.json[0]?.published_at && checkPub.json[0].is_featured === true, JSON.stringify(checkPub.json));
    const anonSees = await api(`posts?id=eq.${tempId}&select=id,status`, {});
    check('опубликованный пост сразу виден анониму', anonSees.status === 200 && anonSees.json.length === 1 && anonSees.json[0].status === 'published');
    // cleanup: удалить temp-пост и вернуть демо-состояние seed-поста 209 (pending_review)
    const del = await api(`posts?id=eq.${tempId}`, { method: 'DELETE', token: chiefTok });
    check('главный удаляет temp-пост', del.status < 300, `status=${del.status}`);
    await api(`posts?id=eq.${PENDING}`, { method: 'PATCH', token: chiefTok, body: { status: 'pending_review', is_featured: false } });
  }

  console.log('== 7. Супер-админ: назначения ==');
  const superTok = await login('superadmin@demo.mirea');
  {
    const upd = await api(`profiles?id=eq.f581d408-78ca-4c3c-9faa-9efedd35d967`, { method: 'PATCH', token: superTok, body: { full_name: 'Сотрудник Яндекс' } });
    check('супер-админ правит чужой профиль', upd.status < 300, `status=${upd.status}`);
    const nonSuper = await api(`profiles?id=eq.f581d408-78ca-4c3c-9faa-9efedd35d967`, { method: 'PATCH', token: empTok, body: { role: 'super_admin' } });
    check('не-супер НЕ может менять роль', nonSuper.status >= 400, `status=${nonSuper.status}`);
    const selfName = await api(`profiles?id=eq.f581d408-78ca-4c3c-9faa-9efedd35d967`, { method: 'PATCH', token: empTok, body: { full_name: 'Своё имя' } });
    check('пользователь правит своё имя', selfName.status < 300, `status=${selfName.status}`);
  }

  console.log(`\nИТОГ: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('SMOKE CRASH:', e); process.exit(1); });
