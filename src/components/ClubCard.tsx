// A club in the list: sport tile, name, schedule, faces, next event.
import { Image } from 'expo-image';
import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../i18n';
import { formatEventTime } from '../lib/dates';
import { colors, curve, fonts, iconSize, radius, sp, type } from '../lib/theme';
import type { Club } from '../lib/types';
import { Icon, sportIconName } from './Icon';

export function ClubCardBody({ c }: { c: Club }) {
  const { t, intl } = useI18n();
  return (
    <>
      <View style={styles.top}>
        <View style={styles.tile}><Icon name={sportIconName(c.sport_code)} size={iconSize.action - 2} color="white" /></View>
        <View style={{ flex: 1, gap: sp.xxs }}>
          <Text maxFontSizeMultiplier={1.35} style={styles.name} numberOfLines={2}>{c.name}</Text>
          {c.schedule ? <Text maxFontSizeMultiplier={1.6} style={styles.schedule} numberOfLines={1}>{c.schedule}</Text> : null}
        </View>
        {c.i_am_member ? <Icon name="check" size={iconSize.toolbar} color="blueText" /> : null}
      </View>
      <View style={styles.bottom}>
        <View style={styles.faces}>
          {c.faces.slice(0, 5).map((f, i) => (
            <Image key={f + i} source={{ uri: f }} style={[styles.face, { marginLeft: i === 0 ? 0 : -10 }]} contentFit="cover" />
          ))}
        </View>
        <Text maxFontSizeMultiplier={1.4} style={styles.members}>{t('clubs.members', { n: c.member_count })}</Text>
      </View>
      {c.next_event ? (
        <View style={styles.next}>
          <Icon name="calendar" size={iconSize.inline} color="clay" />
          <Text maxFontSizeMultiplier={1.6} style={styles.nextText} numberOfLines={1}>
            {t('clubs.next', { title: c.next_event.title, when: formatEventTime(c.next_event.starts_at, intl) })}
          </Text>
        </View>
      ) : null}
    </>
  );
}

export const clubCardStyle = { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, padding: sp.lg, gap: sp.md };

const styles = StyleSheet.create({
  top: { flexDirection: 'row', alignItems: 'center', gap: sp.md },
  tile: {
    width: 52, height: 52, borderRadius: radius.md, ...curve, backgroundColor: colors.blue, alignItems: 'center', justifyContent: 'center',
  },
  name: { ...type.title3, color: colors.ink },
  schedule: { ...type.footnote, fontFamily: fonts.text600, color: colors.muted },
  bottom: { flexDirection: 'row', alignItems: 'center', gap: sp.sm },
  faces: { flexDirection: 'row' },
  face: { width: 28, height: 28, borderRadius: 14, borderWidth: 2, borderColor: colors.card, backgroundColor: colors.line },
  members: { ...type.caption, color: colors.inkSoft },
  next: {
    flexDirection: 'row', alignItems: 'center', gap: sp.sm, backgroundColor: colors.bg, borderRadius: radius.md - 4,
    paddingHorizontal: sp.md, paddingVertical: sp.sm,
  },
  nextText: { flex: 1, ...type.footnote, fontFamily: fonts.text600, color: colors.inkSoft },
});
