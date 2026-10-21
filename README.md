# JÜR (formerly Qadam) — server and the Expo prototype

> **The brand is now JÜR, and the app is being rebuilt natively in SwiftUI for iPhone in `ios/` (see `ios/README.md`).** The Supabase server in `supabase/` is shared and current. The Expo app below is the earlier prototype and is no longer developed.

## Expo prototype — V1.7

Multi-sport dating for Kazakhstan: running in summer and autumn, skiing, skating and padel in winter. Built with Expo (iOS + Android), Supabase (database, auth, chat, storage) and RevenueCat (App Store / Google Play payments). UI in Kazakh, Russian and English.

**Brand: one core, local kits.** The app is the same in every market: Qadam blue `#1F5FA0` and gold on a warm chalk ground, the mark (two strides curling into a heart — in Kazakhstan also read as ram horns), the Latin wordmark **Qadam**, Unbounded and Manrope. Kazakh culture (ornament, felt, dombra recording) lives in the Kazakhstan kit for posters, events and merch, not in the app UI. The brand book, tokens, user flow and components live in the "Qadam" design system; `src/lib/theme.ts` mirrors its tokens 1:1.

## Release fixes, nationwide launch, photo safety, fair exposure (V1.7)

**Release-blocking fixes** (from the pre-release review):
- A failed profile load shows "Couldn't load" with Retry instead of sending a member to onboarding.
- A chat that fails to load shows Retry; a chat that no longer exists says so, instead of loading forever.
- The intro offer shows the store's intro price and "then {price}/month", and leaves quietly if the store has no intro price. Sign-in, paywall and offer share one translated legal footer with working Terms and Privacy links.
- Deleting an account also deletes the person's profile photos, verification selfies and chat media (`delete-account` Edge Function), then the account.
- Club and double-date chats: long-press a message (or use the VoiceOver actions) to report or block its sender.

**Nationwide, app-only launch:**
- Every city is open from day one (migration `20261021000007`).
- `EXPO_PUBLIC_EVENTS=off` (the default) hides the Events tab, "host events", and every "see events" button, and switches copy that mentions events to app-only wording. Set it to `on` to bring events and clubs back; nothing was removed.

**Photo safety:**
- A chat photo can be sent only after both people have written (enforced by the server).
- Incoming chat photos stay blurred until tapped ("Blur photos in chats", on by default in Settings).
- On iOS 17+, Apple's on-device Sensitive Content Analysis checks each incoming photo; flagged photos are always blurred with a warning, others show normally. Apple runs this check only when the person has turned on Settings › Privacy & Security › Sensitive Content Warning. Nothing leaves the phone. Code: `modules/qadam-sensitive` (local Expo module).
- Android has no system equivalent; it relies on the blur setting until an on-device model is added (see Known gaps).

**Fair exposure:**
- People with 10+ likes waiting that they haven't answered (last 14 days) are shown after others in Discover and daily picks; 25+ later still. Answering, yes or no, brings them straight back. New members (first 3 days, under 5 likes) get a small head start. Boosts and "super liked you" still come first. No photo or attractiveness score is used. Tunable in `cfg()`.

Deploy for V1.7:
```bash
npx supabase db push
npx supabase functions deploy delete-account
```
In Xcode / App Store Connect, the Sensitive Content Analysis capability is added by `app.json` (`com.apple.developer.sensitivecontentanalysis.client`); rebuild the dev client.

## Visual polish (V1.6) — one system for every screen

Every screen is now built from the same tokens and parts (`src/lib/theme.ts`, `src/components/ui.tsx`):

- **Type:** `<T variant="title1 | title2 | title3 | headline | body | callout | footnote | caption | overline">` sets font, size, line height, colour and a Dynamic Type ceiling together. Every text element has a ceiling.
- **Spacing:** `sp` (2, 4, 8, 12, 16, 24, 32) and `layout` (16 pt screen margin, 44 pt rows, 29 pt icon tiles).
- **Radii:** `radius` sm 8 · md 12 · lg 20 (cards) · xl 28 (sheets only) · pill, with continuous corners on iOS. Nested shapes follow the concentric rule.
- **Borders:** almost none. Surfaces separate by fill; hairlines only inside grouped lists.
- **Icons:** `iconSize` inline 13 · row 17 · toolbar 22 · action 28 · hero 44.
- **Parts:** Button (50/44 pt; tinted secondary and destructive), Chip and Tag, ListSection + ListItem (inset grouped, coloured tiles, switches), Segmented (iOS dimensions), Empty / ErrorState / SkeletonList, `toast()` for confirmations, `showError()` for failed actions, HeaderTextButton / HeaderIconButton / SheetHeader.
- **Chat:** messages group by sender with a tail only on the last bubble; time dividers after 15 quiet minutes or a new day; per-message time in the long-press menu; "Read" under your last read message.
- **Unread** counts are blue everywhere; gold is reserved for Pro, super likes and the mark.

