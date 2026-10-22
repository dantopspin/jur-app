-- Server settings in a private table. Supabase no longer lets the project owner run
-- `alter database postgres set jur.… = …`, so the push settings live here instead:
--
--   insert into public.app_settings (key, value) values
--     ('jur.apns_function_url', 'https://<ref>.supabase.co/functions/v1/apns'),
--     ('jur.apns_secret', '<same value as the apns function's PUSH_SECRET>')
--   on conflict (key) do update set value = excluded.value;
--
-- Nobody can read the table through the API (RLS on, no policies, no grants); only
-- security-definer functions inside the database use it.
create table if not exists public.app_settings (
  key   text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from public, anon, authenticated;

-- A database-level setting still wins if one exists (older projects set them that way).
create or replace function public.app_setting(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(current_setting(p_key, true), ''),
                  (select value from app_settings where key = p_key))
$$;
revoke all on function public.app_setting(text) from public, anon, authenticated;

create or replace function public.queue_push(p_profile uuid, p_kind text, p_name text, p_data jsonb,
                                             p_extra text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_locale text;
  v_title text;
  v_body text;
  v_expo text[];
  v_apns text[];
  v_messages jsonb;
  v_headers jsonb := '{"Content-Type": "application/json", "Accept": "application/json"}';
  v_req bigint;
  v_access text := app_setting('qadam.expo_access_token');
  v_apns_url text := app_setting('jur.apns_function_url');
  v_apns_secret text := app_setting('jur.apns_secret');
  v_has_net boolean := exists (select 1 from pg_extension where extname = 'pg_net');
begin
  select locale into v_locale from profiles where id = p_profile and not banned;
  if not found then return; end if;
  select t.title, t.body into v_title, v_body from push_text(v_locale, p_kind, p_name, p_extra) t;
  select coalesce(array_agg(token) filter (where token like 'Expo%'), '{}'),
         coalesce(array_agg(token) filter (where token not like 'Expo%'), '{}')
    into v_expo, v_apns
    from push_tokens where profile_id = p_profile;

  -- Old prototype builds: Expo
  if cardinality(v_expo) > 0 and v_has_net then
    select jsonb_agg(jsonb_build_object(
             'to', tok, 'title', v_title, 'body', v_body, 'data', p_data,
             'sound', case when p_kind = 'match' then 'match.wav' else 'default' end,
             'channelId', case p_kind when 'match' then 'matches' when 'message' then 'chats' else 'activity' end,
             'priority', 'high'))
      into v_messages from unnest(v_expo) tok;
    if coalesce(v_access, '') <> '' then
      v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_access);
    end if;
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      into v_req using 'https://exp.host/--/api/v2/push/send', v_messages, v_headers;
  end if;

  -- The native app: APNs through the Edge Function
  if cardinality(v_apns) > 0 and v_has_net and coalesce(v_apns_url, '') <> '' then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      into v_req using v_apns_url,
        jsonb_build_object(
          'tokens', to_jsonb(v_apns), 'title', v_title, 'body', v_body,
          'sound', case when p_kind = 'match' then 'match.wav' else 'default' end,
          'thread', p_kind, 'data', coalesce(p_data, '{}')),
        jsonb_build_object('Content-Type', 'application/json',
                           'Authorization', 'Bearer ' || coalesce(v_apns_secret, ''));
  end if;

  insert into push_outbox (profile_id, kind, title, body, data, tokens, request_id)
  values (p_profile, p_kind, v_title, v_body, coalesce(p_data, '{}'),
          cardinality(v_expo) + cardinality(v_apns), v_req);
end $$;
revoke execute on function public.queue_push(uuid, text, text, jsonb, text) from public, anon, authenticated;
