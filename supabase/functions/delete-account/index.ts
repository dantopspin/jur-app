// Deletes the signed-in person's account AND their files.
// Database rows go with the auth user (foreign keys cascade), but Storage files
// don't: profile photos (public bucket), verification selfies and the photos and
// voice notes in their chats would stay behind. This function removes those first,
// through the Storage API (SQL deletes on storage.objects would leave the files),
// then deletes the user. If a file step fails, nothing is deleted and the app can retry.
//
// Deploy:  supabase functions deploy delete-account
// (JWT verification stays on: only the signed-in person can delete themselves.)

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

/** Every object path directly inside `folder/` of a bucket (uploads are flat). */
async function listFolder(bucket: string, folder: string): Promise<string[]> {
  const out: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await admin.storage.from(bucket).list(folder, { limit: 1000, offset });
    if (error) throw new Error(`list ${bucket}/${folder}: ${error.message}`);
    out.push(...(data ?? []).filter((o) => o.id).map((o) => `${folder}/${o.name}`));
    if (!data || data.length < 1000) return out;
  }
}

async function removeAll(bucket: string, paths: string[]) {
  for (let i = 0; i < paths.length; i += 500) {
    const { error } = await admin.storage.from(bucket).remove(paths.slice(i, i + 500));
    if (error) throw new Error(`remove ${bucket}: ${error.message}`);
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who, error: authError } = await admin.auth.getUser(token);
  if (authError || !who.user) return new Response("unauthorized", { status: 401 });
  const uid = who.user.id;

  try {
    // Chats this person was in (both sides' media goes: the chat itself is deleted).
    const { data: matches, error: mErr } = await admin.from("matches").select("id").or(`user_a.eq.${uid},user_b.eq.${uid}`);
    if (mErr) throw new Error(`matches: ${mErr.message}`);

    await removeAll("photos", await listFolder("photos", uid));
    await removeAll("verification", await listFolder("verification", uid));
    for (const m of matches ?? []) await removeAll("chat-media", await listFolder("chat-media", m.id));

    const { error: dErr } = await admin.auth.admin.deleteUser(uid);
    if (dErr) throw new Error(`delete user: ${dErr.message}`);
  } catch (e) {
    console.error("delete-account failed", uid, e);
    return new Response("delete failed", { status: 500 });
  }
  console.log("delete-account done", uid);
  return Response.json({ ok: true });
});
