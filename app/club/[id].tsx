// A club: who runs it, when it meets, who's in it, what's next, and its chat.
import { Image } from 'expo-image';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import React, { useCallback, useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { Ridge } from '../../src/components/Brand';
import { Icon, sportIconName } from '../../src/components/Icon';
import { PreviewLink } from '../../src/components/PreviewLink';
import { ShareCardButton } from '../../src/components/ShareCard';
import { Button, Empty, Loading, P } from '../../src/components/ui';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { formatEventTime } from '../../src/lib/dates';
import { tick } from '../../src/lib/haptics';
import { snowOnHorizon } from '../../src/lib/season';
import { useSession } from '../../src/lib/session';
import { useSports } from '../../src/lib/sports';
import { colors, fontScale, fonts, lightPalette, radius, space } from '../../src/lib/theme';
import type { Club } from '../../src/lib/types';
import { showError } from '../../src/lib/errors';

export default function ClubScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t, intl, sportName, cityName } = useI18n();
  const { byCode } = useSports();
  const { profile } = useSession();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const [c, setC] = useState<Club | null | undefined>(undefined);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => setC(await api.club(id)), [id]);
  useEffect(() => { load().catch(() => setC(null)); }, [load]);

  if (c === undefined) return <Loading />;
  if (c === null) return <Empty title={t('common.error')} />;

  const sport = byCode[c.sport_code];

  async function toggle() {
    if (!c) return;
    setBusy(true);
    try {
      if (c.i_am_member) await api.leaveClub(c.id);
      else { await api.joinClub(c.id); tick(); }
      await load();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Stack.Screen options={{
        title: sport ? sportName(sport) : '',
        headerRight: () => (
          <ShareCardButton kind="club" title={c.name} line={c.schedule ?? cityName(c.city)} code={profile?.referral_code ?? ''} />
        ),
      }} />
      <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ paddingBottom: space(6) }}>
        <View style={styles.hero}>
          <View style={styles.heroIcon}><Icon name={sportIconName(c.sport_code)} size={40} color="#FFFFFF" /></View>
          <Text maxFontSizeMultiplier={fontScale.display} style={styles.name}>{c.name}</Text>
          {c.schedule ? <Text maxFontSizeMultiplier={1.6} style={styles.schedule}>{c.schedule}</Text> : null}
          <Ridge width={width} height={56} fill={lightPalette.blueDeep} snow={snowOnHorizon()} style={styles.ridge} />
        </View>

        <View style={styles.body}>
          <View style={styles.row}>
            <View style={styles.faces}>
              {c.faces.map((f, i) => (
                <Image key={f + i} source={{ uri: f }} style={[styles.face, { marginLeft: i === 0 ? 0 : -12 }]} contentFit="cover" />
              ))}
            </View>
            <Text maxFontSizeMultiplier={1.6} style={styles.members}>{t('clubs.members', { n: c.member_count })}</Text>
          </View>

          {c.organizer ? (
            <Pressable style={styles.organizer} onPress={() => router.push(`/profile/${c.organizer!.id}`)} accessibilityRole="button">
              {c.organizer.photo ? <Image source={{ uri: c.organizer.photo }} style={styles.orgPhoto} contentFit="cover" /> : null}
              <Text maxFontSizeMultiplier={1.6} style={styles.orgText}>{t('clubs.organizer', { name: c.organizer.name })}</Text>
            </Pressable>
          ) : null}

          {c.description ? <P>{c.description}</P> : null}

          {!c.i_am_organizer && (
            <Button title={c.i_am_member ? t('clubs.leave') : t('clubs.join')} variant={c.i_am_member ? 'secondary' : 'accent'}
              loading={busy} onPress={toggle} />
          )}
          {c.i_am_member && (
            <Button title={t('clubs.chat')} icon={<Icon name="people" size={18} color="white" />}
              onPress={() => router.push(`/club/chat/${c.id}`)} />
          )}
          {c.i_am_organizer && (
            <Button title={t('clubs.newEvent')} variant="secondary" icon={<Icon name="add" size={18} color="blueText" />}
              onPress={() => router.push(`/event/new?club=${c.id}`)} />
          )}

          <Text maxFontSizeMultiplier={1.6} style={styles.section}>{t('clubs.upcoming')}</Text>
          {(c.events ?? []).length === 0 ? <P muted>{t('clubs.noEvents')}</P> : null}
          {(c.events ?? []).map((e) => (
            <PreviewLink key={e.id} href={`/event/${e.id}`} cancelLabel={t('common.cancel')} accessibilityLabel={e.title}
              style={({ pressed }) => [styles.event, pressed && { opacity: 0.92 }]}>
              <View style={{ flex: 1, gap: 2 }}>
                <Text maxFontSizeMultiplier={1.6} style={styles.when}>{formatEventTime(e.starts_at, intl)}</Text>
                <Text maxFontSizeMultiplier={1.6} style={styles.eventTitle}>{e.title}</Text>
                <Text maxFontSizeMultiplier={1.6} style={styles.meta} numberOfLines={1}>{e.meeting_point}</Text>
              </View>
              {e.i_am_going ? <Icon name="check" size={22} color="gold" /> : <Icon name="forward" size={14} color="hint" weight="bold" />}
            </PreviewLink>
          ))}
        </View>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  hero: {
    backgroundColor: lightPalette.blue, alignItems: 'center', paddingTop: space(3), paddingBottom: space(7),
    paddingHorizontal: space(3), gap: space(1), overflow: 'hidden',
  },
  heroIcon: {
    width: 84, height: 84, borderRadius: 42, backgroundColor: lightPalette.blueDeep, alignItems: 'center',
    justifyContent: 'center', borderWidth: 2, borderColor: lightPalette.gold,
  },
  name: { fontFamily: fonts.display, fontSize: 26, lineHeight: 32, color: '#FFFFFF', textAlign: 'center' },
  schedule: { fontFamily: fonts.text700, fontSize: 15, color: lightPalette.gold, textAlign: 'center' },
  ridge: { position: 'absolute', left: 0, bottom: -1 },
  body: { padding: space(2), gap: space(2) },
  row: { flexDirection: 'row', alignItems: 'center', gap: space(1) },
  faces: { flexDirection: 'row' },
  face: { width: 36, height: 36, borderRadius: 18, borderWidth: 2, borderColor: colors.bg, backgroundColor: colors.line },
  members: { fontFamily: fonts.text700, fontSize: 13, color: colors.inkSoft },
  organizer: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  orgPhoto: { width: 28, height: 28, borderRadius: 14, backgroundColor: colors.line },
  orgText: { fontFamily: fonts.text600, fontSize: 15, color: colors.ink },
  section: { fontSize: 12, lineHeight: 16, fontFamily: fonts.text800, color: colors.inkSoft, textTransform: 'uppercase', letterSpacing: 0.8, marginTop: space(1) },
  event: {
    flexDirection: 'row', alignItems: 'center', gap: space(1.5), backgroundColor: colors.card, borderRadius: radius.lg,
    borderCurve: 'continuous', padding: space(2),
  },
  when: { fontSize: 12, fontFamily: fonts.text800, color: colors.accentText, textTransform: 'uppercase', letterSpacing: 0.6 },
  eventTitle: { fontFamily: fonts.displayMedium, fontSize: 16, lineHeight: 22, color: colors.ink },
  meta: { fontFamily: fonts.text500, fontSize: 13, lineHeight: 18, color: colors.muted },
});
