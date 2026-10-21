// Apply to start a club (Ritmo's "start a Run Club", for every sport).
// A moderator approves in the SQL editor: select approve_club_application('<id>', 'Saturdays 08:00 · Medeu');
import { useRouter } from 'expo-router';
import React, { useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, ScrollView, View } from 'react-native';
import { Button, Chip, Field, P, Row } from '../../src/components/ui';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { useSession } from '../../src/lib/session';
import { currentSeason, useSports } from '../../src/lib/sports';
import { colors, space } from '../../src/lib/theme';
import { showError } from '../../src/lib/errors';

export default function ApplyClub() {
  const { t, sportName } = useI18n();
  const { sports } = useSports();
  const { profile } = useSession();
  const router = useRouter();
  const season = currentSeason();
  const [sport, setSport] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [about, setAbout] = useState('');
  const [busy, setBusy] = useState(false);
  const ordered = [...sports].sort((a, b) =>
    Number(b.season === season || b.season === 'all') - Number(a.season === season || a.season === 'all'));

  async function send() {
    if (!profile || !sport) return;
    setBusy(true);
    try {
      const r = await api.applyClub(profile.city, sport, name, about);
      Alert.alert(r.ok ? t('clubs.sent') : r.error === 'pending_exists' ? t('clubs.pending') : t('common.error'));
      if (r.ok || r.error === 'pending_exists') router.back();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1, backgroundColor: colors.bg }}>
      <ScrollView contentContainerStyle={{ padding: space(2), gap: space(2), paddingBottom: space(6) }} keyboardShouldPersistTaps="handled">
        <P muted>{t('clubs.applyIntro')}</P>
        <View style={{ gap: space(1) }}>
          <Row style={{ flexWrap: 'wrap' }}>
            {ordered.map((s) => (
              <Chip key={s.code} label={sportName(s)} selected={sport === s.code} onPress={() => setSport(s.code)} />
            ))}
          </Row>
        </View>
        <Field label={t('clubs.fieldName')} value={name} onChangeText={setName} maxLength={60} />
        <Field label={t('clubs.fieldAbout')} value={about} onChangeText={setAbout} multiline maxLength={600} />
        <Button title={t('clubs.send')} variant="accent" onPress={send} loading={busy}
          disabled={!sport || name.trim().length < 3 || about.trim().length < 10} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
