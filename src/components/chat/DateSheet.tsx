// Compose a date suggestion: a shared sport (or coffee), a time and a place —
// or one of the upcoming events. Native page sheet on iOS.
import DateTimePicker, { DateTimePickerAndroid } from '@react-native-community/datetimepicker';
import React, { useEffect, useState } from 'react';
import { Alert, KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useI18n } from '../../i18n';
import { api } from '../../lib/api';
import { formatEventTime } from '../../lib/dates';
import { useSports } from '../../lib/sports';
import { colors, fonts, iconSize, radius, sp, type, useTheme } from '../../lib/theme';
import { SheetHeader } from '../HeaderButton';
import type { EventItem } from '../../lib/types';
import { Icon, sportIconName } from '../Icon';
import { Button, Chip, Field, Row } from '../ui';
import { showError } from '../../lib/errors';

export function DateSheet({
  visible, matchId, sportCodes, onClose, onSent,
}: { visible: boolean; matchId: string; sportCodes: string[]; onClose: () => void; onSent: () => void }) {
  const { t, intl, sportName } = useI18n();
  const { byCode } = useSports();
  const { raw } = useTheme();
  const [sport, setSport] = useState<string | null>(sportCodes[0] ?? null);
  const [when, setWhen] = useState(() => { const d = new Date(Date.now() + 2 * 86400_000); d.setHours(9, 0, 0, 0); return d; });
  const [place, setPlace] = useState('');
  const [events, setEvents] = useState<EventItem[]>([]);
  const [busy, setBusy] = useState(false);
  const ios = Platform.OS === 'ios';

  useEffect(() => {
    if (visible) api.upcomingEvents().then((e) => setEvents(e.filter((x) => new Date(x.starts_at) > new Date()).slice(0, 5))).catch(() => {});
  }, [visible]);

  async function send(eventId?: string) {
    if (!eventId && (place.trim().length < 2 || when.getTime() < Date.now())) { Alert.alert(t('date.invalid')); return; }
    setBusy(true);
    try {
      const r = await api.proposeDate(matchId, eventId ? { eventId } : { sport, when: when.toISOString(), place: place.trim() });
      if (!r.ok) { Alert.alert(t('date.invalid')); return; }
      onSent();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal visible={visible} animationType="slide" presentationStyle={ios ? 'pageSheet' : undefined} transparent={!ios} onRequestClose={onClose}>
      <KeyboardAvoidingView behavior={ios ? 'padding' : undefined} style={{ flex: 1, backgroundColor: colors.bg }}>
        <SafeAreaView edges={['top', 'bottom']} style={{ flex: 1 }}>
          <SheetHeader title={t('date.title')} cancelLabel={t('common.cancel')} onCancel={onClose}
            action={t('date.sendShort')} onAction={() => send()} actionDisabled={busy} />
          <ScrollView contentContainerStyle={{ padding: sp.lg, gap: sp.sm, paddingBottom: sp.xxl }} keyboardShouldPersistTaps="handled">
            <Text maxFontSizeMultiplier={1.6} style={styles.sub}>{t('date.sub')}</Text>
            <Text maxFontSizeMultiplier={1.6} style={[styles.label, styles.gapTop]}>{t('date.sport')}</Text>
            <Row style={{ flexWrap: 'wrap' }}>
              {sportCodes.map((c) => (
                <Chip key={c} label={byCode[c] ? sportName(byCode[c]) : c} selected={sport === c} onPress={() => setSport(c)} />
              ))}
              <Chip label={t('date.coffee')} selected={sport === null} onPress={() => setSport(null)} />
            </Row>
            <Text maxFontSizeMultiplier={1.6} style={[styles.label, styles.gapTop]}>{t('date.when')}</Text>
            {ios ? (
              <DateTimePicker value={when} mode="datetime" display="compact" minimumDate={new Date()} minuteInterval={15}
                accentColor={raw.blueText} onChange={(_e, d) => d && setWhen(d)} style={{ alignSelf: 'flex-start' }} />
            ) : (
              <Pressable style={styles.picker} onPress={() => DateTimePickerAndroid.open({
                value: when, mode: 'date', minimumDate: new Date(),
                onChange: (_e, d) => d && DateTimePickerAndroid.open({ value: d, mode: 'time', is24Hour: true, onChange: (_e2, tm) => tm && setWhen(tm) }),
              })}>
                <Text maxFontSizeMultiplier={1.6} style={styles.pickerText}>{formatEventTime(when.toISOString(), intl)}</Text>
              </Pressable>
            )}
            <View style={styles.gapTop} />
            <Field label={t('date.where')} value={place} onChangeText={setPlace} placeholder={t('date.wherePlaceholder')} maxLength={120} />
            <Button title={t('date.send')} onPress={() => send()} loading={busy} style={styles.gapTop} />

            {events.length > 0 && (
              <>
                <Text maxFontSizeMultiplier={1.6} style={[styles.label, { marginTop: sp.xl }]}>{t('date.orEvent')}</Text>
                {events.map((e) => (
                  <Pressable key={e.id} style={styles.event} onPress={() => send(e.id)} accessibilityRole="button" disabled={busy}>
                    <View style={styles.eventIcon}><Icon name={sportIconName(e.sport_code)} size={iconSize.row} color="blueText" /></View>
                    <View style={{ flex: 1 }}>
                      <Text maxFontSizeMultiplier={1.6} style={styles.eventTitle}>{e.title}</Text>
                      <Text maxFontSizeMultiplier={1.6} style={styles.eventMeta}>{formatEventTime(e.starts_at, intl)} · {e.meeting_point}</Text>
                    </View>
                    <Icon name="forward" size={iconSize.inline} color="hint" />
                  </Pressable>
                ))}
              </>
            )}
          </ScrollView>
        </SafeAreaView>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  sub: { ...type.callout, color: colors.inkSoft },
  label: { ...type.overline, color: colors.inkSoft },
  gapTop: { marginTop: sp.lg },
  picker: { backgroundColor: colors.card, borderRadius: radius.md, minHeight: 50, paddingHorizontal: sp.lg, justifyContent: 'center' },
  pickerText: { ...type.body, fontFamily: fonts.text600, color: colors.blueText },
  event: { flexDirection: 'row', alignItems: 'center', gap: sp.md, backgroundColor: colors.card, borderRadius: radius.md, padding: sp.md, minHeight: 60 },
  eventIcon: { width: 36, height: 36, borderRadius: 8, backgroundColor: colors.blueTint, alignItems: 'center', justifyContent: 'center' },
  eventTitle: { ...type.headline, fontSize: 15, color: colors.ink },
  eventMeta: { ...type.footnote, color: colors.muted },
});
