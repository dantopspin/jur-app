// Seasons and holidays, in Almaty time. They tint small things — a greeting on
// Discover, snow on the horizon, the Nauryz icon — never the whole app.
// Religious holidays are deliberately not themed automatically.
import type { TKey } from '../i18n';
import { currentSeason } from './sports';

export type Moment = 'nauryz' | 'newyear' | 'winter' | 'summer';

function almaty(d: Date): Date {
  return new Date(d.getTime() + 5 * 3600_000); // UTC+5, read with getUTC*
}

export function seasonalMoment(now = new Date()): Moment {
  const a = almaty(now);
  const m = a.getUTCMonth() + 1;
  const day = a.getUTCDate();
  if (m === 3 && day >= 20 && day <= 24) return 'nauryz';
  if ((m === 12 && day >= 28) || (m === 1 && day <= 2)) return 'newyear';
  return currentSeason(now) === 'winter' ? 'winter' : 'summer';
}

/** Snow on the horizon line, November to March. */
export function snowOnHorizon(now = new Date()): boolean {
  return currentSeason(now) === 'winter';
}

/** "Good morning, Aigerim" by Almaty hour, plus a seasonal line when there is one. */
export function greeting(now = new Date()): { hello: TKey; seasonal: TKey | null } {
  const h = almaty(now).getUTCHours();
  const hello: TKey = h >= 5 && h < 12 ? 'greet.morning' : h >= 18 || h < 5 ? 'greet.evening' : 'greet.day';
  const m = seasonalMoment(now);
  const seasonal: TKey | null = m === 'nauryz' ? 'greet.nauryz' : m === 'newyear' ? 'greet.newyear'
    : m === 'winter' ? 'greet.winter' : null;
  return { hello, seasonal };
}
