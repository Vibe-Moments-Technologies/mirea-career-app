import { supa } from './supabase';
import { currentProfile, signIn, signOut, DEMO_ACCOUNTS, DEMO_PASSWORD, type Profile } from './auth';
import './styles.css';

const app = document.getElementById('app')!;

const ROLE_LABEL: Record<string, string> = {
  super_admin: 'Супер-админ',
  main_moderator: 'Главный модератор',
  assistant_moderator: 'Ассистент',
  org_admin: 'Админ организации',
  org_member: 'Сотрудник',
};

// ponytail: плоский hash-роутер вместо либы; когда маршрутов станет >10 — взять роутер.
const ROUTES: { hash: string; title: string; roles: string[] }[] = [
  { hash: '#/my-posts', title: 'Мои посты', roles: ['org_admin', 'org_member', 'super_admin', 'main_moderator'] },
  { hash: '#/moderation', title: 'Модерация', roles: ['assistant_moderator', 'main_moderator', 'super_admin'] },
  { hash: '#/publish', title: 'К публикации', roles: ['main_moderator', 'super_admin'] },
  { hash: '#/orgs', title: 'Организации', roles: ['super_admin'] },
  { hash: '#/users', title: 'Пользователи', roles: ['super_admin'] },
  { hash: '#/stats', title: 'Статистика', roles: ['super_admin', 'main_moderator', 'assistant_moderator', 'org_admin', 'org_member'] },
];

function menuFor(p: Profile) {
  return ROUTES.filter((r) => r.roles.includes(p.role));
}

async function render() {
  const hash = location.hash || '#/my-posts';
  let profile: Profile | null = null;
  try {
    profile = await currentProfile();
  } catch (e) {
    app.innerHTML = `<div class="wrap"><div class="card">Ошибка профиля: ${(e as Error).message}</div></div>`;
    return;
  }
  if (!profile) return renderLogin();

  const menu = menuFor(profile);
  const route = ROUTES.find((r) => r.hash === hash && r.roles.includes(profile!.role)) ?? menu[menu.length - 1] ?? ROUTES[ROUTES.length - 1];

  app.innerHTML = `
    <header class="topbar glass">
      <div class="logo">Карьера РТУ МИРЭА · консоль</div>
      <div class="user">${profile.full_name} <span class="badge">${ROLE_LABEL[profile.role]}</span>
        <button id="out" class="btn ghost">Выйти</button></div>
    </header>
    <div class="layout">
      <nav class="side glass">
        ${menu.map((m) => `<a href="${m.hash}" class="${m.hash === route.hash ? 'active' : ''}">${m.title}</a>`).join('')}
      </nav>
      <main class="content"><div class="card">
        <h2>${route.title}</h2>
        <p class="muted">Скелет: экран подключим следующим шагом. Роль: <b>${ROLE_LABEL[profile.role]}</b>.</p>
      </div></main>
    </div>`;

  document.getElementById('out')!.onclick = async () => {
    await signOut();
    location.hash = '#/my-posts';
    render();
  };
}

function renderLogin(err = '') {
  app.innerHTML = `
    <div class="login-wrap"><div class="card login glass">
      <h2>Вход в консоль</h2>
      ${err ? `<div class="error">${err}</div>` : ''}
      <form id="f"><input id="email" type="email" placeholder="email" required />
      <input id="pass" type="password" placeholder="пароль" required />
      <button class="btn primary" type="submit">Войти</button></form>
      <div class="demo"><div class="muted">Демо-вход:</div>
        ${DEMO_ACCOUNTS.map((a) => `<button class="btn chip" data-email="${a.email}">${a.label}</button>`).join('')}
      </div>
    </div></div>`;

  (document.getElementById('f') as HTMLFormElement).onsubmit = async (e) => {
    e.preventDefault();
    const email = (document.getElementById('email') as HTMLInputElement).value;
    const password = (document.getElementById('pass') as HTMLInputElement).value;
    try {
      await signIn(email, password);
      render();
    } catch (er) {
      renderLogin((er as Error).message);
    }
  };
  document.querySelectorAll<HTMLButtonElement>('[data-email]').forEach((b) => {
    b.onclick = async () => {
      try {
        await signIn(b.dataset.email!, DEMO_PASSWORD);
        render();
      } catch (er) {
        renderLogin((er as Error).message);
      }
    };
  });
}

supa().auth.onAuthStateChange(() => render());
window.addEventListener('hashchange', render);
render();
