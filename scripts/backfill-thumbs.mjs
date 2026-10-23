// One-time: give every existing profile photo its 480 px copy (<id>_t.jpg), the way new
// uploads already get one. Safe to run again: photos that have a copy are skipped.
//
//   cd scripts && npm i @supabase/supabase-js@2 sharp@0.33
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=... node backfill-thumbs.mjs
//
// The service role key is in Supabase → Project Settings → API. Keep it on your computer;
// never put it in the app.
import { createClient } from '@supabase/supabase-js';
import sharp from 'sharp';

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }
const db = createClient(url, key, { auth: { persistSession: false } });
const bucket = db.storage.from('photos');

async function list(prefix) {
  const out = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await bucket.list(prefix, { limit: 1000, offset });
    if (error) throw error;
    out.push(...data);
    if (data.length < 1000) return out;
  }
}

let made = 0, skipped = 0, failed = 0;
for (const folder of await list('')) {
  if (folder.id) continue; // files at the root aren't profile photos
  const files = await list(folder.name);
  const names = new Set(files.map(f => f.name));
  for (const f of files) {
    if (!f.name.endsWith('.jpg') || f.name.endsWith('_t.jpg')) continue;
    const thumb = f.name.replace(/\.jpg$/, '_t.jpg');
    if (names.has(thumb)) { skipped++; continue; }
    try {
      const { data, error } = await bucket.download(`${folder.name}/${f.name}`);
      if (error) throw error;
      const small = await sharp(Buffer.from(await data.arrayBuffer()))
        .rotate().resize(480, 480, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 82 }).toBuffer();
      const up = await bucket.upload(`${folder.name}/${thumb}`, small,
        { contentType: 'image/jpeg', cacheControl: '31536000', upsert: false });
      if (up.error) throw up.error;
      made++;
    } catch (e) { failed++; console.error(`${folder.name}/${f.name}:`, e.message ?? e); }
  }
}
console.log(`Done. Made ${made}, already had ${skipped}, failed ${failed}.`);
