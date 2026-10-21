# JÜR for iPhone (SwiftUI)

Native iOS 17+ app. The brand is JÜR (жүр: "come on, let's go"); the target, folders and bundle ID use the plain spelling `Jur` / `kz.jur.app`. The server (Supabase: database, rules, tests, Edge Functions)
is shared with the old Expo app in `../supabase` and unchanged by this rebuild.

## First run

1. Copy `Config/Secrets.example.xcconfig` → `Config/Secrets.xcconfig` and fill in:
   your Apple Team ID, Supabase host and anon key, RevenueCat iOS key.
   (Hosts have no `https://` because xcconfig treats `//` as a comment.)
2. Add the fonts listed in `Jur/Resources/Fonts/README.md` (optional; the system font is used until then).
3. Open `Jur.xcodeproj`, pick an iPhone simulator, Run. Packages (supabase-swift, RevenueCat)
   resolve on first open.

`Jur.xcodeproj` is checked in and uses Xcode 16+ folder-synced groups, so new files under `Jur/`
are picked up without editing the project. `python3 scripts/make_xcodeproj.py` rewrites it
(and `Jur/Info.plist`, `Jur/Jur.entitlements`) if build settings change; `project.yml` remains for
anyone who prefers XcodeGen. Last verified: Xcode 26.6, iOS 26.2 Simulator, Supabase 2.55.4,
RevenueCat 5.96.1.

## Push notifications

The app registers its APNs token with `register_push_token`. The server sends through the
`apns` Edge Function (`../supabase/functions/apns`). Set its secrets (`PUSH_SECRET`, `APNS_KEY_ID`,
`APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC=kz.jur.app`, `APNS_ENV`) and the two database
settings at the top of `20261021000012_native_push.sql`. A tap opens the push's `url`
(`/chat/<id>`, `/likes`, `/event/<id>`, `/picks`).

## Strings

`Jur/Resources/Localizable.xcstrings` is generated from `../src/i18n/{kk,ru,en}.ts`:
`npx tsx scripts/make_strings.mjs`. Keys are dotted ("discover.empty"); `{name}` placeholders
are filled by `t("key", ["name": value])`. The language can be switched in Settings.

## What's in the app

Sign-in (Apple, email code), onboarding, Discover (tonight's board, cards, like with a note, super,
undo, boost, today's picks), match moment, Likes, Pairs and chat (text, date tickets, photos with
blur and on-device nudity check, voice notes, report/block/unmatch), Events (board, detail,
join/leave, boarding code, host code, new event), Me (passport, edit profile, prompts, travel mode,
verification, Pro paywall, Pro welcome and gift, redeem), Settings.

Not yet: replies and reactions in chat, double dates, clubs, referral invites, hide-from-contacts,
widgets and Live Activity.