The full audit and plan are in the "Qadam — iOS visual polish audit" doc.

## Dating features (V1.5) — what Tinder, Bumble and Hinge do, fitted to sport

- **Profile prompts.** Up to three answers ("My perfect Sunday…", "Teach me…", "My go-to first date…"). People can like a specific answer with a note; the chat opens with that answer quoted. Edit in Me › Prompts.
- **Suggest a date.** In any chat, "+" › Suggest a date: a sport (or coffee), a time and a place, or one of the next five events. The other person answers on the card; accepting an event plan signs them up for it.
- **Undo the last pass** (Pro). Only the very last swipe, and only a pass.
- **Today's picks.** Five people a day chosen for the sports, events and clubs you share, plus verification and recent activity. The same five all day; a push goes out at 19:00 Almaty (14:00 UTC, pg_cron).
- **Travel mode** (Pro). Settings › Travel mode: appear in another city's Discover for 1–14 days.
- **Hide from contacts.** Settings › Hide from contacts hashes the phone numbers and emails in your address book on the phone and uploads only the hashes; people who match are hidden both ways.
- **Chat:** reply to a message, photos, voice notes (up to 2 minutes), quick reactions, copy. Media lives in a private `chat-media` bucket readable only by the two people in the match, through signed URLs.
- **Training partners** (Bumble BFF). Each profile is Dating, Training partner or Both. Training-partner matches are labelled, use different wording and never show in Dating. "Both" gets a switch at the top of Discover.
- **Double date.** Me › Double date: team up with a friend by member number, browse other pairs in your city, and when both pairs like each other a four-person chat opens. Built for doubles padel or a ski day.

New packages: expo-audio (recording), expo-contacts, expo-crypto, expo-file-system, expo-clipboard. Rebuild the dev client after installing.

**Privacy note on contact hashes.** Hashes are salted with a fixed app prefix, which hides raw numbers in transit and at rest, but phone numbers have few enough possibilities that a hash could be reversed by someone with database access. Treat `identity_hashes` as personal data: keep it out of exports and analytics, and say so in the privacy policy.

## Growth loops (V1.4) — what works for Ritmo, adapted

