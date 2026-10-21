// Group chat used by clubs and double dates: names and avatars on others'
// messages, realtime, blocked people hidden by the server.
import { Image } from 'expo-image';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Icon } from './Icon';
import { toast } from './Toast';
import { useSheet } from './Sheet';
import { confirmBlock, openReportFlow } from '../lib/safety';
import { knock } from '../lib/haptics';
import { ErrorState, SkeletonList } from './ui';
import { useI18n } from '../i18n';
import { formatDivider, needsDivider } from '../lib/dates';
import { feedback } from '../lib/feedback';
import { useSession } from '../lib/session';
import { supabase } from '../lib/supabase';
import { colors, curve, fonts, layout, memberNo, sp, type } from '../lib/theme';
import type { GroupMessage } from '../lib/types';

export function GroupChat({
  channel, table, filter, fetchPage, send: sendBody, empty,
}: {
  /** realtime channel name, table and row filter, e.g. club_messages / club_id=eq.<id> */
  channel: string; table: string; filter: string;
  fetchPage: (before?: string) => Promise<GroupMessage[]>;
  send: (body: string) => Promise<void>;
  empty: string;
}) {
  const { t, intl } = useI18n();
  const { profile } = useSession();
  const sheet = useSheet();
  const me = profile?.id ?? '';
  const [msgs, setMsgs] = useState<GroupMessage[] | null>(null);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [failed, setFailed] = useState(false);
  const loadingOlder = useRef(false);

  const merge = (incoming: GroupMessage[]) => setMsgs((cur) => {
    const seen = new Set((cur ?? []).map((m) => m.id));
    return [...incoming.filter((m) => !seen.has(m.id)), ...(cur ?? [])]
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
  });

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const refresh = useCallback(async () => merge(await fetchPage()), [channel]);

  useEffect(() => {
    fetchPage().then((m) => { setFailed(false); setMsgs(m); }).catch(() => setFailed(true));
    const ch = supabase.channel(channel)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table, filter },
        (payload) => {
          const m = payload.new as { sender_id: string };
          refresh().catch(() => {});
          if (m.sender_id !== me) feedback('message');
        })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [channel, me]);

  async function older() {
    if (!msgs?.length || loadingOlder.current) return;
    loadingOlder.current = true;
    try { merge(await fetchPage(msgs[msgs.length - 1].created_at)); } finally { loadingOlder.current = false; }
  }

  /** Long-press someone else's message: report or block them (the server then hides their messages). */
  function actions(m: GroupMessage) {
    if (m.sender_id === me) return;
    knock();
    const other = { id: m.sender_id, name: m.sender.name };
    const hide = () => setMsgs((cur) => (cur ?? []).filter((x) => x.sender_id !== m.sender_id));
    sheet({
      title: m.sender.name,
      cancelLabel: t('common.cancel'),
      options: [
        { label: t('chat.report'), onPress: () => openReportFlow({ t, sheet, me, other, onDone: hide }) },
        { label: t('chat.block'), destructive: true, onPress: () => confirmBlock({ t, me, other, onDone: hide }) },
      ],
    });
  }

  async function send() {
    const body = text.trim();
    if (!body || sending) return;
    setSending(true);
    setText('');
    try {
      await sendBody(body);
      await refresh();
    } catch {
      setText(body);
      toast(t('chat.sendFailed'), { error: true });
    } finally {
      setSending(false);
    }
  }

  return (
    <SafeAreaView edges={['bottom']} style={{ flex: 1, backgroundColor: colors.bg }}>
      {msgs === null && failed ? (
        <ErrorState onRetry={() => { setFailed(false); fetchPage().then(setMsgs).catch(() => setFailed(true)); }} />
      ) : msgs === null ? <SkeletonList rows={5} /> : (
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={90}>
          <FlatList
            inverted
            data={msgs}
            keyExtractor={(m) => m.id}
            onEndReached={older}
            onEndReachedThreshold={0.3}
            contentContainerStyle={{ paddingHorizontal: layout.margin, paddingVertical: sp.md, flexGrow: 1 }}
            ListEmptyComponent={<Text maxFontSizeMultiplier={1.6} style={styles.empty}>{empty}</Text>}
            renderItem={({ item: m, index }) => {
              const mine = m.sender_id === me;
              // inverted: index + 1 is older, index - 1 newer
              const older = msgs[index + 1];
              const newer = msgs[index - 1];
              const divider = needsDivider(older?.created_at, m.created_at);
              const groupStart = divider || !older || older.sender_id !== m.sender_id;
              const groupEnd = !newer || newer.sender_id !== m.sender_id || needsDivider(m.created_at, newer.created_at);
              return (
                <View style={{ marginTop: groupStart ? sp.sm : sp.xxs }}>
                  {divider ? <Text maxFontSizeMultiplier={1.4} style={styles.divider}>{formatDivider(m.created_at, intl)}</Text> : null}
                  <View style={[styles.line, mine && { justifyContent: 'flex-end' }]}>
                    {!mine && (groupEnd && m.sender.photo
                      ? <Image source={{ uri: m.sender.photo }} style={styles.avatar} contentFit="cover" accessibilityLabel={m.sender.name} />
                      : <View style={styles.avatarSpace} />)}
                    <Pressable onLongPress={() => actions(m)} delayLongPress={300} disabled={mine}
                      accessibilityHint={mine ? undefined : `${t('chat.report')} · ${t('chat.block')}`}
                      accessibilityActions={mine ? undefined : [{ name: 'report', label: t('chat.report') }, { name: 'block', label: t('chat.block') }]}
                      onAccessibilityAction={(e) => {
                        const other = { id: m.sender_id, name: m.sender.name };
                        const hide = () => setMsgs((cur) => (cur ?? []).filter((x) => x.sender_id !== m.sender_id));
                        if (e.nativeEvent.actionName === 'report') openReportFlow({ t, sheet, me, other, onDone: hide });
                        if (e.nativeEvent.actionName === 'block') confirmBlock({ t, me, other, onDone: hide });
                      }}
                      style={[styles.bubble, mine ? styles.mine : styles.theirs, groupEnd && (mine ? styles.tailMine : styles.tailTheirs)]}>
                      {!mine && groupStart ? (
                        <Text maxFontSizeMultiplier={1.4} style={styles.name}>{m.sender.name} <Text maxFontSizeMultiplier={1.6} style={styles.no}>{memberNo(m.sender.member_no)}</Text></Text>
                      ) : null}
                      <Text maxFontSizeMultiplier={2} style={[styles.body, mine && { color: colors.white }]}>{m.body}</Text>
                    </Pressable>
                  </View>
                </View>
              );
            }}
          />
          <View style={styles.composer}>
            <TextInput value={text} onChangeText={setText} placeholder={t('chat.placeholder')} placeholderTextColor={colors.hint}
              style={styles.input} multiline maxLength={1000} />
            <Pressable onPress={send} disabled={!text.trim() || sending} style={[styles.send, !text.trim() && { opacity: 0.4 }]}
              accessibilityRole="button" accessibilityLabel={t('chat.send')}>
              <Icon name="send" size={17} color="white" weight="bold" />
            </Pressable>
          </View>
        </KeyboardAvoidingView>
      )}
    </SafeAreaView>
  );
}

