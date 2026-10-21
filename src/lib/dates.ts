// Date helpers shared by screens (pure functions; unit-tested in src/lib/dates.test.ts).

export function parseBirthdate(dd: string, mm: string, yyyy: string): Date | null {
  const d = Number(dd), m = Number(mm), y = Number(yyyy);
  if (!d || !m || !y || y < 1920) return null;
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return null;
  return date;
}

export function isAdult(birth: Date, now = new Date()): boolean {
  const eighteen = new Date(Date.UTC(birth.getUTCFullYear() + 18, birth.getUTCMonth(), birth.getUTCDate()));
  return eighteen.getTime() <= now.getTime();
}

/** Whole years between birth and now (for the "You're 27" confirmation). */
export function ageOn(birth: Date, now = new Date()): number {
  let age = now.getUTCFullYear() - birth.getUTCFullYear();
  const beforeBirthday = now.getUTCMonth() < birth.getUTCMonth()
    || (now.getUTCMonth() === birth.getUTCMonth() && now.getUTCDate() < birth.getUTCDate());
  if (beforeBirthday) age -= 1;
  return age;
}

/** "Sat 25 Oct, 09:00" in the user's language, Almaty time. */
export function formatEventTime(iso: string, intl: string): string {
  const d = new Date(iso);
  const day = d.toLocaleDateString(intl, { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Asia/Almaty' });
  const time = d.toLocaleTimeString(intl, { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'Asia/Almaty' });
  return `${day}, ${time}`;
}

export function formatShortDate(iso: string, intl: string): string {
  return new Date(iso).toLocaleDateString(intl, { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Almaty' });
}

export function formatClock(iso: string, intl: string): string {
  return new Date(iso).toLocaleTimeString(intl, { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'Asia/Almaty' });
}

/** Builds an ISO timestamp from a local Almaty date "YYYY-MM-DD" and time "HH:MM" (UTC+5, no DST). */
export function almatyToIso(date: string, time: string): string | null {
  const dm = date.trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const tm = time.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!dm || !tm) return null;
  const [y, mo, d] = [Number(dm[1]), Number(dm[2]), Number(dm[3])];
  const [h, mi] = [Number(tm[1]), Number(tm[2])];
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null;
  const utc = Date.UTC(y, mo - 1, d, h - 5, mi);
  const check = new Date(utc + 5 * 3600 * 1000);
  if (check.getUTCDate() !== d || check.getUTCMonth() !== mo - 1) return null;
  return new Date(utc).toISOString();
}

const ALMATY = 'Asia/Almaty';
/** "2026-10-20" for the Almaty calendar day of a moment. */
function dayKey(d: Date): string {
  return d.toLocaleDateString('en-CA', { timeZone: ALMATY });
}
function daysBetween(a: Date, b: Date): number {
  return Math.round((Date.parse(dayKey(b)) - Date.parse(dayKey(a))) / 86400000);
}
function capital(s: string): string {
  return s.charAt(0).toLocaleUpperCase() + s.slice(1);
}

/** Inbox time, as Messages shows it: "14:05" today, "Yesterday", "Tue" this week, then "12.10.26". */
export function formatInboxTime(iso: string, intl: string, now = new Date()): string {
  const d = new Date(iso);
  const days = daysBetween(d, now);
  if (days <= 0) return formatClock(iso, intl);
  if (days === 1) return capital(new Intl.RelativeTimeFormat(intl, { numeric: 'auto' }).format(-1, 'day'));
  if (days < 7) return capital(d.toLocaleDateString(intl, { weekday: 'short', timeZone: ALMATY }));
  return d.toLocaleDateString(intl, { day: '2-digit', month: '2-digit', year: '2-digit', timeZone: ALMATY });
}

/** Chat time divider: "Today 14:05", "Yesterday 09:30", "Tue 25 Oct, 18:00". */
export function formatDivider(iso: string, intl: string, now = new Date()): string {
  const d = new Date(iso);
  const days = daysBetween(d, now);
  const clock = formatClock(iso, intl);
  if (days <= 1) return `${capital(new Intl.RelativeTimeFormat(intl, { numeric: 'auto' }).format(-Math.max(0, days), 'day'))} ${clock}`;
  return formatEventTime(iso, intl);
}

/** Show a time divider before a message when the chat was quiet for this long (or the day changed). */
export const DIVIDER_GAP_MS = 15 * 60 * 1000;
export function needsDivider(prevIso: string | null | undefined, iso: string): boolean {
  if (!prevIso) return true;
  const a = new Date(prevIso); const b = new Date(iso);
  return b.getTime() - a.getTime() >= DIVIDER_GAP_MS || dayKey(a) !== dayKey(b);
}
