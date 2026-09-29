// Minimal env loader + pg client factory (no deps beyond pg).
const fs = require('fs');
const path = require('path');
const { Client } = require(path.join(__dirname, '..', '..', 'tools', 'node_modules', 'pg'));

function loadEnv() {
  const env = {};
  const file = path.join(__dirname, '..', '..', '.env');
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m) env[m[1]] = m[2];
  }
  return env;
}

async function pgClient() {
  const c = new Client({ connectionString: loadEnv().DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await c.connect();
  return c;
}

module.exports = { loadEnv, pgClient };
