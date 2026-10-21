import { useFocusEffect, useRouter } from 'expo-router';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  Alert, Animated, Dimensions, PanResponder, Pressable, ScrollView, Share, StyleSheet, Text, View, type ColorValue,
} from 'react-native';
import { ProfileCardView } from '../../src/components/ProfileCard';
import { Lockup, Mark } from '../../src/components/Brand';
import { CityWaitlist } from '../../src/components/CityWaitlist';
import { Icon } from '../../src/components/Icon';
import { Segmented } from '../../src/components/Segmented';
import { bump } from '../../src/lib/haptics';
import { greeting } from '../../src/lib/season';
import { MatchMoment } from '../../src/components/MatchMoment';
import { NoteSheet } from '../../src/components/NoteSheet';
import { HeaderIconButton } from '../../src/components/HeaderButton';
import { toast } from '../../src/components/Toast';
import { Empty, ErrorState, Loading, Screen, T, Tag } from '../../src/components/ui';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { formatClock, formatShortDate } from '../../src/lib/dates';
import { feedback } from '../../src/lib/feedback';
import { useSession } from '../../src/lib/session';
import { colors, fonts, iconSize, layout, lightPalette, radius, shadowSoft, sp, useTheme } from '../../src/lib/theme';
import type { CityStatus, MatchMode, ProfileCard, PromptKey, SwipeKind } from '../../src/lib/types';
import { features } from '../../src/lib/features';

const W = Dimensions.get('window').width;
const SWIPE_OUT = W * 0.3;