- **Clubs** for every sport (Ritmo's Run Club): local organizers, membership, a club chat, club events (joining one joins the club; members get a push for each new event). People apply in the app; you approve in SQL.
- **Story cards** (9:16) for Instagram/WhatsApp: "I'm going", "I joined the circle №0042", "Join my club" — each with the person's invite code.
- **Gold / blue wristbands**: chosen when joining an event (gold = open to meet, blue = here for the sport), switchable, shown on the attendee list.
- **City launch** (now off: every city opens on day one, V1.7): cities can show a public progress bar until they reach their launch number; invites move it; everyone gets a push when their city opens. Events and clubs work meanwhile.
- **Pricing**: a one-time 50% first-month offer when someone closes the paywall (`intro` offering, product `qadam_pro_monthly_intro`); packs of any size (`qadam_boost_<n>`, `qadam_super_<n>`) so you can add decoy sizes like Ritmo's.

## Native iOS feel and Kazakh moments (V1.3)

- **Native structure:** system tab bar (Liquid Glass on iOS 26) with an unread badge, large collapsing titles, SF Symbols, the system action sheet, long-press previews with context menus on chats and events, native page and form sheets, the native date picker for hosts.
- **Dark mode and Dynamic Type:** a full Night palette that follows the phone, and text that scales with the phone's text size.
- **Haptics:** tick on chips and choices, a bump when a swipe crosses the like or pass line, and dombra-timed patterns for match, super like and check-in.
- **Signature moments:**
  - the shanyrak ring in the match moment;
  - "You've joined the circle" on check-in, and a Regular mark after five events;
  - a felt back on every profile card (tap the member number to flip it);
  - an animated ornament as the onboarding progress and the loading state.
- **Seasons and dastarkhan:** a greeting by time of day, seasonal lines for winter, Nauryz and New Year, and snow on the horizon in winter. Events have an "after" plan (tea, coffee), and new chats suggest "Tea after a run?".
- **Outside the app:** a Live Activity for events you joined, a Home Screen widget, and four app icons (Classic, Night, Felt, Nauryz).

## What's in V1

| Area | What works |
| --- | --- |
| Sign-in | Welcome screen with Sign in with Apple (iPhone), Google, or an email code that submits itself; password sign-in for the App Review demo account |
| Onboarding | One question per screen, auto-advance on single choices, name prefilled from Apple/Google, 18+ check with "You're 27 — right?" confirmation, city, seasonal sports with levels, 1–6 photos, skippable "about you" with the invite code behind a link, notification ask (explained first, asked once) |
| Profile | Race-bib card with a member number (№0001…), sports, races and personal bests, events attended, verified badge |
| Discover | Same city, mutual preferences and age ranges; boosted and super-liked-you first, then shared in-season sports; swipe or tap; **like with a note** (max 140 characters, from the chat button or by tapping their next challenge) |
| Matches & chat | Mutual like creates a match and the notes become the first messages; real-time chat, unread counts, read receipts, new-match row; **openers** in empty chats; **"You're both going"** banner when both joined an event |
| Push notifications | Match, new message (max one per chat per minute), someone liked you (anonymous, max one per 6 h), super like, event reminder 2 h before; in the recipient's language; tapping opens the right screen; on/off in Settings |
| Events | Club runs, ski days, padel nights; join with a capacity limit; attendee list visible after joining; check-in window; "people you met" after the event; hosts create events |
| Money | Pro subscription (weekly, monthly, 6 months), Boost and Super Like packs, restore purchases — store billing via RevenueCat |
| Free tier | 30 likes and 1 super like a day, enforced in the database |
| Growth | 7-day streak → free boost; 2 friends join with your code → 7 days of Pro |
| Safety | Report (auto-blocks; 3 reports auto-hide the profile), block, unmatch, selfie verification, pause profile, in-app account deletion |

All rules that involve money or limits live in SQL, so a modified app can't give itself Pro or extra likes.

## Project layout

```
app/                    Screens (expo-router)
src/lib/                Supabase client, API wrappers, purchases, session, dates
src/components/         Brand mark + ridge, profile card, match moment, buttons, chips, choice sheet
src/i18n/               kk / ru / en strings
supabase/migrations/    Schema, security rules, all server logic
supabase/functions/     RevenueCat webhook
supabase/tests/         132 behavioural tests for the backend
supabase/seed.sql       Demo events (staging only)
assets/sounds/          Placeholder dombra-style UI sounds (scripts/make_sounds.py)
```

## Launch steps

You need: Node 20+, a Mac only if you want local iOS builds (EAS builds in the cloud otherwise), and these accounts — Supabase (free), RevenueCat (free to start), Expo (free), Apple Developer ($99/year), Google Play Console ($25 once).

### 1. Backend (Supabase)

1. Create a project at supabase.com. Frankfurt is the closest region to Kazakhstan.
2. Push the schema:
   ```bash
   npx supabase login
   npx supabase link --project-ref YOUR-PROJECT-REF
   npx supabase db push
   ```
3. **Auth → Email templates → Magic Link**: put the code in the email, e.g. `Your Qadam code: {{ .Token }}`. Without this, users get a link instead of a code.
4. **Auth → SMTP**: connect a real email sender (Resend, Postmark, Mailgun…). Supabase's built-in sender is rate-limited to a handful of emails per hour.
5. Create the App Review demo account: **Auth → Users → Add user** with an email and password, then sign in once in the app and finish onboarding with it.
6. For a staging project only, load demo events: `psql "$DB_URL" -f supabase/seed.sql`.
7. **Database → Extensions**: enable **pg_net** (sends push notifications) and **pg_cron** (event reminders), then run `npx supabase db push` again so the reminder job is scheduled. Optional: if you turn on "Enhanced push security" in Expo, store the token with `alter database postgres set qadam.expo_access_token = '…';`.
8. **Sign in with Apple** — Apple Developer → your App ID → enable *Sign in with Apple*; Supabase → Auth → Providers → Apple → enable and add your bundle id `kz.qadam.app` to Client IDs.
9. **Google** — Google Cloud Console → Credentials: create a *Web* client and an *iOS* client (and an *Android* client with your signing SHA-1). Supabase → Auth → Providers → Google: paste the Web client id and secret, add the iOS client id to Client IDs, and turn on *Skip nonce checks* (needed for native iOS sign-in). Put the Web and iOS ids in `.env`, and replace `REPLACE_WITH_IOS_CLIENT_ID` in `app.json` with the iOS client's reversed id. Leave the Google ids empty to hide the button.

### 2. Run the app

```bash
cp .env.example .env           # fill in the Supabase URL and anon key
npm install
npx expo install --fix         # aligns package versions with the Expo SDK
npm run typecheck
npx eas-cli login && npx eas-cli init     # writes your EAS project id into app.json
npx eas-cli build --profile development --platform ios     # or android
npm start                      # then open the installed dev build
```

Expo Go won't work for purchases (RevenueCat needs native code), so use a development build. Everything except buying works in it before you set up products.

### Native extras (iOS)

- **App Group** — Apple Developer → Identifiers → App Groups → create `group.kz.qadam.app` and enable it for `kz.qadam.app`. The widget reads the app's data through it. EAS can create it for you on the first build.
- The Live Activity (`expo-live-activity`) and the widget (`@bacons/apple-targets`, Swift in `targets/widget`) are generated during `expo prebuild` / EAS build. They need a development or store build, not Expo Go.
- `expo-live-activity` is archived upstream. It works on SDK 54; when you move to SDK 55+, switch to Expo's `expo-widgets`.
- After `npm install`, run `npx expo install --fix` so `expo-symbols` and `@react-native-community/datetimepicker` match SDK 54.

### 3. Products and payments

Create these product IDs in **both** App Store Connect and Google Play Console. The database recognises them by name.

| Product ID | Type | Suggested KZ price |
| --- | --- | --- |
| `qadam_pro_weekly` | Auto-renewing subscription (group "Qadam Pro") | ≈ 1,490 ₸ |
| `qadam_pro_monthly` | Auto-renewing subscription | ≈ 3,490 ₸ |
| `qadam_pro_6m` | Auto-renewing subscription | ≈ 12,990 ₸ |
| `qadam_boost_1` | Consumable | ≈ 690 ₸ |
| `qadam_boost_5` | Consumable | ≈ 2,490 ₸ |
| `qadam_super_5` | Consumable | ≈ 990 ₸ |
| `qadam_super_25` | Consumable | ≈ 3,490 ₸ |
| `qadam_pro_monthly_intro` | Subscription, same group, full monthly price, with a 1-month introductory offer at 50% (App Store: introductory offer; Play: an offer phase on the base plan — not a cheaper base plan, which would renew at the discount) | ≈ 1,745 ₸ first month, then ≈ 3,490 ₸ |
| `qadam_boost_3` | Consumable — decoy, price it the same as `qadam_boost_5` | ≈ 2,490 ₸ |
| `qadam_super_15` | Consumable — decoy, price it the same as `qadam_super_25` | ≈ 3,490 ₸ |

Prices are starting points to test, not research-backed figures.

In RevenueCat:

1. Add the iOS and Android apps and put their public SDK keys in `.env`.
2. Create the entitlement **`pro`** and attach the three subscriptions.
3. Create offerings: **`default`** with Weekly, Monthly and Six Month packages; **`boosts`** with the boost products; **`super_likes`** with the super like products; **`intro`** with one package holding `qadam_pro_monthly_intro` (leave it out to switch the offer off).
4. Deploy the webhook and point RevenueCat at it:
   ```bash
   npx supabase secrets set REVENUECAT_WEBHOOK_SECRET=$(openssl rand -hex 32)
   npx supabase functions deploy revenuecat-webhook --no-verify-jwt
   ```
   In RevenueCat → Integrations → Webhooks, set the URL to `https://YOUR-PROJECT-REF.supabase.co/functions/v1/revenuecat-webhook` and the Authorization header to `Bearer <the same secret>`.
5. Test a sandbox purchase. The Pro badge appears within a few seconds once the webhook lands. You can check `select * from purchase_events order by created_at desc;`.

### 4. Moderation (Supabase SQL editor)

```sql
-- Approve or reject a selfie (photos are in the private "verification" bucket)
update profiles set verification_status = 'approved' where id = '…';

-- Approve a club application (creates the club, makes the applicant its organizer and a host)
select id, club_name, city, sport_code, about from club_applications where status = 'pending';
select approve_club_application('…', 'Saturdays 08:00 · Medeu');

-- Change when a city opens (0 = open now)
update city_launch set opens_at_members = 200 where city = 'astana';

-- Make someone an event host
update profiles set is_host = true where id = '…';

-- Open reports, newest first
select r.*, p.name from reports r join profiles p on p.id = r.reported_id
where r.status = 'open' order by r.created_at desc;

-- Ban, or restore a profile that was auto-hidden by reports
update profiles set banned = true where id = '…';
update profiles set hidden = false where id = '…';
```

### 5. Store submission

```bash
npx eas-cli build --profile production --platform all
npx eas-cli submit --platform all
```

For App Review: give the demo account's email and password in the review notes, mention that sign-in normally uses an email code, set the age rating to 18+, and fill in the privacy questionnaire (email, photos, the city users pick, purchases, user content, sports preferences). Reviewers check that dating apps can report, block and delete the account — all three are in Settings and the chat menu.

Before submitting you also need a hosted Privacy Policy and Terms of Use page; put their URLs in `.env`.

## Tests

```bash
npm run test:db    # migrations + 205 behavioural tests on a throwaway local Postgres
npm test           # date, inbox-time, age, contact-number and photo-blur logic
```

The backend tests cover permissions (no self-granted Pro, no reading others' chats), matching, free limits, purchase crediting and idempotency, blocking, reporting, events and capacity, streaks, referrals, account deletion, likes with notes, push rules and throttling, shared events and reminders, clubs, city launch, prompts, dates in chat, reactions, undo, travel, contact hiding, training-partner matching, daily picks and double dates.

## Where to change things

| Change | Where |
| --- | --- |
| Free limits, boost length, streak and referral rules | `cfg()` at the top of `supabase/migrations/20261020000001_core.sql` (ship as a new migration) |
| Sports list and seasons | `sports` seed at the end of the same migration |
| Cities | `CITIES` in `src/lib/sports.tsx` and `cities` in each `src/i18n/*.ts` |
| Colours and type | `src/lib/theme.ts` (keep in sync with the design system tokens) |
| Sounds | replace the WAVs in `assets/sounds/` with recorded takes (same names; dombra for Kazakhstan) |
| Dark palette, felt, type scaling | `src/lib/theme.ts` |
| Felt texture | `scripts/make_felt.py` → `assets/felt.png` |
| Push wording | `push_text()` in `supabase/migrations/20261020000003_engagement.sql` (ship as a new migration) |
| Text | `src/i18n/kk.ts`, `ru.ts`, `en.ts` |

## Known gaps

- Record real dombra sounds to replace the synthesised placeholders (brief in the design system › Sound and motion).
- Clean up push tokens Expo reports as `DeviceNotRegistered` (read push receipts in a small scheduled job).
- Double-date chats live under Me › Double date, not yet in the Matches tab.
- Nothing in V1.5 has been run on a device yet: test recording, photo upload and the contacts permission on real iOS and Android before release.
- An interactive "Check in" button inside the Live Activity (needs App Intents; today tapping opens the event).
- Kazakh strings are a draft — have a native speaker review `src/i18n/kk.ts`.
- Android photo check: add an on-device nudity model (e.g. an open MobileNet NSFW model via react-native-fast-tflite) so flagged photos get a warning and safe ones can show unblurred; until then Android relies on blur-until-tapped.
- Profile photos are not checked at upload; they rely on reports and selfie verification.
- Event covers of a deleted host stay in storage with their events.
- Paid event tickets (needs a local payment provider and merchant account).
- Apple Health / Strava import for personal bests; a simple admin panel for moderation.
- Same-sex matching is enabled through "Show me: Everyone". If you ever launch in Russia, get legal advice first.
