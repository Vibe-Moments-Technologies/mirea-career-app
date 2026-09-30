// Загрузка картинок в Supabase Storage (media bucket).
// Используется, потому что PowerShell Invoke-RestMethod рвёт TLS на больших телах.
//
// Запуск: node upload-images.js
// Читает .env (SUPABASE_URL, SERVICE_ROLE_KEY) и папку с картинками.

const fs = require('fs');
const path = require('path');

const env = {};
for (const line of fs.readFileSync(path.join(__dirname, '..', '..', '.env'), 'utf8').split('\n')) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2].trim();
}
const URL = env.SUPABASE_URL;
const KEY = env.SERVICE_ROLE_KEY;

const dir = 'C:\\Users\\sm171\\Pictures\\buytokens-gen';
// имена по времени создания: newest first
const files = fs.readdirSync(dir)
  .filter((f) => f.endsWith('.png'))
  .map((f) => ({ f, t: fs.statSync(path.join(dir, f)).mtimeMs }))
  .sort((a, b) => b.t - a.t)
  .slice(0, 6)
  .map((x) => x.f);

const names = ['career-fair', 'internship', 'hackathon', 'open-day', 'chemistry-lab', 'lecture'];

(async () => {
  for (let i = 0; i < files.length; i++) {
    const target = `images/${names[i]}.png`;
    const body = fs.readFileSync(path.join(dir, files[i]));
    try {
      const res = await fetch(`${URL}/storage/v1/object/media/${target}`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${KEY}`,
          apikey: KEY,
          'Content-Type': 'image/png',
          'x-upsert': 'true',
        },
        body,
      });
      const text = await res.text();
      if (res.ok) {
        console.log(`OK ${names[i]} -> ${URL}/storage/v1/object/public/media/${target}`);
      } else {
        console.log(`FAIL ${names[i]} [${res.status}]: ${text.slice(0, 200)}`);
      }
    } catch (e) {
      console.log(`FAIL ${names[i]}: ${e.message}`);
    }
  }
})();