export default function Discover() {
  const { t, intl, cityName } = useI18n();
  const router = useRouter();
  const { limits, refreshLimits, profile } = useSession();
  const { raw } = useTheme();
  const hello = greeting();
  const [deck, setDeck] = useState<ProfileCard[] | null>(null);
  const [match, setMatch] = useState<{ id: string; other: ProfileCard } | null>(null);
  const [busy, setBusy] = useState(false);
  const [noteOpen, setNoteOpen] = useState(false);
  const [notePrompt, setNotePrompt] = useState<PromptKey | undefined>(undefined);
  const [city, setCity] = useState<CityStatus | null>(null);
  const [failed, setFailed] = useState(false);
  // People who are here for both browse dating and training partners separately.
  const [mode, setMode] = useState<MatchMode | undefined>(profile?.mode === 'both' ? 'dating' : undefined);
  const pos = useRef(new Animated.ValueXY()).current;
  const loadingMore = useRef(false);

  const load = useCallback(async () => {
    try {
      setFailed(false);
      setDeck(await api.discover(20, mode));
    } catch {
      setFailed(true);
      setDeck([]);
    }
  }, [mode]);

  useEffect(() => { if (deck !== null) { setDeck(null); load(); } // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode]);

  async function undo() {
    if (!limits?.pro) { router.push('/paywall'); return; }
    try {
      const r = await api.rewind();
      if (r.ok && r.profile) {
        bump();
        setDeck((cur) => [r.profile!, ...(cur ?? []).filter((x) => x.id !== r.profile!.id)]);
      } else if (r.error === 'pro_only') router.push('/paywall');
      else toast(t('undo.nothing'), { icon: 'info' });
    } catch {
      toast(t('common.error'), { error: true });
    }
  }

  useFocusEffect(
    useCallback(() => {
      if (deck === null || deck.length === 0) load();
      api.cityStatus().then(setCity).catch(() => {});
      refreshLimits();
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []),
  );

  const top = deck?.[0];

  async function topUp(remaining: ProfileCard[]) {
    if (remaining.length > 3 || loadingMore.current) return;
    loadingMore.current = true;
    try {
      const more = await api.discover(20, mode);
      setDeck((cur) => {
        const seen = new Set((cur ?? []).map((p) => p.id));
        return [...(cur ?? []), ...more.filter((p) => !seen.has(p.id))];
      });
    } finally {
      loadingMore.current = false;
    }
  }

  async function act(kind: SwipeKind, note?: string, prompt?: PromptKey) {
    if (!top || busy) return;
    setBusy(true);
    try {
      const res = await api.swipe(top.id, kind, note, prompt);
      if (!res.ok && res.error === 'like_limit') {
        resetCard();
        Alert.alert(t('discover.likeLimit'), t('discover.likeLimitSub'), [
          { text: t('common.close'), style: 'cancel' },
          { text: t('me.getPro'), onPress: () => router.push('/paywall') },
        ]);
        return;
      }
      if (!res.ok && res.error === 'super_limit') {
        resetCard();
        Alert.alert(t('discover.superLimit'), undefined, [
          { text: t('common.close'), style: 'cancel' },
          { text: t('me.getPro'), onPress: () => router.push('/paywall') },
        ]);
        return;
      }
      if (res.match_id) {
        setMatch({ id: res.match_id, other: top }); // MatchMoment plays its own sound
      } else if (kind !== 'pass') {
        feedback(kind === 'super' ? 'super' : 'like');
      }
      const rest = (deck ?? []).slice(1);
      setDeck(rest);
      pos.setValue({ x: 0, y: 0 });
      topUp(rest);
      refreshLimits();
    } catch {
      resetCard();
      toast(t('common.error'), { error: true });
    } finally {
      setBusy(false);
    }
  }

  function resetCard() {
    Animated.spring(pos, { toValue: { x: 0, y: 0 }, useNativeDriver: false }).start();
  }

  function flyOut(kind: SwipeKind, note?: string, prompt?: PromptKey) {
    const x = kind === 'pass' ? -W * 1.4 : W * 1.4;
    const y = kind === 'super' ? -600 : 0;
    Animated.timing(pos, { toValue: { x: kind === 'super' ? 0 : x, y }, duration: 220, useNativeDriver: false })
      .start(() => act(kind, note, prompt));
  }

  const pan = useRef(
    PanResponder.create({
      onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dx) > 12 && Math.abs(g.dx) > Math.abs(g.dy),
      onPanResponderMove: Animated.event([null, { dx: pos.x }], { useNativeDriver: false }),
      onPanResponderRelease: (_, g) => {
        if (g.dx > SWIPE_OUT) flyOutRef.current('like');
        else if (g.dx < -SWIPE_OUT) flyOutRef.current('pass');
        else Animated.spring(pos, { toValue: { x: 0, y: 0 }, useNativeDriver: false }).start();
      },
    }),
  ).current;
  const flyOutRef = useRef(flyOut);
  flyOutRef.current = flyOut;

  async function boost() {
    try {
      const r = await api.activateBoost();
      if (r.ok) {
        toast(t('discover.boostDone'), { icon: 'boost' });
        refreshLimits();
      } else if (r.error === 'no_boosts') {
        router.push('/paywall');
      }
    } catch {
      toast(t('common.error'), { error: true });
    }
  }

  // A soft haptic bump when a drag crosses the like / pass threshold, both ways.
  const past = useRef(0);
  useEffect(() => {
    const id = pos.x.addListener(({ value }) => {
      const zone = value > SWIPE_OUT ? 1 : value < -SWIPE_OUT ? -1 : 0;
      if (zone !== past.current) { if (zone !== 0) bump(); past.current = zone; }
    });
    return () => pos.x.removeListener(id);
  }, [pos.x]);

  const rotate = pos.x.interpolate({ inputRange: [-W, 0, W], outputRange: ['-12deg', '0deg', '12deg'] });
  const likeOpacity = pos.x.interpolate({ inputRange: [0, SWIPE_OUT], outputRange: [0, 1], extrapolate: 'clamp' });
  const nopeOpacity = pos.x.interpolate({ inputRange: [-SWIPE_OUT, 0], outputRange: [1, 0], extrapolate: 'clamp' });

  const boosted = limits?.boosted_until ? new Date(limits.boosted_until) > new Date() : false;

  return (
    <Screen>
      <View style={styles.header}>
        <Lockup size={22} />
        <View style={styles.toolbar}>
          <HeaderIconButton icon="sparkle" label={t('picks.open')} onPress={() => router.push('/picks')} />
          {boosted && limits?.boosted_until ? (
            <View style={styles.boosted} accessibilityLabel={t('discover.boost')}>
              <Icon name="boost" size={iconSize.inline} color="onGold" />
              <T variant="caption" tone="onGold">{formatClock(limits.boosted_until, intl)}</T>
            </View>
          ) : (
            <HeaderIconButton icon="boost" label={t('discover.boost')} onPress={boost}
              badge={limits ? String(limits.boost_credits + (limits.free_boost_available ? 1 : 0)) : undefined} />
          )}
        </View>
      </View>

      {profile ? (
        <View style={styles.status}>
          <T variant="footnote" tone="inkSoft" numberOfLines={1} style={{ flexShrink: 1 }}>{t(hello.hello, { name: profile.name })}</T>
          {hello.seasonal ? <Tag label={t(hello.seasonal)} tone="gold" icon="sparkle" /> : null}
          {profile.travel_city && profile.travel_until && new Date(profile.travel_until) > new Date() ? (
            <Tag tone="blue" icon="plane"
              label={t('travel.active', { city: cityName(profile.travel_city), date: formatShortDate(profile.travel_until, intl) })} />
          ) : null}
        </View>
      ) : null}
      {profile?.hidden ? <T variant="footnote" style={styles.paused}>{t('me.paused')}</T> : null}

      {profile?.mode === 'both' && mode ? (
        <View style={styles.segment}>
          <Segmented value={mode} onChange={setMode}
            options={[{ value: 'dating', label: t('mode.dating') }, { value: 'buddy', label: t('mode.buddy') }]} />
        </View>
      ) : null}

      {city && !city.open ? (
        <CityWaitlist status={city} code={profile?.referral_code ?? ''} />
      ) : deck === null ? (
        <Loading />
      ) : failed ? (
        <ErrorState onRetry={() => { setDeck(null); load(); }} />
      ) : !top ? (
        features.events ? (
          <Empty title={t('discover.empty')} sub={t('discover.emptySub')}
            action={t('discover.seeEvents')} onAction={() => router.push('/events')} />
        ) : (
          <Empty title={t('discover.empty')} sub={t('discover.emptySubApp')} action={t('me.invite')}
            onAction={() => Share.share({ message: t('me.inviteMessage', { code: profile?.referral_code ?? '' }) })} />
        )
      ) : (
        <>
          <ScrollView contentContainerStyle={{ paddingHorizontal: layout.margin, paddingTop: sp.sm, paddingBottom: 140 }} showsVerticalScrollIndicator={false}>
            <Animated.View
              {...pan.panHandlers}
              style={{ transform: [{ translateX: pos.x }, { translateY: pos.y }, { rotate }] }}
            >
              <ProfileCardView p={top} onComment={(k) => { setNotePrompt(k); setNoteOpen(true); }} />
              <Animated.View style={[styles.stamp, styles.stampLike, { opacity: likeOpacity }]}>
                <Mark size={52} color={lightPalette.blue} />
              </Animated.View>
              <Animated.View style={[styles.stamp, styles.stampNope, { opacity: nopeOpacity }]}>
                <Icon name="close" size={40} color={lightPalette.clay} weight="bold" />
              </Animated.View>
            </Animated.View>
          </ScrollView>

          <View style={styles.actions} pointerEvents="box-none">
            {limits?.likes_left != null && limits.likes_left <= 10 ? (
              <T variant="footnote" style={styles.left}>{t('discover.likesLeft', { n: limits.likes_left })}</T>
            ) : null}
            <View style={styles.actionRow} pointerEvents="box-none">
              <RoundButton size={48} onPress={undo} label={t('undo.title')} bg={colors.card}>
                <Icon name="undo" size={20} color="inkSoft" weight="semibold" />
              </RoundButton>
              <RoundButton size={64} onPress={() => flyOut('pass')} label="pass" bg={colors.card}>
                <Icon name="close" size={iconSize.action} color="clay" weight="bold" />
              </RoundButton>
              <RoundButton size={48} onPress={() => flyOut('super')} label="super like" bg={colors.gold}
                badge={limits ? String(limits.supers_left) : undefined}>
                <Icon name="star" size={22} color="onGold" />
              </RoundButton>
              <RoundButton size={64} onPress={() => flyOut('like')} label="like" bg={colors.blue}>
                <Mark size={34} color={raw.gold} />
              </RoundButton>
            </View>
          </View>
        </>
      )}

      <NoteSheet
        visible={noteOpen && !!top}
        name={top?.name ?? ''}
        challenge={top?.next_challenge}
        prompt={notePrompt ? top?.prompts?.find((q) => q.key === notePrompt) : null}
        onClose={() => setNoteOpen(false)}
        onSend={(note) => { setNoteOpen(false); flyOut('like', note, notePrompt); }}
      />

      <MatchMoment
        visible={!!match}
        buddy={match?.other.match_mode === 'buddy'}
        name={match?.other.name ?? ''}
        myPhoto={profile?.photos[0]}
        theirPhoto={match?.other.photos[0]}
        onClose={() => setMatch(null)}
        onWrite={() => {
          const id = match?.id;
          setMatch(null);
          if (id) router.push(`/chat/${id}`);
        }}
      />
    </Screen>
  );
}

function RoundButton({
  children, onPress, size, label, badge, bg,
}: {
  children: React.ReactNode; onPress: () => void; size: number; label: string; badge?: string; bg: ColorValue;
}) {
  return (
    <Pressable accessibilityLabel={badge ? `${label}, ${badge}` : label} accessibilityRole="button" onPress={onPress}
      style={({ pressed }) => [styles.round, { width: size, height: size, borderRadius: size / 2, backgroundColor: bg },
        pressed && { transform: [{ scale: 0.92 }] }]}>
      {children}
      {badge !== undefined && (
        <View style={styles.badge}><Text maxFontSizeMultiplier={1.2} style={styles.badgeText}>{badge}</Text></View>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    paddingLeft: layout.margin, paddingRight: sp.sm, minHeight: 44,
  },
  toolbar: { flexDirection: 'row', alignItems: 'center' },
  boosted: {
    flexDirection: 'row', alignItems: 'center', gap: sp.xs, backgroundColor: colors.gold, borderRadius: radius.pill,
    paddingHorizontal: sp.sm, paddingVertical: sp.xs, marginHorizontal: sp.sm,
  },
  status: { flexDirection: 'row', alignItems: 'center', gap: sp.sm, paddingHorizontal: layout.margin, minHeight: 24 },
  paused: { paddingHorizontal: layout.margin, marginTop: sp.xs },
  segment: { paddingHorizontal: layout.margin, paddingTop: sp.sm },
  actions: { position: 'absolute', bottom: sp.lg, left: 0, right: 0, alignItems: 'center', gap: sp.sm },
  actionRow: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: sp.lg },
  round: { alignItems: 'center', justifyContent: 'center', ...shadowSoft, shadowOpacity: 0.1 },
  badge: {
    position: 'absolute', top: -4, right: -4, minWidth: 20, paddingHorizontal: 5, paddingVertical: 1, borderRadius: 10,
    backgroundColor: colors.blue, alignItems: 'center', justifyContent: 'center',
  },
  badgeText: { color: colors.white, fontSize: 11, lineHeight: 16, fontFamily: fonts.text800 },
  left: { backgroundColor: colors.card, borderRadius: radius.pill, paddingHorizontal: sp.md, paddingVertical: sp.xs, overflow: 'hidden' },
  stamp: {
    position: 'absolute', top: 40, width: 84, height: 84, borderRadius: 42, borderWidth: 3,
    alignItems: 'center', justifyContent: 'center', backgroundColor: colors.card,
  },
  stampLike: { left: 24, borderColor: colors.blue },
  stampNope: { right: 24, borderColor: colors.clay },
});
