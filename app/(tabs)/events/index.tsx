import { Stack, useFocusEffect, useRouter } from 'expo-router';
import React, { useCallback, useState } from 'react';
import { FlatList, Pressable, RefreshControl, Share, StyleSheet, Text, View } from 'react-native';
import { ClubCardBody, clubCardStyle } from '../../../src/components/ClubCard';
import { Icon, sportIconName } from '../../../src/components/Icon';
import { Segmented } from '../../../src/components/Segmented';
import { PreviewLink } from '../../../src/components/PreviewLink';
import { HeaderIconButton } from '../../../src/components/HeaderButton';
import { Empty, ErrorState, SkeletonList, T, Tag } from '../../../src/components/ui';
import { useI18n, type TKey } from '../../../src/i18n';
import { api } from '../../../src/lib/api';
import { formatEventTime } from '../../../src/lib/dates';
import { syncEventActivities } from '../../../src/lib/liveActivity';
import { useSession } from '../../../src/lib/session';
import { useSports } from '../../../src/lib/sports';
import { colors, curve, fonts, iconSize, layout, radius, sp, type } from '../../../src/lib/theme';
import type { Club, EventItem } from '../../../src/lib/types';

export default function Events() {
  const { t, intl, sportName } = useI18n();
  const { byCode } = useSports();
  const { profile } = useSession();
  const router = useRouter();
  const [items, setItems] = useState<EventItem[] | null>(null);
  const [clubs, setClubs] = useState<Club[] | null>(null);
  const [tab, setTab] = useState<'events' | 'clubs'>('events');
  const [refreshing, setRefreshing] = useState(false);
  const [failed, setFailed] = useState(false);

  const load = useCallback(async () => {
    try {
      const [list, cl] = await Promise.all([api.upcomingEvents(), api.clubs()]);
      setItems(list);
      setClubs(cl);
      syncEventActivities(list, (place) => t('live.meet', { place }));
      setFailed(false);
    } catch {
      setFailed(true);
      setItems((cur) => cur ?? []);
      setClubs((cur) => cur ?? []);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const refresh = (
    <RefreshControl refreshing={refreshing} onRefresh={async () => {
      setRefreshing(true); await load(); setRefreshing(false);
    }} />
  );
  const header = (
    <View style={{ gap: sp.md, marginBottom: sp.xs }}>
      <Segmented value={tab} onChange={setTab}
        options={[{ value: 'events', label: t('clubs.tabEvents') }, { value: 'clubs', label: t('clubs.tabClubs') }]} />
      <T variant="footnote">{tab === 'events' ? t('events.sub') : t('clubs.sub')}</T>
    </View>
  );

  return (
    <>
      <Stack.Screen options={{
        headerRight: profile?.is_host ? () => (
          <HeaderIconButton icon="add" label={t('events.create')} onPress={() => router.push('/event/new')} />
        ) : undefined,
      }} />
      {items === null || clubs === null ? (
        <SkeletonList kind="card" rows={4} />
      ) : failed && items.length === 0 && clubs.length === 0 ? (
        <ErrorState onRetry={load} />
      ) : tab === 'clubs' ? (
        <FlatList
          data={clubs}
          keyExtractor={(c) => c.id}
          contentInsetAdjustmentBehavior="automatic"
          contentContainerStyle={{ padding: layout.margin, gap: sp.md, flexGrow: 1, paddingBottom: sp.xxl }}
          style={{ backgroundColor: colors.bg }}
          refreshControl={refresh}
          ListHeaderComponent={header}
          ListFooterComponent={
            <Pressable style={({ pressed }) => [styles.start, pressed && { opacity: 0.8 }]} accessibilityRole="button"
              onPress={() => router.push('/club/apply')}>
              <Icon name="plusCircle" size={iconSize.action} color="blueText" />
              <View style={{ flex: 1, gap: sp.xxs }}>
                <Text maxFontSizeMultiplier={1.6} style={styles.startTitle}>{t('clubs.start')}</Text>
                <Text maxFontSizeMultiplier={1.6} style={styles.startSub}>{t('clubs.startSub')}</Text>
              </View>
              <Icon name="forward" size={iconSize.inline} color="blueText" />
            </Pressable>
          }
          ListEmptyComponent={<T variant="callout" style={{ textAlign: 'center', marginVertical: sp.xl }}>{t('clubs.empty')}</T>}
          renderItem={({ item: c }) => (
            <PreviewLink href={`/club/${c.id}`} cancelLabel={t('common.cancel')} accessibilityLabel={c.name}
              style={({ pressed }) => [clubCardStyle, pressed && { opacity: 0.92 }]}>
              <ClubCardBody c={c} />
            </PreviewLink>
          )}
        />
      ) : (
        <FlatList
          data={items}
          keyExtractor={(e) => e.id}
          contentInsetAdjustmentBehavior="automatic"
          contentContainerStyle={{ padding: layout.margin, gap: sp.md, flexGrow: 1, paddingBottom: sp.xxl }}
          style={{ backgroundColor: colors.bg }}
          refreshControl={refresh}
          ListHeaderComponent={header}
          ListEmptyComponent={<Empty icon="calendar" title={t('events.empty')} sub={t('events.emptySub')} />}
          renderItem={({ item: e }) => {
            const sport = byCode[e.sport_code];
            const full = e.going_count >= e.capacity;
            const when = formatEventTime(e.starts_at, intl);
            return (
              <PreviewLink
                href={`/event/${e.id}`}
                cancelLabel={t('common.cancel')}
                accessibilityLabel={`${e.title}, ${when}`}
                style={({ pressed }) => [styles.card, pressed && { opacity: 0.92 }]}
                actions={[{
                  title: t('menu.share'), icon: 'share',
                  onPress: () => Share.share({ message: t('menu.shareEvent', { title: e.title, when }) }),
                }]}
              >
                <View style={styles.iconTile}>
                  <Icon name={sportIconName(e.sport_code)} size={iconSize.action} color="blueText" />
                </View>
                <View style={{ flex: 1, gap: sp.xs }}>
                  <Text maxFontSizeMultiplier={1.4} style={styles.when}>{when}</Text>
                  {e.club ? <Text maxFontSizeMultiplier={1.6} style={styles.club} numberOfLines={1}>{e.club.name}</Text> : null}
                  <Text maxFontSizeMultiplier={1.35} style={styles.title} numberOfLines={2}>{e.title}</Text>
                  <Text maxFontSizeMultiplier={1.6} style={styles.meta} numberOfLines={1}>
                    {sport ? sportName(sport) : e.sport_code} · {e.meeting_point}
                  </Text>
                  {e.after_text ? (
                    <View style={styles.after}>
                      <Icon name="tea" size={iconSize.inline} color="clay" />
                      <Text maxFontSizeMultiplier={1.6} style={styles.afterText} numberOfLines={1}>{e.after_text}</Text>
                    </View>
                  ) : null}
                  <View style={styles.tags}>
                    {e.i_am_going ? <Tag tone="good" icon="tick" label={t('events.youreIn')} /> : null}
                    <Tag tone={full ? 'clay' : 'neutral'} icon="people" label={t('events.going', { n: e.going_count, cap: e.capacity })} />
                    {e.open_count > 0 ? <Tag tone="gold" icon="heart" label={String(e.open_count)} /> : null}
                    <Tag tone="neutral" label={t(`levels.${e.level}` as TKey)} />
                    <Tag tone="neutral" label={e.price_kzt > 0 ? `${e.price_kzt.toLocaleString(intl)} ₸` : t('common.free')} />
                  </View>
                </View>
              </PreviewLink>
            );
          }}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  club: { ...type.footnote, fontFamily: fonts.text700, color: colors.blueText },
  start: {
    flexDirection: 'row', alignItems: 'center', gap: sp.md, borderRadius: radius.lg, ...curve, padding: sp.lg,
    backgroundColor: colors.blueTint, marginTop: sp.xs,
  },
  startTitle: { ...type.headline, color: colors.blueText },
  startSub: { ...type.footnote, color: colors.inkSoft },
  card: { flexDirection: 'row', gap: sp.md, backgroundColor: colors.card, borderRadius: radius.lg, ...curve, padding: sp.lg },
  iconTile: {
    width: 56, height: 56, borderRadius: radius.md, ...curve, backgroundColor: colors.blueTint, alignItems: 'center', justifyContent: 'center',
  },
  when: { ...type.overline, color: colors.accentText },
  title: { ...type.title3, color: colors.ink },
  meta: { ...type.footnote, color: colors.muted },
  after: { flexDirection: 'row', alignItems: 'center', gap: sp.xs + 2 },
  afterText: { flex: 1, ...type.footnote, fontFamily: fonts.text600, color: colors.inkSoft },
  tags: { flexDirection: 'row', flexWrap: 'wrap', gap: sp.xs + 2, marginTop: sp.xs },
});
