// Run: npx tsx --test src/lib/photoPolicy.test.ts
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { photoTreatment } from './photoPolicy';

test('a photo flagged on the device is always blurred with a warning', () => {
  assert.deepEqual(photoTreatment('sensitive', false, false), { blur: true, warn: true });
  assert.deepEqual(photoTreatment('sensitive', true, false), { blur: true, warn: true });
});

test('a photo the device checked and cleared shows normally', () => {
  assert.deepEqual(photoTreatment('clear', true, false), { blur: false, warn: false });
});

test('without a device check, the blur setting decides', () => {
  assert.deepEqual(photoTreatment('unknown', true, false), { blur: true, warn: false });
  assert.deepEqual(photoTreatment('unknown', false, false), { blur: false, warn: false });
});

test('your own photos are never blurred', () => {
  assert.deepEqual(photoTreatment('sensitive', true, true), { blur: false, warn: false });
});
