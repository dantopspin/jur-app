import { Image } from 'expo-image';
import { useFocusEffect, useRouter } from 'expo-router';
import React, { useCallback, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { Button, Empty, ErrorState, Screen, SkeletonList, T } from '../src/components/ui';
import { useI18n } from '../src/i18n';
import { api } from '../src/lib/api';
import { useSession } from '../src/lib/session';
import { bibNumber, colors, curve, fonts, layout, radius, sp, type } from '../src/lib/theme';
import type { ProfileCard } from '../src/lib/types';
import { features } from '../src/lib/features';

export default function Likes() {
  const { t } = useI18n();
  const router = useRouter();
  const { limits } = useSession();
  const [data, setData] = useState<{ count: number; profiles: ProfileCard[] } | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(() => {
    setFailed(false);
    api.likesReceived().then(setData).catch(() => setFailed(true));
  }, []);
  useFocusEffect(load);

  if (failed && !data) return <Screen edges={['bottom']}><ErrorState onRetry={load} /></Screen>;
  if (!data) return <Screen edges={['bottom']}><SkeletonList kind="card" rows={3} /></Screen>;
  if (data.count === 0) {
    return (
      <Screen edges={['bottom']}>
        {features.events
          ? <Empty icon="heart" title={t('likes.empty')} sub={t('likes.emptySub')} action={t('discover.seeEvents')} onAction={() => router.push('/events')} />
          : <Empty icon="heart" title={t('likes.empty')} sub={t('likes.emptySubApp')} action={t('prompts.title')} onAction={() => router.push('/prompts')} />}
      </Screen>
    );
  }

  if (!limits?.pro) {
    return (
      <Screen edges={['bottom']}>
        <View style={styles.locked}>
          <Text maxFontSizeMultiplier={1.2} style={styles.count}>{data.count}</Text>
          <T variant="body" tone="inkSoft" style={{ textAlign: 'center' }}>{t('likes.proOnly')}</T>
          <Button title={t('me.getPro')} variant="accent" onPress={() => router.push('/paywall')} style={{ alignSelf: 'stretch' }} />
        </View>
      </Screen>
    );
  }

  return (
    <Screen edges={['bottom']}>
      <FlatList
        data={data.profiles}
        numColumns={2}
        keyExtractor={(p) => p.id}
        contentContainerStyle={{ padding: layout.margin, gap: sp.md }}
        columnWrapperStyle={{ gap: sp.md }}
        renderItem={({ item: p }) => (
          <Pressable style={({ pressed }) => [styles.tile, pressed && { opacity: 0.85 }]} onPress={() => router.push(`/profile/${p.id}?from=likes`)}
            accessibilityRole="button" accessibilityLabel={`${p.name}, ${p.age}`}>
            <Image source={{ uri: p.photos[0] }} style={styles.photo} contentFit="cover" />
            <View style={styles.label}>
              <Text maxFontSizeMultiplier={1.4} style={styles.name} numberOfLines={1}>{p.name}, {p.age}</Text>
              <Text maxFontSizeMultiplier={1.3} style={styles.num}>№{bibNumber(p.member_no)}</Text>
              {p.note ? <Text maxFontSizeMultiplier={1.6} style={styles.note} numberOfLines={3}>“{p.note}”</Text> : null}
            </View>
          </Pressable>
        )}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  locked: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: sp.xxl, gap: sp.lg },
  count: { fontFamily: fonts.display, fontSize: 72, lineHeight: 80, color: colors.blueText, fontVariant: ['tabular-nums'] },
  tile: { flex: 1, borderRadius: radius.lg, ...curve, overflow: 'hidden', backgroundColor: colors.card },
  photo: { width: '100%', aspectRatio: 4 / 5, backgroundColor: colors.line },
  label: { padding: sp.md, gap: sp.xxs },
  note: {
    marginTop: sp.xs, ...type.footnote, fontFamily: fonts.text600, color: colors.blueText,
    backgroundColor: colors.blueTint, borderRadius: radius.sm, paddingHorizontal: sp.sm, paddingVertical: 6, overflow: 'hidden',
  },
  num: { ...type.caption, color: colors.muted, fontVariant: ['tabular-nums'] },
  name: { ...type.headline, fontSize: 15, color: colors.ink },
});
