import { Image } from 'expo-image';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { ShareCardButton } from '../../src/components/ShareCard';
import { useSheet } from '../../src/components/Sheet';
import { useSession } from '../../src/lib/session';
import { CircleMoment } from '../../src/components/CircleMoment';
import { Icon, sportIconName, type IconName } from '../../src/components/Icon';
import { Button, Card, ErrorState, H1, Loading, P, Screen, SectionLabel, T } from '../../src/components/ui';
import { useI18n, type TKey } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { formatEventTime } from '../../src/lib/dates';
import { endEventActivity, syncEventActivities } from '../../src/lib/liveActivity';
import { useSports } from '../../src/lib/sports';
import { bibNumber, border, colors, curve, fonts, iconSize, layout, radius, sp, type } from '../../src/lib/theme';
import type { EventItem, ProfileCard } from '../../src/lib/types';
import { showError } from '../../src/lib/errors';

export default function EventScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t, intl, sportName, cityName } = useI18n();
  const { byCode } = useSports();
  const router = useRouter();
  const [e, setE] = useState<EventItem | null | undefined>(undefined);
  const [people, setPeople] = useState<ProfileCard[]>([]);
  const [busy, setBusy] = useState(false);
  const [circle, setCircle] = useState(false);
  const sheet = useSheet();
  const { profile } = useSession();

  const load = useCallback(async () => {
    const ev = await api.event(id);
    setE(ev);
    if (ev) syncEventActivities([ev], (place) => t('live.meet', { place }));
    if (ev?.i_am_going) setPeople(await api.eventPeople(id));
    else setPeople([]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  useEffect(() => { load().catch(() => setE(null)); }, [load]);

  if (e === undefined) return <Screen edges={['bottom']}><Loading /></Screen>;
  if (e === null) return <Screen edges={['bottom']}><ErrorState onRetry={() => { setE(undefined); load().catch(() => setE(null)); }} /></Screen>;

  const sport = byCode[e.sport_code];
  const start = new Date(e.starts_at).getTime();
  const end = start + e.duration_min * 60_000;
  const now = Date.now();
  const past = now > end;
  const started = now > start;
  const checkInOpen = now >= start - 30 * 60_000 && now <= end;
  const full = e.going_count >= e.capacity;

  // Gold wristband = open to meeting someone; blue = here for the sport.
  function chooseWristband() {
    sheet({
      title: t('wristband.title'),
      cancelLabel: t('common.cancel'),
      options: [
        { label: t('wristband.gold'), onPress: () => run(() => api.joinEvent(id, true)) },
        { label: t('wristband.blue'), onPress: () => run(() => api.joinEvent(id, false)) },
      ],
    });
  }

  async function run(fn: () => Promise<{ ok: boolean; error?: string } | void>) {
    setBusy(true);
    try {
      const r = await fn();
      if (r && !r.ok) {
        const msg = r.error === 'full' ? t('events.full') : r.error === 'started' ? t('events.started')
          : r.error === 'not_now' ? t('events.notNow') : t('common.error');
        Alert.alert(msg);
      }
      await load();
    } catch (err) {
      showError(t, err);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen edges={['bottom']}>
      <Stack.Screen options={{
        title: sport ? sportName(sport) : '',
        headerRight: () => (
          <ShareCardButton kind="going" title={e.title} code={profile?.referral_code ?? ''}
            line={`${formatEventTime(e.starts_at, intl)} · ${e.meeting_point}`} />
        ),
      }} />
      <ScrollView contentContainerStyle={{ padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 }}>
        {e.cover_url ? <Image source={{ uri: e.cover_url }} style={styles.cover} contentFit="cover" /> : null}
        <View style={{ gap: sp.sm }}>
          <Text maxFontSizeMultiplier={1.4} style={styles.when}>{formatEventTime(e.starts_at, intl)} · {e.duration_min} min</Text>
          <H1>{e.title}</H1>
          {e.host ? <T variant="callout">{t('events.host', { name: e.host.name })}</T> : null}
          {e.club ? (
            <Pressable style={styles.clubLink} onPress={() => router.push(`/club/${e.club!.id}`)} accessibilityRole="button">
              <Icon name="people" size={iconSize.row} color="blueText" />
              <Text maxFontSizeMultiplier={1.6} style={styles.clubLinkText} numberOfLines={1}>{e.club.name}</Text>
              <Icon name="forward" size={iconSize.inline} color="blueText" />
            </Pressable>
          ) : null}
        </View>

        <Card style={{ paddingVertical: 0, paddingRight: 0 }}>
          <Info icon="location" label={t('events.meetingPoint')} value={`${e.meeting_point}, ${cityName(e.city)}`} first />
          <Info icon={sportIconName(e.sport_code)} label={t('events.level')} value={t(`levels.${e.level}` as TKey)} />
          <Info icon="ticket" label={t('events.price')} value={e.price_kzt > 0 ? t('events.payAtVenue', { price: e.price_kzt.toLocaleString(intl) }) : t('common.free')} />
          <Info icon="people" label={t('events.whoGoing')} value={t('events.going', { n: e.going_count, cap: e.capacity })} />
          {e.after_text ? <Info icon="tea" label={t('dastarkhan.after')} value={e.after_text} /> : null}
        </Card>

        {e.description ? <P>{e.description}</P> : null}

        {e.cancelled ? null : !e.i_am_going ? (
          <Button title={full ? t('events.full') : started ? t('events.started') : t('events.join')}
            variant="accent" disabled={full || started} loading={busy} onPress={chooseWristband} />
        ) : (
          <View style={{ gap: sp.sm }}>
            {checkInOpen && (
              <Button title={e.i_checked_in ? `✓ ${t('events.checkedIn')}` : t('events.checkIn')}
                variant="accent" disabled={e.i_checked_in} loading={busy} onPress={() => run(async () => {
                  const r = await api.checkIn(id);
                  if (r.ok) {
                    setCircle(true); // plays the check-in sound and haptic
                    endEventActivity(e, t('circle.joinedTitle'));
                  }
                  return r;
                })} />
            )}
            {!started && (
              <Button title={t('events.leave')} variant="secondary" loading={busy} onPress={() => run(async () => {
                await api.leaveEvent(id);
                endEventActivity(e, t('events.leave'));
              })} />
            )}
            {!checkInOpen && !past && <T variant="callout" tone="good" style={{ textAlign: 'center' }}>✓ {t('events.youreIn')}</T>}
            {!past && (
              <View style={styles.band}>
                <View style={[styles.bandDot, { backgroundColor: e.i_am_open ? colors.gold : colors.blue }]} />
                <View style={{ flex: 1, gap: sp.xxs }}>
                  <Text maxFontSizeMultiplier={1.6} style={styles.bandTitle}>{t('wristband.toggle')}</Text>
                  <Text maxFontSizeMultiplier={1.6} style={styles.bandHint}>{t('wristband.toggleHint')}</Text>
                </View>
                <Switch value={!!e.i_am_open} onValueChange={(v) => run(() => api.setOpenToMeet(id, v))}
                  trackColor={{ true: colors.gold, false: colors.line }} />
              </View>
            )}
          </View>
        )}

        <View style={{ gap: sp.sm }}>
          <SectionLabel style={{ marginBottom: 0 }}>{past ? t('events.peopleMet') : t('events.whoGoing')}</SectionLabel>
          {e.going_count > 0 ? (
            <View style={styles.openRow}>
              <View style={[styles.bandDot, { backgroundColor: colors.gold }]} />
              <Text maxFontSizeMultiplier={1.6} style={styles.openText}>{t('wristband.openCount', { n: e.open_count, total: e.going_count })}</Text>
            </View>
          ) : null}
          {!e.i_am_going ? (
            <P muted>{t('events.joinToSee')}</P>
          ) : (
            <View style={styles.grid}>
              {people.map((p) => (
                <Pressable key={p.id} style={styles.person} onPress={() => router.push(`/profile/${p.id}?from=event`)}>
                  <Image source={{ uri: p.photos[0] }} contentFit="cover"
                    style={[styles.personPhoto, { borderColor: p.open_to_meet ? colors.gold : colors.blue }]}
                    accessibilityLabel={`${p.name}, ${p.open_to_meet ? t('wristband.goldShort') : t('wristband.blueShort')}`} />
                  <Text maxFontSizeMultiplier={1.3} style={styles.personNum}>№{bibNumber(p.member_no)}</Text>
                  <Text maxFontSizeMultiplier={1.4} style={styles.personName} numberOfLines={1}>
                    {p.name}
                  </Text>
                  {p.my_swipe === 'like' || p.my_swipe === 'super' ? (
                    <View style={styles.liked}><Icon name="check" size={iconSize.row} color="blueText" /></View>
                  ) : null}
                </Pressable>
              ))}
            </View>
          )}
        </View>
      </ScrollView>
      <CircleMoment visible={circle} sportCode={e.sport_code} onClose={() => setCircle(false)}
        share={{ title: e.title, line: formatEventTime(e.starts_at, intl), code: profile?.referral_code ?? '', member: profile?.member_no }} />
    </Screen>
  );
}

function Info({ label, value, icon, first }: { label: string; value: string; icon: IconName; first?: boolean }) {
  return (
    <View style={styles.info}>
      <View style={styles.infoIcon}><Icon name={icon} size={iconSize.row} color="blueText" /></View>
      <View style={[styles.infoText, !first && styles.infoSep]}>
        <Text maxFontSizeMultiplier={1.6} style={styles.infoLabel}>{label}</Text>
        <Text maxFontSizeMultiplier={1.8} style={styles.infoValue}>{value}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  cover: { width: '100%', aspectRatio: 16 / 9, borderRadius: radius.lg, ...curve, backgroundColor: colors.line },
  when: { ...type.overline, fontSize: 13, color: colors.accentText },
  info: { flexDirection: 'row', gap: sp.md, alignItems: 'center' },
  infoIcon: {
    width: layout.tile, height: layout.tile, borderRadius: 7, backgroundColor: colors.blueTint, alignItems: 'center', justifyContent: 'center',
  },
  infoText: { flex: 1, gap: sp.xxs, paddingVertical: sp.md, paddingRight: sp.lg },
  infoSep: { borderTopWidth: border.hair, borderTopColor: colors.line },
  infoLabel: { ...type.footnote, color: colors.muted },
  infoValue: { ...type.body, fontFamily: fonts.text600, color: colors.ink },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: sp.md },
  person: { width: 96, gap: sp.xxs },
  liked: { position: 'absolute', top: 6, right: 6, backgroundColor: colors.card, borderRadius: 12, padding: 2 },
  personPhoto: { width: 96, height: 120, borderRadius: radius.md, ...curve, backgroundColor: colors.line, borderWidth: 2.5, marginBottom: sp.xs },
  band: {
    flexDirection: 'row', alignItems: 'center', gap: sp.md, backgroundColor: colors.card, borderRadius: radius.lg, ...curve,
    padding: sp.lg,
  },
  bandDot: { width: 14, height: 14, borderRadius: 7 },
  bandTitle: { ...type.headline, fontSize: 15, color: colors.ink },
  bandHint: { ...type.footnote, color: colors.muted },
  openRow: { flexDirection: 'row', alignItems: 'center', gap: sp.sm },
  openText: { ...type.footnote, fontFamily: fonts.text600, color: colors.inkSoft },
  clubLink: {
    flexDirection: 'row', alignItems: 'center', gap: sp.sm, backgroundColor: colors.blueTint, borderRadius: radius.md, ...curve,
    paddingHorizontal: sp.md, minHeight: 44, marginTop: sp.xs,
  },
  clubLinkText: { flex: 1, ...type.callout, fontFamily: fonts.text700, color: colors.blueText },
  personNum: { fontFamily: fonts.text800, fontSize: 13, color: colors.ink, fontVariant: ['tabular-nums'] },
  personName: { ...type.footnote, fontFamily: fonts.text600, color: colors.inkSoft },
});
