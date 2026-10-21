import { Image } from 'expo-image';
import { getAppIconName, setAlternateAppIcon, supportsAlternateIcons } from 'expo-alternate-app-icons';
import React, { useEffect, useState } from 'react';
import { Alert, Linking, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Segmented } from '../src/components/Segmented';
import { Icon } from '../src/components/Icon';
import { ListItem, ListSection, Screen, SectionLabel } from '../src/components/ui';
import { useI18n } from '../src/i18n';
import { api } from '../src/lib/api';
import { env } from '../src/lib/env';
import { setSoundsEnabled, soundsEnabled } from '../src/lib/feedback';
import { tick } from '../src/lib/haptics';
import { openSystemSettings, pushPermission, requestPushPermission, syncPushToken, type PushPermission } from '../src/lib/push';
import { manageSubscriptionsUrl, purchasesAvailable } from '../src/lib/purchases';
import { useSession } from '../src/lib/session';
import { useSheet } from '../src/components/Sheet';
import { useRouter } from 'expo-router';
import { CITIES } from '../src/lib/sports';
import { formatShortDate } from '../src/lib/dates';
import { supabase } from '../src/lib/supabase';
import { colors, curve, layout, sp, type } from '../src/lib/theme';
import type { Locale } from '../src/lib/types';
import { showError } from '../src/lib/errors';
import { features } from '../src/lib/features';
import { deviceCheckAvailable, setBlurAll, useBlurAll } from '../src/lib/photoSafety';

