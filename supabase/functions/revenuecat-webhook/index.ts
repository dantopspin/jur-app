// RevenueCat → Supabase webhook.
// RevenueCat calls this on every purchase, renewal, expiry and refund.
// All crediting logic lives in SQL (public.apply_revenuecat_event) so it is
// tested and idempotent; this function only authenticates the caller.
//
// Deploy:  supabase functions deploy revenuecat-webhook --no-verify-jwt
// Secrets: supabase secrets set REVENUECAT_WEBHOOK_SECRET=<long random string>
// In RevenueCat → Integrations → Webhooks set the URL to
//   https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook
// and the Authorization header to:  Bearer <the same secret>

import { createClient } from "npm:@supabase/supabase-js@2";

const SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  if (!SECRET) return new Response("webhook secret not configured", { status: 500 });

  const auth = req.headers.get("authorization") ?? "";
  if (!timingSafeEqual(auth, `Bearer ${SECRET}`)) {
    return new Response("unauthorized", { status: 401 });
  }

  let body: { event?: Record<string, unknown> };
  try {
    body = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  const event = body.event;
  if (!event || typeof event !== "object") return new Response("no event", { status: 400 });

  const { data, error } = await supabase.rpc("apply_revenuecat_event", { p_event: event });
  if (error) {
    console.error("apply_revenuecat_event failed", error);
    // 500 makes RevenueCat retry later.
    return new Response("db error", { status: 500 });
  }
  console.log(`revenuecat ${event.type} ${event.product_id ?? ""} → ${data}`);
  // The account doesn't exist yet (bought between sign-in and profile creation):
  // a non-2xx answer makes RevenueCat send the same event again later.
  if (typeof data === "string" && data.startsWith("retry:")) {
    return new Response(data, { status: 503 });
  }
  return Response.json({ result: data });
});
