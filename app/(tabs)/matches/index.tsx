import { Image } from 'expo-image';
import { useFocusEffect, useRouter } from 'expo-router';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, FlatList, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Icon } from '../../../src/components/Icon';
import { PreviewLink } from '../../../src/components/PreviewLink';
import { Empty, ErrorState, SectionLabel, SkeletonList, T, Tag } from '../../../src/components/ui';
import { useI18n } from '../../../src/i18n';
import { api } from '../../../src/lib/api';
import { useSession } from '../../../src/lib/session';
import { supabase } from '../../../src/lib/supabase';
import { formatInboxTime } from '../../../src/lib/dates';
import { border, colors, curve, fonts, iconSize, layout, radius, sp, type } from '../../../src/lib/theme';
import type { MatchRow } from '../../../src/lib/types';
import { features } from '../../../src/lib/features';

export default function Matches() {
  const { t, intl } = useI18n();
  const router = useRouter();
  const { profile } = useSession();
  const [rows, setRows] = useState<MatchRow[] | null>(null);
  const [likes, setLikes] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const [failed, setFailed] = useState(false);

  const load = useCallback(async () => {
    try {
      const [m, l] = await Promise.all([api.matches(), api.likesReceived()]);
      setRows(m);
      setLikes(l.count);
      setFailed(false);
    } catch {
      setFailed(true);
      setRows((cur) => cur ?? []);
    }
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  // Live inbox: any new message or match in a chat I'm part of refreshes the list.
  useEffect(() => {
    if (!profile) return;
    const ch = supabase
      .channel(`inbox:${profile.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, () => load())
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'matches' }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [profile, load]);

  const fresh = (rows ?? []).filter((r) => !r.last_message);
  const convos = (rows ?? []).filter((r) => r.last_message);

  function unmatch(r: MatchRow) {
    Alert.alert(t('chat.unmatch'), t('chat.unmatchConfirm', { name: r.other.name }), [
      { text: t('common.cancel'), style: 'cancel' },
      { text: t('chat.unmatch'), style: 'destructive', onPress: async () => { await api.unmatch(r.match_id); load(); } },
    ]);
  }

  if (rows === null) return <SkeletonList rows={7} />;
  if (failed && rows.length === 0) return <ErrorState onRetry={load} />;

  return (
    <FlatList
      data={convos}
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: colors.bg }}
      keyExtractor={(r) => r.match_id}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => {
        setRefreshing(true); await load(); setRefreshing(false);
      }} />}
      contentContainerStyle={{ flexGrow: 1, paddingBottom: sp.xxl }}
      ItemSeparatorComponent={() => <View style={styles.sep} />}
      ListHeaderComponent={
        <View style={{ gap: sp.xl, paddingTop: sp.sm, paddingBottom: convos.length ? sp.sm : 0 }}>
          {likes > 0 && (
            <Pressable style={({ pressed }) => [styles.likes, pressed && { opacity: 0.85 }]} onPress={() => router.push('/likes')} accessibilityRole="button">
              <Text maxFontSizeMultiplier={1.2} style={styles.likesNum}>{likes}</Text>
              <View style={{ flex: 1, gap: sp.xxs }}>
                <Text maxFontSizeMultiplier={1.6} style={styles.likesText}>
                  {likes === 1 ? t('matches.likedYouOne') : t('matches.likedYou', { n: likes })}
                </Text>
                <Text maxFontSizeMultiplier={1.6} style={styles.likesCta}>{t('matches.seeWho')}</Text>
              </View>
              <Icon name="forward" size={iconSize.inline} color="blueMist" />
            </Pressable>
          )}
          {fresh.length > 0 && (
            <View>
              <SectionLabel style={{ paddingHorizontal: layout.margin }}>{t('matches.newMatches')}</SectionLabel>
              <ScrollView horizontal showsHorizontalScrollIndicator={false}
                contentContainerStyle={{ paddingHorizontal: layout.margin, gap: sp.lg }}>
                {fresh.map((r) => (
                  <Pressable key={r.match_id} onPress={() => router.push(`/chat/${r.match_id}`)} style={styles.fresh}
                    accessibilityRole="button" accessibilityLabel={r.other.name}>
                    <View style={styles.ring}>
                      <Image source={{ uri: r.other.photos[0] }} style={styles.bigAvatar} contentFit="cover" />
                    </View>
                    <T variant="caption" tone="ink" numberOfLines={1} style={{ maxWidth: 72 }}>{r.other.name}</T>
                  </Pressable>
                ))}
              </ScrollView>
            </View>
          )}
          {convos.length > 0 && <SectionLabel style={{ paddingHorizontal: layout.margin, marginBottom: 0 }}>{t('matches.messages')}</SectionLabel>}
        </View>
      }
      ListEmptyComponent={fresh.length === 0 && likes === 0
        ? (features.events
          ? <Empty icon="chats" title={t('matches.empty')} sub={t('matches.emptySub')} action={t('discover.seeEvents')} onAction={() => router.push('/events')} />
          : <Empty icon="chats" title={t('matches.empty')} sub={t('matches.emptySubApp')} action={t('matches.goDiscover')} onAction={() => router.push('/discover')} />)
        : null}
      renderItem={({ item: r }) => (
        <PreviewLink
          href={`/chat/${r.match_id}`}
          cancelLabel={t('common.cancel')}
          accessibilityLabel={r.unread > 0 ? `${r.other.name}, ${r.unread}` : r.other.name}
          style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.line }]}
          actions={[
            { title: t('menu.viewProfile'), icon: 'people', onPress: () => router.push(`/profile/${r.other.id}`) },
            { title: t('chat.unmatch'), icon: 'close', destructive: true, onPress: () => unmatch(r) },
          ]}>
          <Image source={{ uri: r.other.photos[0] }} style={styles.avatar} contentFit="cover" />
          <View style={{ flex: 1, gap: sp.xxs }}>
            <View style={styles.nameRow}>
              <Text maxFontSizeMultiplier={1.6} style={styles.name} numberOfLines={1}>{r.other.name}</Text>
              {r.kind === 'buddy' ? <Tag label={t('mode.partner')} /> : null}
              <View style={{ flex: 1 }} />
              {r.last_message ? (
                <Text maxFontSizeMultiplier={1.4} style={[styles.time, r.unread > 0 && { color: colors.blueText }]}>
                  {formatInboxTime(r.last_message.created_at, intl)}
                </Text>
              ) : null}
            </View>
            <View style={styles.previewRow}>
              <Text maxFontSizeMultiplier={1.6} style={[styles.preview, r.unread > 0 && { color: colors.ink }]} numberOfLines={2}>
                {r.last_message?.sender_id === profile?.id ? t('matches.you') : ''}
                {r.last_message?.kind === 'photo' ? t('chat2.photo') : r.last_message?.kind === 'voice' ? t('chat2.voice')
                  : r.last_message?.kind === 'date' ? t('chat2.dateCard') : r.last_message?.body}
              </Text>
              {r.unread > 0 && <View style={styles.dot}><Text maxFontSizeMultiplier={1.2} style={styles.dotText}>{r.unread}</Text></View>}
            </View>
          </View>
        </PreviewLink>
      )}
    />
  );
}

const AVATAR = 56;

const styles = StyleSheet.create({
  likes: {
    marginHorizontal: layout.margin, backgroundColor: colors.blue, borderRadius: radius.lg, ...curve, padding: sp.lg,
    flexDirection: 'row', alignItems: 'center', gap: sp.lg,
  },
  likesNum: { ...type.title1, fontSize: 34, lineHeight: 40, color: colors.gold, fontVariant: ['tabular-nums'] },
  likesText: { ...type.headline, color: colors.white },
  likesCta: { ...type.footnote, fontFamily: fonts.text600, color: colors.blueMist },
  fresh: { alignItems: 'center', gap: sp.xs + 2 },
  ring: { padding: 3, borderRadius: 40, borderWidth: 2.5, borderColor: colors.blue },
  bigAvatar: { width: 64, height: 64, borderRadius: 32, backgroundColor: colors.line },
  row: { flexDirection: 'row', alignItems: 'center', gap: sp.md, paddingHorizontal: layout.margin, paddingVertical: sp.md },
  sep: { height: border.hair, backgroundColor: colors.line, marginLeft: layout.margin + AVATAR + sp.md },
  avatar: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2, backgroundColor: colors.line },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: sp.sm },
  name: { ...type.headline, color: colors.ink, flexShrink: 1 },
  time: { ...type.footnote, color: colors.muted, fontVariant: ['tabular-nums'] },
  previewRow: { flexDirection: 'row', alignItems: 'flex-start', gap: sp.sm },
  preview: { flex: 1, ...type.callout, fontFamily: fonts.text500, color: colors.muted },
  dot: {
    minWidth: 20, paddingHorizontal: 6, paddingVertical: 1, borderRadius: 10, backgroundColor: colors.blue,
    alignItems: 'center', justifyContent: 'center', marginTop: 1,
  },
  dotText: { color: colors.white, fontFamily: fonts.text800, fontSize: 12, lineHeight: 18, fontVariant: ['tabular-nums'] },
});
