// Run: npx tsx --test src/lib/dates.test.ts
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ageOn, almatyToIso, isAdult, parseBirthdate } from './dates';

test('parseBirthdate accepts real dates and rejects impossible ones', () => {
  assert.equal(parseBirthdate('29', '02', '2000')?.toISOString().slice(0, 10), '2000-02-29');
  assert.equal(parseBirthdate('29', '02', '2001'), null);
  assert.equal(parseBirthdate('31', '04', '1995'), null);
  assert.equal(parseBirthdate('', '01', '1995'), null);
  assert.equal(parseBirthdate('01', '01', '1900'), null);
});

test('isAdult flips exactly on the 18th birthday', () => {
  const birth = parseBirthdate('20', '10', '2008')!;
  assert.equal(isAdult(birth, new Date(Date.UTC(2026, 9, 19, 23, 59))), false);
  assert.equal(isAdult(birth, new Date(Date.UTC(2026, 9, 20, 0, 0))), true);
});

test('almatyToIso converts Almaty local time (UTC+5) to UTC', () => {
  assert.equal(almatyToIso('2026-11-07', '09:00'), '2026-11-07T04:00:00.000Z');
  assert.equal(almatyToIso('2026-11-07', '03:30'), '2026-11-06T22:30:00.000Z');
  assert.equal(almatyToIso('2026-02-30', '09:00'), null);
  assert.equal(almatyToIso('2026-11-07', '25:00'), null);
  assert.equal(almatyToIso('07.11.2026', '09:00'), null);
});

test('ageOn counts whole years', () => {
  const birth = parseBirthdate('20', '10', '1998')!;
  assert.equal(ageOn(birth, new Date(Date.UTC(2026, 9, 19))), 27);
  assert.equal(ageOn(birth, new Date(Date.UTC(2026, 9, 20))), 28);
});

test('formatInboxTime: clock today, yesterday, weekday, then date (Almaty days)', async () => {
  const { formatInboxTime } = await import('./dates');
  const now = new Date('2026-10-20T15:00:00Z'); // 20:00 Almaty
  assert.equal(formatInboxTime('2026-10-20T04:05:00Z', 'en', now), '09:05');
  assert.equal(formatInboxTime('2026-10-19T20:00:00Z', 'en', now), '01:00'); // already the 20th in Almaty
  assert.equal(formatInboxTime('2026-10-19T10:00:00Z', 'en', now), 'Yesterday');
  assert.equal(formatInboxTime('2026-10-16T10:00:00Z', 'en', now), 'Fri');
  assert.equal(formatInboxTime('2026-10-01T10:00:00Z', 'en', now), '10/01/26');
});

test('needsDivider after 15 quiet minutes or a new Almaty day', async () => {
  const { needsDivider } = await import('./dates');
  assert.equal(needsDivider(null, '2026-10-20T10:00:00Z'), true);
  assert.equal(needsDivider('2026-10-20T10:00:00Z', '2026-10-20T10:14:00Z'), false);
  assert.equal(needsDivider('2026-10-20T10:00:00Z', '2026-10-20T10:15:00Z'), true);
  assert.equal(needsDivider('2026-10-20T18:58:00Z', '2026-10-20T19:02:00Z'), true); // midnight in Almaty
});
