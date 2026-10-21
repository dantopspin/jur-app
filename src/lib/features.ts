// Product switches that change what the app shows, not how it works.
//
// events: offline events, clubs, wristbands and check-in. Off for the nationwide,
// app-only launch: the Events tab and every "see events" / "host events" entry
// point disappear, and copy that mentions events uses its app-only wording.
// All the event code, tables and tests stay; set EXPO_PUBLIC_EVENTS=on to bring
// them back in a build.
export const features = {
  events: process.env.EXPO_PUBLIC_EVENTS === 'on',
} as const;