export default function Settings() {
  const { t, locale, setLocale, cityName, intl } = useI18n();
  const sheet = useSheet();
  const router = useRouter();
  const { profile, refreshProfile, signOut, limits } = useSession();
  const [paused, setPaused] = useState(profile?.hidden ?? false);
  const [sounds, setSounds] = useState(true);
  const blurAll = useBlurAll();
  const [deviceCheck, setDeviceCheck] = useState(false);
  useEffect(() => { deviceCheckAvailable().then(setDeviceCheck); }, []);

  const [push, setPush] = useState<PushPermission | null>(null);
  const [icon, setIcon] = useState<string | null>(() => (supportsAlternateIcons ? getAppIconName() : null));

  async function chooseIcon(name: string | null) {
    tick();
    try {
      await setAlternateAppIcon(name);
      setIcon(name);
    } catch (e) {
      showError(t, e);
    }
  }

  useEffect(() => { soundsEnabled().then(setSounds); pushPermission().then(setPush); }, []);

  const travelling = !!(profile?.travel_city && profile.travel_until && new Date(profile.travel_until) > new Date());

  function travel() {
    if (!limits?.pro) { router.push('/paywall'); return; }
    if (travelling) {
      sheet({ cancelLabel: t('common.cancel'), options: [{ label: t('travel.end'), destructive: true,
        onPress: async () => { await api.clearTravel(); refreshProfile(); } }] });
      return;
    }
    sheet({
      title: t('travel.pickCity'), cancelLabel: t('common.cancel'),
      options: CITIES.filter((c) => c !== profile?.city).map((c) => ({
        label: cityName(c),
        onPress: () => sheet({
          title: t('travel.pickDays'), cancelLabel: t('common.cancel'),
          options: [3, 7, 14].map((n) => ({
            label: t('travel.days', { n }),
            onPress: async () => {
              const r = await api.setTravel(c, n);
              if (!r.ok) Alert.alert(r.error === 'pro_only' ? t('travel.proOnly') : t('common.error'));
              refreshProfile();
            },
          })),
        }),
      })),
    });
  }

  async function notifications() {
    const labels = { matches: t('notify.matches'), chats: t('notify.chats'), activity: t(features.events ? 'notify.activity' : 'notify.activityApp') };
    if (push === 'undetermined') {
      const granted = await requestPushPermission(labels);
      setPush(granted ? 'granted' : 'denied');
      if (granted) syncPushToken(labels);
    } else {
      openSystemSettings(); // turning off, or allowing after an earlier "no", happens in the phone's settings
    }
  }

  if (!profile) return null;
  const userId = profile.id;

  async function changeLocale(l: Locale) {
    setLocale(l);
    await supabase.from('profiles').update({ locale: l }).eq('id', userId);
  }

  async function togglePause(v: boolean) {
    setPaused(v);
    const { error } = await supabase.from('profiles').update({ hidden: v }).eq('id', userId);
    if (error) {
      setPaused(!v);
      Alert.alert(t('common.error'), error.message);
    } else {
      refreshProfile();
    }
  }

  async function manageSub() {
    const url = purchasesAvailable() ? await manageSubscriptionsUrl() : null;
    Linking.openURL(url ?? (Platform.OS === 'ios'
      ? 'https://apps.apple.com/account/subscriptions'
      : 'https://play.google.com/store/account/subscriptions'));
  }

  function deleteAccount() {
    Alert.alert(t('settings.deleteAccount'), t('settings.deleteConfirm'), [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('common.delete'), style: 'destructive',
        onPress: async () => {
          try {
            await api.deleteAccount();
            Alert.alert(t('settings.deleted'));
            await signOut();
          } catch (e) {
            showError(t, e);
          }
        },
      },
    ]);
  }

  const pushLabel = push === 'granted' ? t('notify.on') : push === 'denied' ? t('notify.off') : push ? t('notify.ask') : undefined;

  return (
    <Screen edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.page}>
        <View>
          <SectionLabel style={{ paddingHorizontal: layout.margin }}>{t('settings.language')}</SectionLabel>
          <Segmented value={locale} onChange={changeLocale}
            options={[{ value: 'kk', label: 'Қазақша' }, { value: 'ru', label: 'Русский' }, { value: 'en', label: 'English' }]} />
        </View>

        <ListSection>
          <ListItem icon="hide" tint="inkSoft" title={t('settings.pause')} subtitle={t('settings.pauseHint')}
            toggle={{ value: paused, onChange: togglePause }} />
          <ListItem icon="sound" tint="clay" title={t('settings.sounds')} subtitle={t('settings.soundsHint')}
            toggle={{ value: sounds, onChange: (v) => { setSounds(v); setSoundsEnabled(v); } }} />
          <ListItem icon="bell" tint="danger" title={t('notify.setting')} right={pushLabel} onPress={notifications} />
        </ListSection>

        <ListSection>
          <ListItem icon="plane" title={t('travel.title')} onPress={travel}
            subtitle={travelling ? t('travel.active', { city: cityName(profile.travel_city!), date: formatShortDate(profile.travel_until!, intl) })
              : limits?.pro ? t('travel.hint') : t('travel.proOnly')} />
          <ListItem icon="eyeoff" tint="good" title={t('contacts.title')} onPress={() => router.push('/hide-contacts')} />
        </ListSection>

        <ListSection footer={deviceCheck ? t('safety.footerDevice') : t('safety.footer')}>
          <ListItem icon="photo" tint="clayDeep" title={t('safety.blurSetting')} toggle={{ value: blurAll, onChange: setBlurAll }} />
        </ListSection>

        {supportsAlternateIcons && (
          <View>
            <SectionLabel style={{ paddingHorizontal: layout.margin }}>{t('icons.title')}</SectionLabel>
            <View style={styles.icons}>
              {APP_ICONS.map((a) => {
                const on = (icon ?? null) === a.name;
                return (
                  <Pressable key={a.key} onPress={() => chooseIcon(a.name)} style={styles.iconTile}
                    accessibilityRole="radio" accessibilityState={{ selected: on }} accessibilityLabel={t(a.label)}>
                    <View>
                      <Image source={a.src} style={styles.iconImg} />
                      {on ? <View style={styles.iconCheck}><Icon name="check" size={20} color="blueText" /></View> : null}
                    </View>
                    <Text maxFontSizeMultiplier={1.4} style={[styles.iconLabel, on && { color: colors.blueText }]}>{t(a.label)}</Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        )}

        <ListSection>
          <ListItem icon="card" tint="blueDeep" title={t('settings.manageSub')} onPress={manageSub} />
          <ListItem icon="lock" tint="inkSoft" title={t('settings.privacy')} onPress={() => Linking.openURL(env.privacyUrl)} />
          <ListItem icon="doc" tint="inkSoft" title={t('settings.terms')} onPress={() => Linking.openURL(env.termsUrl)} />
          <ListItem icon="help" tint="inkSoft" title={t('settings.support')} onPress={() => Linking.openURL(`mailto:${env.supportEmail}`)} />
        </ListSection>

        <ListSection>
          <ListItem center title={t('settings.signOut')} onPress={signOut} />
        </ListSection>
        <ListSection>
          <ListItem center danger title={t('settings.deleteAccount')} onPress={deleteAccount} />
        </ListSection>
      </ScrollView>
    </Screen>
  );
}

const APP_ICONS = [
  { key: 'classic', name: null, label: 'icons.classic', src: require('../assets/icon.png') },
  { key: 'night', name: 'Night', label: 'icons.night', src: require('../assets/icons/night.png') },
  { key: 'felt', name: 'Felt', label: 'icons.felt', src: require('../assets/icons/felt.png') },
  { key: 'nauryz', name: 'Nauryz', label: 'icons.nauryz', src: require('../assets/icons/nauryz.png') },
] as const;

const styles = StyleSheet.create({
  page: { padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 },
  icons: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: sp.xs },
  iconTile: { alignItems: 'center', gap: sp.sm, width: 72 },
  iconImg: { width: 60, height: 60, borderRadius: 14, ...curve },
  iconCheck: { position: 'absolute', right: -6, bottom: -6, backgroundColor: colors.bg, borderRadius: 12, padding: 1 },
  iconLabel: { ...type.caption, color: colors.muted },
});