const AVATAR = 28;

const styles = StyleSheet.create({
  empty: { ...type.footnote, textAlign: 'center', color: colors.muted, marginTop: sp.xxl, transform: [{ scaleY: -1 }] },
  divider: { ...type.caption, fontFamily: fonts.text600, textAlign: 'center', color: colors.muted, marginTop: sp.md, marginBottom: sp.sm },
  line: { flexDirection: 'row', alignItems: 'flex-end', gap: sp.sm },
  avatar: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2, backgroundColor: colors.line },
  avatarSpace: { width: AVATAR },
  bubble: { maxWidth: '78%', paddingHorizontal: 14, paddingVertical: sp.sm, borderRadius: 18, ...curve },
  mine: { backgroundColor: colors.blue },
  theirs: { backgroundColor: colors.card },
  tailMine: { borderBottomRightRadius: 4 },
  tailTheirs: { borderBottomLeftRadius: 4 },
  name: { ...type.caption, color: colors.clayDeep, marginBottom: sp.xxs },
  no: { fontFamily: fonts.text700, fontSize: 11, color: colors.muted, fontVariant: ['tabular-nums'] },
  body: { ...type.body, lineHeight: 22, color: colors.ink },
  composer: {
    flexDirection: 'row', alignItems: 'flex-end', gap: sp.sm, paddingVertical: sp.sm, paddingHorizontal: sp.md,
    borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line, backgroundColor: colors.card,
  },
  input: {
    flex: 1, minHeight: 36, maxHeight: 120, backgroundColor: colors.bg, borderRadius: 18, ...curve, paddingHorizontal: 14,
    paddingTop: 8, paddingBottom: 8, ...type.body, lineHeight: undefined, color: colors.ink,
  },
  send: { width: 34, height: 34, borderRadius: 17, backgroundColor: colors.blue, alignItems: 'center', justifyContent: 'center', marginBottom: 1 },
});
