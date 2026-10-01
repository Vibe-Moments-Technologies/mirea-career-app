// invite.js — Node-микросервис инвайтов (VDS + локально). Без фреймворков.
// Хранит SERVICE_ROLE_KEY только здесь, браузер его никогда не видит.
// Статус: СТАБ — health работает, POST /invite вернёт 501 до следующего шага.
// Запуск локально: $env:SERVICE_ROLE_KEY="..."; node server/invite.js
// Проверка: curl http://localhost:3001/health
const http = require('node:http');

const PORT = Number(process.env.INVITE_PORT || 3001);

const server = http.createServer((req, res) => {
  if (req.url === '/health' && req.method === 'GET') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true }));
    return;
  }
  if (req.url === '/invite' && req.method === 'POST') {
    // ponytail: полная логика (проверка caller org_admin + Admin API) — следующим шагом.
    res.writeHead(501, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'not_implemented_yet' }));
    return;
  }
  res.writeHead(404);
  res.end();
});

server.listen(PORT, () => console.log(`invite stub on http://localhost:${PORT}`));
