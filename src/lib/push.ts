// Push notifications: permission, Expo push token, Android channels, and
// routing when someone taps a notification. The server decides what to send
// (supabase/migrations/…_engagement.sql); the app only registers the device.
import Constants from 'expo-constants';
import * as Notifications from 'expo-notifications';
import { Linking, Platform } from 'react-native';
import { api } from './api';

export type PushPermission = 'granted' | 'denied' | 'undetermined';

// In the foreground the app plays its own sound and haptic, so show the banner silently.
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

let currentToken: string | null = null;

async function ensureChannels(labels: { matches: string; chats: string; activity: string }) {
  if (Platform.OS !== 'android') return;
  await Notifications.setNotificationChannelAsync('matches', {
    name: labels.matches, importance: Notifications.AndroidImportance.HIGH, sound: 'match.wav',
    vibrationPattern: [0, 120, 80, 120], lightColor: '#1F5FA0',
  });
  await Notifications.setNotificationChannelAsync('chats', {
    name: labels.chats, importance: Notifications.AndroidImportance.HIGH, sound: 'default',
  });
  await Notifications.setNotificationChannelAsync('activity', {
    name: labels.activity, importance: Notifications.AndroidImportance.DEFAULT, sound: 'default',
  });
}

export async function pushPermission(): Promise<PushPermission> {
  try {
    const { status } = await Notifications.getPermissionsAsync();
    return status as PushPermission;
  } catch {
    return 'undetermined';
  }
}

/** Shows the system prompt (call it only after the in-app explanation). */
export async function requestPushPermission(labels: { matches: string; chats: string; activity: string }): Promise<boolean> {
  try {
    await ensureChannels(labels); // Android 13+ shows the prompt once a channel exists
    const { status } = await Notifications.requestPermissionsAsync();
    return status === 'granted';
  } catch {
    return false;
  }
}

/** Registers this device for the signed-in profile if notifications are allowed. Never throws. */
export async function syncPushToken(labels: { matches: string; chats: string; activity: string }) {
  try {
    if ((await pushPermission()) !== 'granted') return;
    await ensureChannels(labels);
    const projectId = Constants.expoConfig?.extra?.eas?.projectId as string | undefined;
    const { data } = await Notifications.getExpoPushTokenAsync(projectId ? { projectId } : undefined);
    currentToken = data;
    await api.registerPushToken(data, Platform.OS === 'ios' ? 'ios' : 'android');
  } catch (e) {
    // simulators and builds without an EAS project id can't get a token
    console.warn('push registration skipped', e);
  }
}

/** On sign-out: stop sending this account's notifications to this phone. */
export async function forgetPushToken() {
  if (!currentToken) return;
  await api.unregisterPushToken(currentToken).catch(() => {});
  currentToken = null;
}

/** "Allow in Settings" for people who said no to the system prompt. */
export function openSystemSettings() {
  Linking.openSettings().catch(() => {});
}

/** The in-app path a notification should open, e.g. "/chat/…". */
export function urlFromResponse(r: Notifications.NotificationResponse | null | undefined): string | null {
  const url = r?.notification.request.content.data?.url;
  return typeof url === 'string' && url.startsWith('/') ? url : null;
}
