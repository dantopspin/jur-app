// Sends native iOS notifications through Apple's HTTP/2 API (token-based auth).
// Called only by queue_push in Postgres (pg_net) with the shared PUSH_SECRET.
//
// Secrets: PUSH_SECRET, APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (the .p8 file's
// contents), APNS_TOPIC (kz.jur.app), APNS_ENV ("development" or "production").
//
// Builds from Xcode get sandbox tokens; TestFlight and App Store builds get production
// tokens, and both can be in the table at once. APNS_ENV only picks which server is
// tried first: a token the first server calls BadDeviceToken is retried on the other,
// and dropped only if neither accepts it.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const env = (k: string) => Deno.env.get(k) ?? '';
const PRODUCTION = 'https://api.push.apple.com';
const SANDBOX = 'https://api.sandbox.push.apple.com';
const hosts = env('APNS_ENV') === 'development' ? [SANDBOX, PRODUCTION] : [PRODUCTION, SANDBOX];

let cached: { jwt: string; at: number } | null = null;

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function providerToken(): Promise<string> {
  // Apple accepts a token for up to an hour; refresh every 50 minutes.
  if (cached && Date.now() - cached.at < 50 * 60_000) return cached.jwt;
  const pem = env('APNS_PRIVATE_KEY').replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: env('APNS_KEY_ID') }));
  const claims = b64url(JSON.stringify({ iss: env('APNS_TEAM_ID'), iat: Math.floor(Date.now() / 1000) }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  cached = { jwt, at: Date.now() };
  return jwt;
}

Deno.serve(async (req) => {
  if (req.headers.get('Authorization') !== `Bearer ${env('PUSH_SECRET')}` || !env('PUSH_SECRET')) {
    return new Response('forbidden', { status: 403 });
  }
  const { tokens, title, body, sound, thread, data } = await req.json();
  const payload = JSON.stringify({
    aps: { alert: { title, body }, sound: sound ?? 'default', 'thread-id': thread ?? 'jur' },
    ...(data ?? {}),
  });
  const jwt = await providerToken();
  const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'));
  const send = (host: string, token: string) => fetch(`${host}/3/device/${token}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'apns-topic': env('APNS_TOPIC') || 'kz.jur.app',
      'apns-push-type': 'alert',
      'apns-priority': '10',
    },
    body: payload,
  });
  const results = await Promise.all((tokens as string[]).map(async (token) => {
    let status = 0;
    let reason: string | undefined;
    for (const host of hosts) {
      const r = await send(host, token);
      status = r.status;
      reason = r.status === 200 ? undefined : (await r.json().catch(() => ({}))).reason;
      // A token from the other environment: try the other server before giving up on it.
      if (r.status === 400 && reason === 'BadDeviceToken') continue;
      break;
    }
    // 410: the app was removed. BadDeviceToken on both servers: the token is junk.
    if (status === 410 || (status === 400 && reason === 'BadDeviceToken')) {
      await admin.rpc('drop_push_token', { p_token: token });
    }
    return { token: token.slice(0, 8), status, reason };
  }));
  return Response.json({ sent: results });
});
