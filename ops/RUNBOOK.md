# JÜR operations runbook

What to set up once, how to ship a change, and what to do when something breaks.
The server is one Supabase project; the rules live in SQL (`supabase/migrations`) and
are tested on every pull request (`.github/workflows/backend-tests.yml`).

## One-time setup (account settings, not code)

| # | Where | What | Why |
|---|---|---|---|
| 1 | Supabase → Billing | Be on **Pro** before launch | Free has no backups and pauses after a week idle |
| 2 | Supabase → Billing → Spend cap | Keep **on** until revenue covers overage; then turn off *and* set usage alerts at 50/80/100 % of budget | A cap that's on stops the app when you hit it |
| 3 | Supabase → Database → Backups | Turn on **Point-in-time recovery** once there's real data (≈$100/mo for 7 days) | Daily backups lose up to 24 h of matches and payments |
| 4 | GitHub → Settings → Secrets → Actions | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (ops health), `SUPABASE_DB_URL` (session pooler), `BACKUP_AGE_RECIPIENT` | Turns on the daily health check and the nightly encrypted backup |
| 5 | Supabase → Storage → Settings → S3 | Create S3 access keys; copy Storage weekly (below) | Photos and chat media are **not** in database backups |
| 6 | Second Supabase project `jur-staging` | Same migrations, test data, TestFlight internal builds point at it | Today migrations go straight to production |
| 7 | App Store Connect → each release | **Phased release** on | Apple has no rollback; phased release lets you pause at 1 % |
| 8 | RevenueCat → Integrations → Webhooks | Confirm the URL and `Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>`; send a test event | Purchases credit only through the webhook |
| 9 | Apple Developer → Keys | Note the APNs key id and where the `.p8` is stored (password manager) | Losing it means no pushes until a new key is deployed |

After merging, open **Actions → Ops health → Run workflow** once so GitHub knows to email
*you* when the daily check fails.

## Shipping a server change

1. Branch, write the migration **and** its rollback in `supabase/rollback/<name>_down.sql`, add tests.
2. Open a pull request; CI runs every migration, every test, every rollback, and type-checks the functions.
3. Apply to staging: `supabase link --project-ref <staging> && supabase db push`, try it in a TestFlight build.
4. Production, at a quiet hour (Almaty night): `supabase link --project-ref <prod> && supabase db push`.
5. Then any changed Edge Functions: `supabase functions deploy <name>` (`--no-verify-jwt` for `apns` and `revenuecat-webhook`).
6. Watch for 30 minutes: `select ops_health();` and `select * from ops_events order by at desc limit 50;`

Order matters: database first, functions second, app last. Each step must work with the
previous version of the next one (old app + new database must still work).

## Rolling back

| What broke | Do this |
|---|---|
| A migration | Run its `supabase/rollback/<name>_down.sql` in the SQL editor, then `delete from supabase_migrations.schema_migrations where version = '<name>';` Fix forward with a new migration. Newest first if undoing several. |
| Data got damaged | Point-in-time restore to just before (Supabase → Backups), or restore last night's encrypted dump into a scratch project and copy the rows back. |
| An Edge Function | `git checkout <last good commit> -- supabase/functions/<name> && supabase functions deploy <name>` |
| An app release | Pause the phased release in App Store Connect; ship a fix with expedited review. A server-side fix is often faster. |

## Backups

- **Supabase**: daily (Pro, 7 days) plus point-in-time recovery once enabled.
- **Nightly copy outside Supabase**: `.github/workflows/db-backup.yml`, encrypted with your `age` key, 30 days.
- **Storage** (weekly, from your Mac, needs `rclone`):
  ```
  rclone config create jur s3 provider Other endpoint https://<ref>.supabase.co/storage/v1/s3 \
    access_key_id <key> secret_access_key <secret> region <project region>
  rclone sync jur:photos ~/Backups/jur/photos && rclone sync jur:verification ~/Backups/jur/verification \
    && rclone sync jur:chat-media ~/Backups/jur/chat-media
  ```
  Keep `~/Backups/jur` on an encrypted disk: it's every member's photos.
- **Restore drill** every few months: restore the newest dump into a scratch project, open the app against it, check a profile, a chat and a Pro member. A backup you haven't restored is a guess.

## When something is wrong

| Symptom | Look at |
|---|---|
| Daily "Ops health" email | `select ops_health();` → `reasons` |
| Crashes | `select at, message, detail->>'build' from ops_events where source = 'app' order by at desc;` |
| Pushes not arriving | `select delivery_status, delivery_failed, count(*) from push_outbox where created_at > now() - interval '1 day' group by 1, 2;` A 403 everywhere is usually an expired or wrong APNs key. |
| A purchase didn't give Pro | `select * from purchase_events where app_user_id = '<user id>' order by created_at desc;` A `retry:` row older than an hour means the profile never got created. |
| Scheduled jobs | `select jobname, status, start_time, return_message from cron.job_run_details join cron.job using (jobid) order by start_time desc limit 20;` |
| Everything slow | Supabase → Reports → Query performance; Discover is the heaviest call (≈0.1 s at 1 000 members, ≈1.2 s at 20 000 on a laptop). |
| "Too many in a row" complaints | Limits are in `20261026000023_scale_and_limits.sql` (`rate_guard(...)` arguments); change with a migration. |

## Capacity notes (load-tested 26 Oct 2026, fake members, 70 % in one city)

| Members | Discover | Filter count |
|---|---|---|
| 1 000 | 0.09 s | 0.01 s |
| 5 000 | 0.34 s | 0.04 s |
| 20 000 | 1.2 s | 0.22 s |

Discover's cost follows the number of candidates in one city. Before a city passes
≈20 000 members: store each member's "likes waiting" count (updated on swipe) instead of
counting it per load, and move chat from Postgres Changes to Realtime Broadcast.
