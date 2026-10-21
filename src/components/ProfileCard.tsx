// A person as shown to others (brand system › ProfileCard).
// Front: photo with the horizon cut out of its bottom edge, facts below.
// Back (tap the member number): felt, the member number large, member since,
// events, verified and — after five events — the shanyrak Regular mark.
import { Image } from 'expo-image';
import React, { useRef, useState } from 'react';
import {
  AccessibilityInfo, Animated, Pressable, StyleSheet, Text, View, useWindowDimensions,
} from 'react-native';
import { useI18n } from '../i18n';
import { bump } from '../lib/haptics';
import { useSports } from '../lib/sports';
import { colors, curve, felt, fontScale, fonts, iconSize, layout, memberNo, radius, shadow, sp, space, type, useTheme } from '../lib/theme';
import type { ProfileCard as Card, PromptKey } from '../lib/types';
import type { TKey } from '../i18n';
import { Mark, Ridge, Shanyrak } from './Brand';
import { Felt } from './Felt';
import { Icon, sportIconName } from './Icon';
import { Tag } from './ui';
import { features } from '../lib/features';

export const REGULAR_AFTER = 5;

export function ProfileCardView({
  p, compact, onComment,
}: {
  p: Card; compact?: boolean;
  /** "like with a note": about their next challenge (no key) or one of their prompts */
  onComment?: (prompt?: PromptKey) => void;
}) {
  const { t, sportName, cityName, intl } = useI18n();
  const { byCode } = useSports();
  const { raw } = useTheme();
  const { width } = useWindowDimensions();
  const [photo, setPhoto] = useState(0);
  const [height, setHeight] = useState(0);
  const flip = useRef(new Animated.Value(0)).current;
  const [flipped, setFlipped] = useState(false);
  const photos = p.photos;
  const shared = p.shared_sports ?? 0;
  const cardWidth = width - layout.margin * 2;
  const regular = p.events_attended >= REGULAR_AFTER;

  async function toggle() {
    bump();
    const to = flipped ? 0 : 1;
    setFlipped(!flipped);
    const reduce = await AccessibilityInfo.isReduceMotionEnabled();
    if (reduce) { flip.setValue(to); return; }
    Animated.spring(flip, { toValue: to, damping: 18, stiffness: 180, useNativeDriver: true }).start();
  }

  const frontRot = flip.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '180deg'] });
  const backRot = flip.interpolate({ inputRange: [0, 1], outputRange: ['180deg', '360deg'] });
  const since = p.member_since
    ? new Date(`${p.member_since}-01T00:00:00Z`).toLocaleDateString(intl, { month: 'long', year: 'numeric' })
    : null;

  return (
    <View style={!compact && shadow}>
      {/* front */}
      <Animated.View
        onLayout={(e) => setHeight(e.nativeEvent.layout.height)}
        style={[styles.card, styles.face, { transform: [{ perspective: 1200 }, { rotateY: frontRot }] }]}
        importantForAccessibility={flipped ? 'no-hide-descendants' : 'auto'}
        accessibilityElementsHidden={flipped}
      >
        <Pressable
          style={[styles.photoWrap, compact && { aspectRatio: 1.1 }]}
          accessibilityHint="Tap left or right for more photos"
          onPress={(e) => {
            if (photos.length < 2) return;
            const left = e.nativeEvent.locationX < cardWidth / 2;
            setPhoto((i) => (left ? Math.max(0, i - 1) : Math.min(photos.length - 1, i + 1)));
          }}
        >
          {photos[photo] ? (
            <Image source={{ uri: photos[photo] }} style={StyleSheet.absoluteFill} contentFit="cover" transition={150}
              accessibilityLabel={p.name} />
          ) : (
            <View style={[StyleSheet.absoluteFill, { backgroundColor: colors.blue }]} />
          )}
          {photos.length > 1 && (
            <View style={styles.bars}>
              {photos.map((_, i) => (
                <View key={i} style={[styles.bar, i === photo && { backgroundColor: '#FFFFFF' }]} />
              ))}
            </View>
          )}
          <View style={styles.badges}>
            {p.super_liked_me ? <Badge text={t('discover.superLikedYou')} gold /> : null}
            {p.match_mode === 'buddy' ? <Badge text={t('mode.partner')} /> : null}
            {p.travel_city ? <Badge text={t('travel.visiting', { city: cityName(p.travel_city) })} /> : null}
            {regular ? <Badge text={t('circle.regular')} shanyrak /> : null}
            {p.is_host ? <Badge text={t('card.host')} /> : null}
          </View>
          <Ridge width={cardWidth} height={44} fill={raw.card} snow={false} style={styles.ridge} />
        </Pressable>

        <View style={styles.body}>
          <View style={styles.top}>
            <Text maxFontSizeMultiplier={fontScale.display} style={styles.name} numberOfLines={1}>{p.name}, {p.age}</Text>
            {p.verified ? (
              <View style={styles.verified}>
                <Icon name="verified" size={iconSize.row} color="blueText" />
                <Text maxFontSizeMultiplier={1.4} style={styles.verifiedText}>{t('card.verified')}</Text>
              </View>
            ) : null}
          </View>
          <View style={styles.metaRow}>
            <Pressable onPress={toggle} style={styles.no} hitSlop={8} accessibilityRole="button" accessibilityLabel={t('back.flip')}>
              <Text maxFontSizeMultiplier={fontScale.control} style={styles.noText}>{memberNo(p.member_no)}</Text>
              <Icon name="flip" size={11} color="muted" weight="semibold" />
            </Pressable>
            <Text maxFontSizeMultiplier={1.6} style={styles.meta} numberOfLines={1}>
              {cityName(p.city)}
              {p.events_attended > 0 ? ` · ${t('card.events', { n: p.events_attended })}` : ''}
            </Text>
          </View>

          <View style={styles.chips}>
            {p.sports.slice(0, compact ? 4 : 8).map((s) => {
              const def = byCode[s.code];
              return <Tag key={s.code} tone="neutral" icon={sportIconName(s.code)} label={def ? sportName(def) : s.code} />;
            })}
            {shared > 0 ? (
              <Tag tone="gold" label={shared === 1 ? t('discover.sharedOne') : t('discover.sharedMany', { n: shared })} />
            ) : null}
          </View>

          {!compact && p.next_challenge ? (
            <Pressable style={styles.goal} onPress={() => onComment?.()} disabled={!onComment}
              accessibilityRole={onComment ? 'button' : undefined} accessibilityHint={onComment ? t('note.add') : undefined}>
              <View style={{ flex: 1, gap: sp.xs }}>
                <Text maxFontSizeMultiplier={1.4} style={styles.label}>{t('card.nextChallenge')}</Text>
                <Text maxFontSizeMultiplier={1.6} style={styles.goalText}>{p.next_challenge}</Text>
              </View>
              {onComment ? (
                <View style={styles.comment}><Icon name="note" size={iconSize.row} color="blueText" /></View>
              ) : null}
            </Pressable>
          ) : null}

          {!compact && (p.prompts ?? []).map((q) => (
            <Pressable key={q.key} style={styles.prompt} onPress={() => onComment?.(q.key)} disabled={!onComment}
              accessibilityRole={onComment ? 'button' : undefined} accessibilityHint={onComment ? t('note.add') : undefined}>
              <View style={{ flex: 1, gap: sp.xs }}>
                <Text maxFontSizeMultiplier={1.6} style={styles.promptQ}>{t(`prompts.${q.key}` as TKey)}</Text>
                <Text maxFontSizeMultiplier={1.35} style={styles.promptA}>{q.answer}</Text>
              </View>
              {onComment ? (
                <View style={styles.comment}><Icon name="note" size={iconSize.row} color="blueText" /></View>
              ) : null}
            </Pressable>
          ))}

          {!compact && p.achievements.length > 0 ? (
            <View style={{ gap: sp.xs }}>
              {p.achievements.slice(0, 3).map((a, i) => (
                <View key={i} style={styles.ach}>
                  <Text maxFontSizeMultiplier={1.6} style={styles.achTitle} numberOfLines={1}>{a.title}</Text>
                  {a.result ? <Text maxFontSizeMultiplier={1.6} style={styles.achResult}>{a.result}</Text> : null}
                </View>
              ))}
            </View>
          ) : null}

          {!compact && p.bio ? <Text maxFontSizeMultiplier={2} style={styles.bio}>{p.bio}</Text> : null}
        </View>
      </Animated.View>

      {/* back */}
      <Animated.View
        pointerEvents={flipped ? 'auto' : 'none'}
        importantForAccessibility={flipped ? 'auto' : 'no-hide-descendants'}
        accessibilityElementsHidden={!flipped}
        style={[styles.backWrap, styles.face, { height: height || undefined, transform: [{ perspective: 1200 }, { rotateY: backRot }] }]}
      >
        <Pressable style={{ flex: 1 }} onPress={toggle} accessibilityRole="button" accessibilityLabel={t('back.flip')}>
          <Felt style={styles.back}>
            <View style={styles.backTop}>
              <Mark size={34} color={felt.label} />
              <Text maxFontSizeMultiplier={1.6} style={styles.backLabel}>{t('back.title').toUpperCase()}</Text>
            </View>
            <View style={{ alignItems: 'center', gap: space(1) }}>
              {regular ? (
                <View style={styles.backSeal}>
                  <Shanyrak size={128} color={felt.label} slats={0.22} />
                  <Text maxFontSizeMultiplier={1.3} style={[styles.backNo, styles.backNoInSeal]}>{memberNo(p.member_no)}</Text>
                </View>
              ) : (
                <Text maxFontSizeMultiplier={1.3} style={styles.backNo}>{memberNo(p.member_no)}</Text>
              )}
              <Text maxFontSizeMultiplier={1.6} style={styles.backName}>{p.name}</Text>
              {since ? <Text maxFontSizeMultiplier={1.6} style={styles.backSince}>{t('back.since', { date: since })}</Text> : null}
            </View>
            {features.events || p.verified ? (
              <View style={styles.backStats}>
                {features.events ? <BackStat value={String(p.events_attended)} label={t('back.events')} /> : null}
                {p.verified ? <BackStat value="✓" label={t('back.verified')} /> : null}
              </View>
            ) : null}
            <View style={styles.backSports}>
              {p.sports.slice(0, 6).map((s) => (
                <Icon key={s.code} name={sportIconName(s.code)} size={20} color={felt.ink} />
              ))}
            </View>
          </Felt>
        </Pressable>
      </Animated.View>
    </View>
  );
}

function BackStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center', minWidth: 72 }}>
      <Text maxFontSizeMultiplier={1.6} style={styles.backStatValue}>{value}</Text>
      <Text maxFontSizeMultiplier={1.6} style={styles.backStatLabel}>{label}</Text>
    </View>
  );
}

function Badge({ text, gold, shanyrak }: { text: string; gold?: boolean; shanyrak?: boolean }) {
  return (
    <View style={[styles.badge, gold && { backgroundColor: colors.gold }, shanyrak && styles.badgeFelt]}>
      {shanyrak ? <Shanyrak size={16} color={felt.label} slats={0.8} /> : null}
      <Text maxFontSizeMultiplier={1.3} numberOfLines={1} style={[styles.badgeText, gold && { color: colors.onGold }, shanyrak && { color: felt.ink }]}>{text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  face: { backfaceVisibility: 'hidden' },
  card: { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, overflow: 'hidden' },
  photoWrap: { width: '100%', aspectRatio: 4 / 4.4, backgroundColor: colors.blue },
  bars: { position: 'absolute', top: sp.sm, left: sp.lg, right: sp.lg, flexDirection: 'row', gap: sp.xs },
  bar: { flex: 1, height: 3, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.45)' },
  badges: { position: 'absolute', left: sp.lg, right: sp.lg, top: sp.lg + sp.xs, flexDirection: 'row', gap: sp.sm, flexWrap: 'wrap' },
  badge: {
    flexDirection: 'row', alignItems: 'center', gap: sp.xs, backgroundColor: colors.blue, paddingHorizontal: 10,
    paddingVertical: 5, borderRadius: radius.pill,
  },
  badgeFelt: { backgroundColor: felt.ground },
  badgeText: { ...type.caption, color: '#FFFFFF' },
  ridge: { position: 'absolute', left: 0, bottom: -1 },
  body: { paddingHorizontal: sp.lg, paddingBottom: sp.lg, paddingTop: sp.xs, gap: sp.md },
  top: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: sp.sm },
  name: { flex: 1, ...type.title2, color: colors.ink },
  verified: { flexDirection: 'row', alignItems: 'center', gap: sp.xs },
  verifiedText: { ...type.caption, fontSize: 13, color: colors.blueText },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: sp.sm, marginTop: -sp.xs },
  no: {
    flexDirection: 'row', alignItems: 'center', gap: sp.xs, backgroundColor: colors.bg, borderRadius: radius.pill,
    paddingHorizontal: sp.sm, paddingVertical: 3,
  },
  noText: { fontFamily: fonts.text800, fontSize: 13, color: colors.ink, fontVariant: ['tabular-nums'] },
  meta: { flex: 1, ...type.callout, fontFamily: fonts.text500, color: colors.inkSoft },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: sp.sm },
  goal: {
    backgroundColor: colors.bg, borderRadius: radius.md, ...curve, padding: sp.lg,
    flexDirection: 'row', alignItems: 'flex-start', gap: sp.md,
  },
  comment: {
    width: 32, height: 32, borderRadius: 16, backgroundColor: colors.card, alignItems: 'center', justifyContent: 'center',
  },
  label: { ...type.overline, fontSize: 11, color: colors.clayDeep },
  goalText: { ...type.headline, color: colors.ink },
  prompt: {
    backgroundColor: colors.bg, borderRadius: radius.md, ...curve, padding: sp.lg,
    flexDirection: 'row', alignItems: 'flex-start', gap: sp.md,
  },
  promptQ: { ...type.footnote, fontFamily: fonts.text600, color: colors.muted },
  promptA: { ...type.title3, color: colors.ink },
  ach: { flexDirection: 'row', justifyContent: 'space-between', gap: sp.sm },
  achTitle: { flex: 1, ...type.callout, fontFamily: fonts.text500, color: colors.inkSoft },
  achResult: { ...type.callout, fontFamily: fonts.text700, color: colors.ink, fontVariant: ['tabular-nums'] },
  bio: { ...type.body, color: colors.inkSoft },
  // back
  backWrap: { position: 'absolute', left: 0, right: 0, top: 0, borderRadius: radius.lg, ...curve, overflow: 'hidden' },
  back: { flex: 1, padding: space(2.5), justifyContent: 'space-between', borderRadius: radius.lg },
  backTop: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  backLabel: { fontFamily: fonts.text800, fontSize: 12, letterSpacing: 1.4, color: felt.label },
  backSeal: { width: 128, height: 128, alignItems: 'center', justifyContent: 'center' },
  backNo: { fontFamily: fonts.display, fontSize: 52, lineHeight: 60, color: felt.ink, letterSpacing: -1 },
  backNoInSeal: { position: 'absolute', fontSize: 24, lineHeight: 30, letterSpacing: 0 },
  backName: { fontFamily: fonts.displayMedium, fontSize: 20, color: felt.ink },
  backSince: { fontFamily: fonts.text600, fontSize: 14, color: '#5B5240' },
  backStats: {
    flexDirection: 'row', justifyContent: 'center', gap: space(2), borderTopWidth: 1, borderBottomWidth: 1,
    borderColor: felt.line, paddingVertical: space(1.5),
  },
  backStatValue: { fontFamily: fonts.display, fontSize: 22, color: felt.ink },
  backStatLabel: { fontFamily: fonts.text700, fontSize: 11, letterSpacing: 0.6, color: '#5B5240', textTransform: 'uppercase' },
  backSports: { flexDirection: 'row', justifyContent: 'center', gap: space(1.5) },
});
