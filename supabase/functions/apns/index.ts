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
//
// Apple being busy (429) or down (5xx), or the network failing, is retried twice with a
// short wait. The reply lists every token's result; Postgres reads it back
// (record_push_delivery) and counts failures, so a broken push setup shows up in ops_health.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const env = (k: string) => Deno.env.get(k) ?? '';
const PRODUCTION = 'https://api.push.apple.com';
const SANDBOX = 'https://api.sandbox.push.apple.com';
const hosts = env('APNS_ENV') === 'development' ? [SANDBOX, PRODUCTION] : [PRODUCTION, SANDBOX];
const RETRY_WAIT_MS = [300, 1200];

let cached: { jwt: string; at: number } | null = null;

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

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
  const secret = env('PUSH_SECRET');
  if (!secret || !timingSafeEqual(req.headers.get('Authorization') ?? '', `Bearer ${secret}`)) {
    return new Response('forbidden', { status: 403 });
  }
  let input: { tokens?: unknown; title?: string; body?: string; sound?: string; thread?: string; data?: Record<string, unknown> };
  try {
    input = await req.json();
  } catch {
    return new Response('bad json', { status: 400 });
  }
  const tokens = Array.isArray(input.tokens) ? input.tokens.filter((t): t is string => typeof t === 'string') : [];
  if (tokens.length === 0) return Response.json({ sent: [] });

  const payload = JSON.stringify({
    aps: { alert: { title: input.title, body: input.body }, sound: input.sound ?? 'default', 'thread-id': input.thread ?? 'jur' },
    ...(input.data ?? {}),
  });
  let jwt: string;
  try {
    jwt = await providerToken();
  } catch (e) {
    console.error('apns: provider token failed (check APNS_PRIVATE_KEY / KEY_ID / TEAM_ID)', e);
    return new Response('provider token failed', { status: 500 });
  }
  const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'));

  /** One attempt; network errors become status 0 so they're retried like a 5xx. */
  const send = async (host: string, token: string): Promise<{ status: number; reason?: string }> => {
    try {
      const r = await fetch(`${host}/3/device/${token}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${jwt}`,
          'apns-topic': env('APNS_TOPIC') || 'kz.jur.app',
          'apns-push-type': 'alert',
          'apns-priority': '10',
        },
        body: payload,
      });
      const reason = r.status === 200 ? undefined : (await r.json().catch(() => ({}))).reason;
      return { status: r.status, reason };
    } catch (e) {
      return { status: 0, reason: e instanceof Error ? e.message : 'network' };
    }
  };

  /** Busy, down or unreachable: worth trying again in a moment. */
  const transient = (s: number) => s === 0 || s === 429 || s >= 500;

  const results = await Promise.all(tokens.map(async (token) => {
    let res = { status: 0 } as { status: number; reason?: string };
    for (const host of hosts) {
      res = await send(host, token);
      for (let i = 0; i < RETRY_WAIT_MS.length && transient(res.status); i++) {
        await sleep(RETRY_WAIT_MS[i]);
        res = await send(host, token);
      }
      // A token from the other environment: try the other server before giving up on it.
      if (res.status === 400 && res.reason === 'BadDeviceToken') continue;
      break;
    }
    // 410: the app was removed. BadDeviceToken on both servers: the token is junk.
    if (res.status === 410 || (res.status === 400 && res.reason === 'BadDeviceToken')) {
      await admin.rpc('drop_push_token', { p_token: token });
    } else if (res.status !== 200) {
      console.error(`apns: ${token.slice(0, 8)}… ${res.status} ${res.reason ?? ''}`);
    }
    return { token: token.slice(0, 8), status: res.status, reason: res.reason };
  }));
  return Response.json({ sent: results });
});
