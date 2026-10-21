import {
  Manrope_400Regular, Manrope_500Medium, Manrope_600SemiBold, Manrope_700Bold, Manrope_800ExtraBold,
} from '@expo-google-fonts/manrope';
import { Unbounded_700Bold, Unbounded_800ExtraBold, useFonts } from '@expo-google-fonts/unbounded';
import { Stack, useRouter, useSegments } from 'expo-router';
import * as Notifications from 'expo-notifications';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { AppState } from 'react-native';
import { useStackOptions } from '../src/components/nav';
import React, { useEffect, useRef } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { SheetProvider } from '../src/components/Sheet';
import { ToastHost } from '../src/components/Toast';
import { HeaderTextButton } from '../src/components/HeaderButton';
import { Button, Empty, ErrorState, Screen } from '../src/components/ui';
import { I18nProvider, useI18n } from '../src/i18n';
import { SessionProvider, useSession } from '../src/lib/session';
import { urlFromResponse } from '../src/lib/push';
import { SportsProvider } from '../src/lib/sports';
import { refreshWidget } from '../src/lib/widget';

SplashScreen.preventAutoHideAsync().catch(() => {});

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    Unbounded_700Bold, Unbounded_800ExtraBold,
    Manrope_400Regular, Manrope_500Medium, Manrope_600SemiBold, Manrope_700Bold, Manrope_800ExtraBold,
  });
  if (!fontsLoaded) return null;
  return (
    <SafeAreaProvider>
      <I18nProvider>
        <SportsProvider>
          <SessionProvider>
            <SheetProvider>
              <StatusBar style="auto" />
              <Gate />
              <ToastHost />
            </SheetProvider>
          </SessionProvider>
        </SportsProvider>
      </I18nProvider>
    </SafeAreaProvider>
  );
}

/** Sends people to sign-in, onboarding or the app depending on their state. */
function Gate() {
  const { ready, session, profile, profileError, refreshProfile, signOut } = useSession();
  const { t, intl } = useI18n();
  const stackOptions = useStackOptions();
  // Card-style modals get a Cancel button where iOS puts it.
  const cancel = { headerLeft: () => <HeaderTextButton title={t('common.cancel')} onPress={() => router.back()} /> };
  const segments = useSegments();
  const router = useRouter();
  const first = segments[0] as string | undefined;
  const lastPush = Notifications.useLastNotificationResponse();
  const handledPush = useRef<string | null>(null);

  useEffect(() => {
    if (!ready) return;
    SplashScreen.hideAsync().catch(() => {});
    if (!session) {
      if (first !== 'sign-in') router.replace('/sign-in');
    } else if (!profile) {
      // Only a confirmed "no profile" means onboarding; a failed load shows Retry below.
      if (!profileError && first !== 'onboarding') router.replace('/onboarding');
    } else if (first === undefined || first === 'sign-in' || first === 'onboarding') {
      router.replace('/discover');
    }
  }, [ready, session, profile, profileError, first, router]);

  // Keep the Home Screen widget fresh: on sign-in and whenever the app comes back.
  useEffect(() => {
    if (!profile) return;
    const run = () => refreshWidget((k) => t(k), intl);
    run();
    const sub = AppState.addEventListener('change', (st) => { if (st === 'active') run(); });
    return () => sub.remove();
  }, [profile, t, intl]);

  // Tapping a notification opens the chat, likes or event it is about.
  useEffect(() => {
    if (!ready || !profile || !lastPush) return;
    const id = lastPush.notification.request.identifier;
    const url = urlFromResponse(lastPush);
    if (!url || handledPush.current === id) return;
    handledPush.current = id;
    router.push(url as never);
  }, [ready, profile, lastPush, router]);

  if (ready && session && !profile && profileError) {
    return (
      <Screen edges={['top', 'bottom']}>
        <ErrorState onRetry={() => { refreshProfile().catch(() => {}); }} />
        <Button title={t('settings.signOut')} variant="ghost" onPress={signOut} style={{ marginBottom: 16 }} />
      </Screen>
    );
  }

  if (profile?.banned) {
    return (
      <Screen>
        <Empty title={t('common.error')} sub={t('common.suspended')} action={t('settings.signOut')} onAction={signOut} />
      </Screen>
    );
  }

  return (
    <Stack screenOptions={stackOptions}>
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="sign-in" options={{ headerShown: false }} />
      <Stack.Screen name="onboarding" options={{ headerShown: false, gestureEnabled: false }} />
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="paywall" options={{ presentation: 'modal', headerShown: false }} />
      <Stack.Screen name="chat/[id]" options={{ title: '' }} />
      <Stack.Screen name="profile/[id]" options={{ title: '' }} />
      <Stack.Screen name="event/[id]" options={{ title: '' }} />
      <Stack.Screen name="event/new" options={{ ...cancel, title: t('events.create'), presentation: 'modal' }} />
      <Stack.Screen name="edit-profile" options={{ title: t('edit.title') }} />
      <Stack.Screen name="settings" options={{ title: t('settings.title') }} />
      <Stack.Screen name="verify" options={{
        title: t('verify.title'), presentation: 'formSheet', sheetAllowedDetents: [0.6, 1], sheetGrabberVisible: true,
        sheetCornerRadius: 28,
      }} />
      <Stack.Screen name="likes" options={{ title: t('likes.title') }} />
      <Stack.Screen name="club/[id]" options={{ title: '' }} />
      <Stack.Screen name="club/chat/[id]" options={{ title: t('clubs.chat') }} />
      <Stack.Screen name="club/apply" options={{ ...cancel, title: t('clubs.applyTitle'), presentation: 'modal' }} />
      <Stack.Screen name="offer" options={{ presentation: 'modal', headerShown: false }} />
      <Stack.Screen name="picks" options={{ title: t('picks.title') }} />
      <Stack.Screen name="hide-contacts" options={{ title: t('contacts.title') }} />
      <Stack.Screen name="prompts" options={{ ...cancel, title: t('prompts.title'), presentation: 'modal' }} />
      <Stack.Screen name="duo/index" options={{ title: t('duo.title') }} />
      <Stack.Screen name="duo/find" options={{ title: t('duo.find') }} />
      <Stack.Screen name="duo/chat/[id]" options={{ title: t('duo.title') }} />
    </Stack>
  );
}
