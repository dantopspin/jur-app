# JÜR for iPhone (SwiftUI)

Native iOS 17+ app. The brand is JÜR (жүр: "come on, let's go"); the target, folders and bundle ID use the plain spelling `Jur` / `kz.jur.app`. The server (Supabase: database, rules, tests, Edge Functions)
is shared with the old Expo app in `../supabase` and unchanged by this rebuild.

## First run (about 5 minutes)

1. `brew install xcodegen` (once).
2. Copy `Config/Secrets.example.xcconfig` → `Config/Secrets.xcconfig` and fill in:
   your Apple Team ID, Supabase host and anon key, RevenueCat iOS key.
   (Hosts have no `https://` because xcconfig treats `//` as a comment.)
3. Add the fonts listed in `Jur/Resources/Fonts/README.md` (optional; the system font is used until then).
4. `xcodegen` in this folder, then open `Jur.xcodeproj`, pick an iPhone simulator, Run.

Swift packages (supabase-swift, RevenueCat) resolve on first open.

If the build fails, send me the first few errors from Xcode's Issue navigator
(⌘5): I can't compile Swift on my side, so your build output is how we fix things fast.

## Strings

`Jur/Resources/Localizable.xcstrings` is generated from `../src/i18n/{kk,ru,en}.ts`:
`npx tsx scripts/make_strings.mjs`. Keys are dotted ("discover.empty"); `{name}` placeholders
are filled by `t("key", ["name": value])`. The language can be switched in Settings.

## Milestones

1. **This build:** project, design tokens, components, server client, sign-in (Apple and email code),
   the session gate (with Retry on a failed load), tab shell, basic Me and Settings (language, legal,
   sign out, delete account).
2. Onboarding, profile card, Discover, likes with notes, match moment.
3. Matches and chat (replies, photos with photo safety, voice notes, reactions, date cards).
4. Events (member-hosted, check-in codes), badges, Pro paywall and the Pro gift, settings, safety.
5. Widgets and Live Activity, App Store screenshots in the new art direction.
