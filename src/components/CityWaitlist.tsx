// A city that hasn't opened yet: progress toward the launch bar, the person's own
// invites, and a way into events and clubs meanwhile. Dating apps live or die
// by density, so a city opens for Discover only when enough people are in.
import { useRouter } from 'expo-router';
import React from 'react';
import { Share, StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../i18n';
import { tick } from '../lib/haptics';
import { fontScale, fonts, lightPalette, radius, space } from '../lib/theme';
import type { CityStatus } from '../lib/types';
import { Shanyrak } from './Brand';
import { Icon } from './Icon';
import { Button } from './ui';
import { features } from '../lib/features';

export function CityWaitlist({ status, code }: { status: CityStatus; code: string }) {
  const { t, cityName } = useI18n();
  const router = useRouter();
  const city = cityName(status.city);
  const share = Math.min(1, status.members / Math.max(1, status.needed));

  return (
    <View style={styles.wrap}>
      <View style={styles.card}>
        <View style={styles.ring}>
          <Shanyrak size={150} color={lightPalette.gold} slats={0.2} style={StyleSheet.absoluteFill} />
          <Text maxFontSizeMultiplier={fontScale.display} style={styles.pct}>{Math.round(share * 100)}%</Text>
        </View>
        <Text maxFontSizeMultiplier={fontScale.display} style={styles.title} accessibilityRole="header">
          {t('city.waitTitle', { city })}
        </Text>
        <Text maxFontSizeMultiplier={fontScale.body} style={styles.sub}>{t('city.waitSub', { city, needed: status.needed })}</Text>
        <View style={styles.bar} accessibilityRole="progressbar"
          accessibilityValue={{ min: 0, max: status.needed, now: status.members }}>
          <View style={[styles.fill, { width: `${share * 100}%` }]} />
        </View>
        <View style={styles.row}>
          <Text maxFontSizeMultiplier={1.3} style={styles.count}>{t('city.progress', { members: status.members, needed: status.needed })}</Text>
          {status.my_invites > 0 ? <Text maxFontSizeMultiplier={1.3} style={styles.count}>{t('city.invited', { n: status.my_invites })}</Text> : null}
        </View>
        <Button title={t('city.invite')} variant="accent" style={{ alignSelf: 'stretch' }}
          icon={<Icon name="share" size={18} color="onGold" />}
          onPress={() => { tick(); Share.share({ message: t('city.inviteMessage', { city, code }) }); }} />
      </View>
      {features.events ? <Button title={t('city.seeEvents')} variant="secondary" onPress={() => router.push('/events')} /> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, padding: space(2), gap: space(1.5), justifyContent: 'center' },
  card: { backgroundColor: lightPalette.blue, borderRadius: radius.lg, padding: space(3), alignItems: 'center', gap: space(1.25) },
  ring: { width: 150, height: 150, alignItems: 'center', justifyContent: 'center' },
  pct: { fontFamily: fonts.display, fontSize: 30, color: '#FFFFFF' },
  title: { fontFamily: fonts.display, fontSize: 24, lineHeight: 30, color: '#FFFFFF', textAlign: 'center' },
  sub: { fontFamily: fonts.text500, fontSize: 15, lineHeight: 22, color: lightPalette.blueMist, textAlign: 'center' },
  bar: { alignSelf: 'stretch', height: 10, borderRadius: 5, backgroundColor: lightPalette.blueDeep, overflow: 'hidden', marginTop: space(0.5) },
  fill: { height: 10, borderRadius: 5, backgroundColor: lightPalette.gold },
  row: { alignSelf: 'stretch', flexDirection: 'row', justifyContent: 'space-between' },
  count: { fontFamily: fonts.text700, fontSize: 13, color: lightPalette.blueMist },
});

