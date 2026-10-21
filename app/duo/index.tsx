// Double date: team up with a friend (by member number), then meet another pair.
import { Image } from 'expo-image';
import { useFocusEffect, useRouter } from 'expo-router';
import React, { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Icon } from '../../src/components/Icon';
import { toast } from '../../src/components/Toast';
import { Button, ErrorState, Field, Loading, P, Row, SectionLabel } from '../../src/components/ui';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { colors, curve, fonts, iconSize, layout, memberNo, radius, sp, type } from '../../src/lib/theme';
import type { DuoState, ProfileCard } from '../../src/lib/types';
import { showError } from '../../src/lib/errors';

function Faces({ people, size = 56 }: { people: ProfileCard[]; size?: number }) {
  return (
    <View style={{ flexDirection: 'row' }}>
      {people.map((p, i) => (
        <Image key={p.id} source={{ uri: p.photos[0] }} contentFit="cover"
          style={{ width: size, height: size, borderRadius: size / 2, marginLeft: i ? -size / 4 : 0, borderWidth: 2, borderColor: colors.card as string, backgroundColor: colors.line as string }} />
      ))}
    </View>
  );
}

export default function Duo() {
  const { t } = useI18n();
  const router = useRouter();
  const [s, setS] = useState<DuoState | null>(null);
  const [no, setNo] = useState('');
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const load = useCallback(async () => {
    try { setFailed(false); setS(await api.myDuo()); } catch { setFailed(true); }
  }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  async function run(fn: () => Promise<{ ok: boolean; error?: string } | void>) {
    setBusy(true);
    try {
      const r = await fn();
      if (r && !r.ok) {
        Alert.alert(r.error === 'not_found' ? t('duo.errors_not_found') : r.error === 'friend_busy' ? t('duo.errors_busy')
          : r.error === 'already_in_duo' ? t('duo.errors_already') : t('common.error'));
      } else toast(t('states.sent'));
      await load();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  if (!s && failed) return <ErrorState onRetry={load} />;
  if (!s) return <Loading />;
  const duo = s.duo;

  return (
    <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 }}>
      <View style={styles.hero}>
        <Icon name="duo" size={56} color="blueText" weight="regular" />
        <P style={{ textAlign: 'center' }}>{t('duo.intro')}</P>
      </View>

      {s.invites.length > 0 && !duo?.status?.startsWith('active') ? (
        <View>
          <SectionLabel>{t('duo.invites')}</SectionLabel>
          {s.invites.map((inv) => (
            <View key={inv.id} style={styles.card}>
              <Faces people={[inv.from]} size={44} />
              <Text maxFontSizeMultiplier={1.6} style={styles.cardTitle}>{inv.from.name} <Text maxFontSizeMultiplier={1.6} style={styles.no}>{memberNo(inv.from.member_no)}</Text></Text>
              <Row style={{ alignSelf: 'stretch' }}>
                <Button title={t('duo.decline')} variant="secondary" compact onPress={() => run(() => api.duoRespond(inv.id, false))} style={{ flex: 1 }} disabled={busy} />
                <Button title={t('duo.accept')} compact onPress={() => run(() => api.duoRespond(inv.id, true))} style={{ flex: 1 }} disabled={busy} />
              </Row>
            </View>
          ))}
        </View>
      ) : null}

      {!duo ? (
        <View>
          <SectionLabel>{t('duo.invite')}</SectionLabel>
          <Row>
            <View style={{ flex: 1 }}>
              <Field value={no} onChangeText={(v) => setNo(v.replace(/\D/g, ''))} placeholder={t('duo.memberNo')} keyboardType="number-pad"
                maxLength={7} accessibilityLabel={t('duo.memberNo')} />
            </View>
            <Button title={t('duo.send')} compact onPress={() => run(() => api.duoInvite(Number(no)))} disabled={!no} loading={busy} />
          </Row>
        </View>
      ) : duo.status === 'pending' ? (
        <View style={styles.card}>
          <Faces people={[duo.partner]} />
          <Text maxFontSizeMultiplier={1.6} style={styles.cardTitle}>{t('duo.waiting', { name: duo.partner.name })}</Text>
          <Button title={t('duo.cancel')} variant="secondary" compact onPress={() => run(() => api.duoLeave())} disabled={busy} style={{ alignSelf: 'stretch' }} />
        </View>
      ) : (
        <>
          <View style={styles.card}>
            <Faces people={[duo.partner]} />
            <Text maxFontSizeMultiplier={1.6} style={styles.cardTitle}>{t('duo.with', { name: duo.partner.name })}</Text>
            <Button title={t('duo.find')} onPress={() => router.push('/duo/find')} style={{ alignSelf: 'stretch' }} />
          </View>
          {s.matches.length > 0 ? (
            <View>
              <SectionLabel>{t('duo.chats')}</SectionLabel>
              <View style={styles.group}>
              {s.matches.map((m) => (
                <Pressable key={m.id} style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.line }]} onPress={() => router.push(`/duo/chat/${m.id}`)} accessibilityRole="button">
                  <Faces people={m.other} size={44} />
                  <View style={{ flex: 1 }}>
                    <Text maxFontSizeMultiplier={1.6} style={styles.rowTitle}>{m.other.map((o) => o.name).join(' & ')}</Text>
                    <Text maxFontSizeMultiplier={1.6} style={styles.rowSub} numberOfLines={1}>{m.last_message?.body ?? t('duo.matched')}</Text>
                  </View>
                  <Icon name="forward" size={iconSize.inline} color="hint" />
                </Pressable>
              ))}
              </View>
            </View>
          ) : null}
          <Button title={t('duo.leave')} variant="danger" compact onPress={() => run(() => api.duoLeave())} disabled={busy} />
        </>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  hero: { alignItems: 'center', gap: sp.md, paddingTop: sp.sm },
  card: { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, padding: sp.lg, gap: sp.md, alignItems: 'center' },
  cardTitle: { ...type.title3, color: colors.ink, textAlign: 'center' },
  no: { fontFamily: fonts.text700, fontSize: 13, color: colors.muted, fontVariant: ['tabular-nums'] },
  group: { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, overflow: 'hidden' },
  row: { flexDirection: 'row', alignItems: 'center', gap: sp.md, paddingHorizontal: sp.lg, paddingVertical: sp.md },
  rowTitle: { ...type.headline, color: colors.ink },
  rowSub: { ...type.footnote, color: colors.muted },
});
