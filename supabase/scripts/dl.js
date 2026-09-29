// dl.js — загрузка через undici fetch (PowerShell/BITS/Invoke-WebRequest в песочнице блокируются).
// Использование: node supabase/scripts/dl.js <url> <outfile>
const fs = require('fs');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');

(async () => {
  const [url, out] = process.argv.slice(2);
  if (!url || !out) { console.error('usage: node dl.js <url> <outfile>'); process.exit(2); }
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) { console.error('HTTP', res.status, url); process.exit(1); }
  const total = Number(res.headers.get('content-length') || 0);
  await pipeline(Readable.fromWeb(res.body), fs.createWriteStream(out));
  const size = fs.statSync(out).size;
  console.log(`downloaded ${out} ${(size / 1048576).toFixed(1)} MB` + (total ? ` of ${(total / 1048576).toFixed(1)} MB` : ''));
  if (total && size !== total) { console.error('SIZE MISMATCH'); process.exit(1); }
})().catch(e => { console.error('FAIL:', e.message); process.exit(1); });