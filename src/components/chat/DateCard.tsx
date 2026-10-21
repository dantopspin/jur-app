// "Let's meet": a date suggestion inside the chat (Bumble Suggest a Date / Hinge
// Direct to Date). The other person answers with one tap.
import { useRouter } from 'expo-router';
import React, { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../../i18n';
import { api } from '../../lib/api';
import { formatEventTime } from '../../lib/dates';
import { feedback } from '../../lib/feedback';
import { useSports } from '../../lib/sports';
import { fonts, lightPalette as c, radius, space } from '../../lib/theme';
import type { DatePayload, Message } from '../../lib/types';
import { Icon, sportIconName } from '../Icon';
import { Button } from '../ui';
import { showError } from '../../lib/errors';

export function DateCard({ m, mine, onAnswered }: { m: Message; mine: boolean; onAnswered: () => void }) {
  const { t, intl, sportName } = useI18n();
  const { byCode } = useSports();
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const d = m.payload as DatePayload;
  const sport = d.sport ? byCode[d.sport] : undefined;
  const what = sport ? sportName(sport) : t('date.coffee');

  async function answer(a: 'accepted' | 'declined') {
    setBusy(true);
    try {
      const r = await api.respondDate(m.id, a);
      if (r.ok && a === 'accepted') feedback('match');
      onAnswered();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={[styles.card, mine ? { alignSelf: 'flex-end' } : { alignSelf: 'flex-start' }]}>
      <View style={styles.top}>
        <View style={styles.icon}><Icon name={d.sport ? sportIconName(d.sport) : 'coffee'} size={22} color="#FFFFFF" /></View>
        <View style={{ flex: 1 }}>
          <Text maxFontSizeMultiplier={1.6} style={styles.label}>{t('date.card').toUpperCase()}</Text>
          <Text maxFontSizeMultiplier={1.3} style={styles.what}>{what}</Text>
        </View>
      </View>
      <View style={styles.line}><Icon name="calendar" size={15} color={c.blueMist} /><Text maxFontSizeMultiplier={1.6} style={styles.text}>{formatEventTime(d.when, intl)}</Text></View>
      <View style={styles.line}><Icon name="location" size={15} color={c.blueMist} /><Text maxFontSizeMultiplier={1.6} style={styles.text}>{d.place}</Text></View>
      {d.status === 'pending' && !mine ? (
        <View style={styles.row}>
          <Button title={t('date.no')} variant="ghost" textColor="#FFFFFF" onPress={() => answer('declined')} disabled={busy} style={{ flex: 1 }} />
          <Button title={t('date.yes')} variant="accent" onPress={() => answer('accepted')} loading={busy} style={{ flex: 1 }} />
        </View>
      ) : (
        <View style={[styles.status, d.status === 'accepted' && { backgroundColor: c.gold }]}>
          <Text maxFontSizeMultiplier={1.3} style={[styles.statusText, d.status === 'accepted' && { color: c.ink }]}>
            {d.status === 'accepted' ? t('date.accepted') : d.status === 'declined' ? t('date.declined') : t('date.waiting')}
          </Text>
        </View>
      )}
      {d.event_id ? (
        <Text maxFontSizeMultiplier={1.6} style={styles.link} onPress={() => router.push(`/event/${d.event_id}`)} accessibilityRole="link">{t('date.openEvent')}</Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { width: 260, backgroundColor: c.blue, borderRadius: radius.lg, padding: space(2), gap: 8 },
  top: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  icon: { width: 42, height: 42, borderRadius: 21, backgroundColor: c.blueDeep, alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: c.gold },
  label: { fontFamily: fonts.text800, fontSize: 11, letterSpacing: 1.2, color: c.gold },
  what: { fontFamily: fonts.displayMedium, fontSize: 18, color: '#FFFFFF' },
  line: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  text: { flex: 1, fontFamily: fonts.text600, fontSize: 14, color: '#FFFFFF' },
  row: { flexDirection: 'row', gap: 8, marginTop: 4 },
  status: { alignSelf: 'flex-start', backgroundColor: c.blueDeep, borderRadius: radius.pill, paddingHorizontal: 12, paddingVertical: 5, marginTop: 2 },
  statusText: { fontFamily: fonts.text800, fontSize: 13, color: '#FFFFFF' },
  link: { fontFamily: fonts.text700, fontSize: 14, color: c.blueMist, textDecorationLine: 'underline' },
});
