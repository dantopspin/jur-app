import DateTimePicker, { DateTimePickerAndroid } from '@react-native-community/datetimepicker';
import { useLocalSearchParams, useRouter } from 'expo-router';
import React, { useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Button, Chip, Field, Row, Screen } from '../../src/components/ui';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { almatyToIso, formatEventTime } from '../../src/lib/dates';
import { useSession } from '../../src/lib/session';
import { currentSeason, useSports } from '../../src/lib/sports';
import { colors, fonts, radius, space, useTheme } from '../../src/lib/theme';
import { showError } from '../../src/lib/errors';

/** Hosts only (enforced by the database too). */
export default function NewEvent() {
  const { t, sportName, intl } = useI18n();
  const { raw } = useTheme();
  const { sports } = useSports();
  const { profile } = useSession();
  const router = useRouter();
  const { club } = useLocalSearchParams<{ club?: string }>();
  const season = currentSeason();
  const [title, setTitle] = useState('');
  const [sport, setSport] = useState<string | null>(null);
  // Native date and time pickers. The phone's clock is Kazakhstan time for our
  // hosts; we keep the wall-clock values and store them as Almaty time.
  const [when, setWhen] = useState<Date>(() => {
    const d = new Date(Date.now() + 2 * 86400_000);
    d.setHours(9, 0, 0, 0);
    return d;
  });
  const pad = (n: number) => String(n).padStart(2, '0');
  const date = `${when.getFullYear()}-${pad(when.getMonth() + 1)}-${pad(when.getDate())}`;
  const time = `${pad(when.getHours())}:${pad(when.getMinutes())}`;
  const [after, setAfter] = useState('');
  const [duration, setDuration] = useState('90');
  const [capacity, setCapacity] = useState('30');
  const [price, setPrice] = useState('0');
  const [meeting, setMeeting] = useState('');
  const [description, setDescription] = useState('');
  const [busy, setBusy] = useState(false);

  const ordered = [...sports].sort((a, b) =>
    Number(b.season === season || b.season === 'all') - Number(a.season === season || a.season === 'all'));

  async function publish() {
    const startsAt = almatyToIso(date, time);
    if (!profile || !sport || title.trim().length < 3 || meeting.trim().length < 3 || !startsAt
        || new Date(startsAt).getTime() < Date.now()) {
      Alert.alert(t('events.invalid'));
      return;
    }
    setBusy(true);
    try {
      const { id } = await api.createEvent({
        host_id: profile.id,
        city: profile.city,
        sport_code: sport,
        title: title.trim(),
        description: description.trim() || null,
        meeting_point: meeting.trim(),
        starts_at: startsAt,
        duration_min: Math.max(15, Math.min(720, Number(duration) || 90)),
        capacity: Math.max(2, Math.min(500, Number(capacity) || 30)),
        price_kzt: Math.max(0, Number(price) || 0),
        after_text: after.trim() || null,
        club_id: club ?? null,
      });
      router.replace(`/event/${id}`);
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen edges={['bottom']}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ padding: space(2), gap: space(2), paddingBottom: space(6) }} keyboardShouldPersistTaps="handled">
          <Field label={t('events.fieldTitle')} value={title} onChangeText={setTitle} maxLength={80} />
          <View style={{ gap: 6 }}>
            <Field label={t('events.fieldSport')} editable={false} value={sport ? sportName(sports.find((s) => s.code === sport)!) : ''} />
            <Row style={{ flexWrap: 'wrap' }}>
              {ordered.map((s) => (
                <Chip key={s.code} label={sportName(s)} selected={sport === s.code} onPress={() => setSport(s.code)} />
              ))}
            </Row>
          </View>
          {Platform.OS === 'ios' ? (
            <View style={styles.pickerRow}>
              <Text maxFontSizeMultiplier={1.6} style={styles.pickerLabel}>{t('events.fieldDate')}</Text>
              <DateTimePicker value={when} mode="datetime" display="compact" minimumDate={new Date()} minuteInterval={5}
                accentColor={raw.blueText} onChange={(_e, d) => d && setWhen(d)} />
            </View>
          ) : (
            <Pressable style={styles.pickerRow} accessibilityRole="button" onPress={() => {
              DateTimePickerAndroid.open({
                value: when, mode: 'date', minimumDate: new Date(),
                onChange: (_e, d) => {
                  if (!d) return;
                  DateTimePickerAndroid.open({
                    value: d, mode: 'time', is24Hour: true,
                    onChange: (_e2, tm) => tm && setWhen(tm),
                  });
                },
              });
            }}>
              <Text maxFontSizeMultiplier={1.6} style={styles.pickerLabel}>{t('events.fieldDate')}</Text>
              <Text maxFontSizeMultiplier={1.6} style={styles.pickerValue}>{formatEventTime(almatyToIso(date, time) ?? when.toISOString(), intl)}</Text>
            </Pressable>
          )}
          <Row>
            <View style={{ flex: 1 }}>
              <Field label={t('events.fieldDuration')} value={duration} onChangeText={setDuration} keyboardType="number-pad" />
            </View>
            <View style={{ flex: 1 }}>
              <Field label={t('events.fieldCapacity')} value={capacity} onChangeText={setCapacity} keyboardType="number-pad" />
            </View>
          </Row>
          <Field label={t('events.fieldPrice')} value={price} onChangeText={setPrice} keyboardType="number-pad" />
          <Field label={t('events.fieldMeeting')} value={meeting} onChangeText={setMeeting} maxLength={160} />
          <Field label={t('events.fieldDescription')} value={description} onChangeText={setDescription} multiline maxLength={1500} />
          <Field label={t('dastarkhan.fieldAfter')} value={after} onChangeText={setAfter} maxLength={80} />
          <Button title={t('events.publish')} variant="accent" onPress={publish} loading={busy} />
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  pickerRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: space(1),
    backgroundColor: colors.card, borderRadius: radius.md, borderCurve: 'continuous',
    paddingHorizontal: 16, paddingVertical: 10, minHeight: 50,
  },
  pickerLabel: { fontFamily: fonts.text700, fontSize: 15, color: colors.inkSoft },
  pickerValue: { fontFamily: fonts.text600, fontSize: 16, color: colors.blueText },
});
