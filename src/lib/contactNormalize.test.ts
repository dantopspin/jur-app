// Run: npx tsx --test src/lib/contactNormalize.test.ts
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { normaliseEmail, normalisePhone } from './contactNormalize';

test('phones normalise to one Kazakhstan format', () => {
  assert.equal(normalisePhone('8 777 123 45 67'), '77771234567');
  assert.equal(normalisePhone('+7 (777) 123-45-67'), '77771234567');
  assert.equal(normalisePhone('777 123 4567'), '77771234567');
  assert.equal(normalisePhone('123'), null);
});

test('emails are trimmed and lower-cased', () => {
  assert.equal(normaliseEmail('  Dana@Example.COM '), 'dana@example.com');
  assert.equal(normaliseEmail('not an email'), null);
});
