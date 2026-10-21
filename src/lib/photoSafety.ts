// Photo safety for chat photos.
// 1. On iOS 17+, Apple's on-device Sensitive Content Analysis checks each incoming
//    photo (only when the person has Sensitive Content Warning turned on).
// 2. Everywhere else, incoming photos stay blurred until tapped, unless the person
//    turns "Blur photos in chats" off in Settings.
// Nothing about the photo is sent anywhere; the check runs on the phone.
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system/legacy';
import { useEffect, useState } from 'react';
import { QadamSensitive } from '../../modules/qadam-sensitive';
import type { Assessment } from './photoPolicy';

const KEY = 'qadam.blurChatPhotos';
let blurAll = true;
let loaded = false;
const listeners = new Set<(v: boolean) => void>();

AsyncStorage.getItem(KEY).then((v) => {
  loaded = true;
  if (v === 'off') { blurAll = false; listeners.forEach((l) => l(false)); }
}).catch(() => { loaded = true; });

export function setBlurAll(v: boolean) {
  blurAll = v;
  AsyncStorage.setItem(KEY, v ? 'on' : 'off').catch(() => {});
  listeners.forEach((l) => l(v));
}

/** The "Blur photos in chats" setting (on by default). */
export function useBlurAll(): boolean {
  const [v, setV] = useState(blurAll);
  useEffect(() => {
    if (loaded) setV(blurAll);
    listeners.add(setV);
    return () => { listeners.delete(setV); };
  }, []);
  return v;
}

let policy: Promise<string> | null = null;
function devicePolicy(): Promise<string> {
  if (!QadamSensitive) return Promise.resolve('unavailable');
  policy ??= QadamSensitive.policy().catch(() => 'unavailable');
  return policy;
}

/** True when this phone can check photos itself (iOS 17+ with Sensitive Content Warning on). */
export async function deviceCheckAvailable(): Promise<boolean> {
  const p = await devicePolicy();
  return p === 'simple' || p === 'descriptive';
}

const cache = new Map<string, Promise<Assessment>>();

/** Checks a chat photo on the device. 'unknown' when no check is possible or it failed. */
export function assessPhoto(path: string, signedUrl: string): Promise<Assessment> {
  const hit = cache.get(path);
  if (hit) return hit;
  const run = (async (): Promise<Assessment> => {
    if (!(await deviceCheckAvailable()) || !QadamSensitive) return 'unknown';
    const local = `${FileSystem.cacheDirectory}scan-${path.replace(/[^a-zA-Z0-9.-]/g, '_')}`;
    try {
      await FileSystem.downloadAsync(signedUrl, local);
      return (await QadamSensitive.analyze(local)) ? 'sensitive' : 'clear';
    } catch {
      return 'unknown';
    } finally {
      FileSystem.deleteAsync(local, { idempotent: true }).catch(() => {});
    }
  })();
  cache.set(path, run);
  return run;
}
