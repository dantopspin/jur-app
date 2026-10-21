import { Image } from 'expo-image';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator, Alert, FlatList, KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Icon } from '../../src/components/Icon';
import { Empty, ErrorState, Loading } from '../../src/components/ui';
import { HeaderIconButton } from '../../src/components/HeaderButton';
import { toast } from '../../src/components/Toast';
import { refreshUnread } from '../../src/lib/unread';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { formatDivider, formatShortDate, needsDivider } from '../../src/lib/dates';
import { feedback } from '../../src/lib/feedback';
import { useSession } from '../../src/lib/session';
import { supabase } from '../../src/lib/supabase';
import { colors, curve, fonts, iconSize, layout, radius, shadowSoft, sp, type } from '../../src/lib/theme';
import type { EventItem, MatchRow, Message } from '../../src/lib/types';
import { currentSeason, useSports } from '../../src/lib/sports';
import { formatEventTime } from '../../src/lib/dates';
import { confirmBlock, openReportFlow } from '../../src/lib/safety';
import { useSheet } from '../../src/components/Sheet';
import { DateCard } from '../../src/components/chat/DateCard';
import { DateSheet } from '../../src/components/chat/DateSheet';
import { PhotoBubble, VoiceBubble } from '../../src/components/chat/MediaBubbles';
import { MessageActions } from '../../src/components/chat/MessageActions';
import { uploadChatPhoto, uploadVoice } from '../../src/lib/chatMedia';
import { useVoiceRecorder } from '../../src/lib/voice';
import { pickPhoto } from '../../src/lib/upload';
import { bump, knock, tick } from '../../src/lib/haptics';
import type { TKey } from '../../src/i18n';

export default function Chat() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t, intl, sportName } = useI18n();
  const { byCode } = useSports();
  const router = useRouter();
  const { profile } = useSession();
  const sheet = useSheet();
  const me = profile?.id ?? '';
  const [match, setMatch] = useState<MatchRow | null>(null);
  const [messages, setMessages] = useState<Message[] | null>(null);
  /** 'failed': couldn't load; 'gone': the match no longer exists (unmatched, blocked, old push) */
  const [state, setState] = useState<'ok' | 'failed' | 'gone'>('ok');
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [shared, setShared] = useState<EventItem[]>([]);
  const [profileSports, setProfileSports] = useState<string[]>([]);
  useEffect(() => { api.mySports().then((r) => setProfileSports(r.map((x) => x.sport_code))).catch(() => {}); }, []);
  const loadingOlder = useRef(false);
  const reachedStart = useRef(false);
  const [replyTo, setReplyTo] = useState<Message | null>(null);
  const [acting, setActing] = useState<Message | null>(null);
  const [dateOpen, setDateOpen] = useState(false);
  const [uploading, setUploading] = useState(false);
  const voice = useVoiceRecorder();

  /** Merge a fresh first page into what we have (new, edited and reacted messages). */
  const refresh = useCallback(async () => {
    const page = await api.chatMessages(id);
    setMessages((cur) => {
      const byId = new Map((cur ?? []).map((m) => [m.id, m]));
      for (const m of page) byId.set(m.id, m);
      return [...byId.values()].sort((a, b) => b.created_at.localeCompare(a.created_at));
    });
  }, [id]);

  const load = useCallback(async () => {
    const all = await api.matches();
    const m = all.find((r) => r.match_id === id) ?? null;
    setMatch(m);
    if (!m) { setState('gone'); return; }
    setMessages(await api.chatMessages(id));
    setState('ok');
    api.markRead(id).then(refreshUnread).catch(() => {});
    api.sharedEvents(id).then(setShared).catch(() => {});
  }, [id]);

  const retry = useCallback(() => {
    setState('ok');
    load().catch(() => setState('failed'));
  }, [load]);
  useEffect(() => { retry(); }, [retry]);

  // Realtime: new messages in this chat.
  useEffect(() => {
    const ch = supabase
      .channel(`chat:${id}`)
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'messages', filter: `match_id=eq.${id}` },
        (payload) => {
          const msg = payload.new as Message;
          refresh().catch(() => {});
          if (msg.sender_id !== me) {
            api.markRead(id).then(refreshUnread).catch(() => {});
            feedback('message');
          }
        })
      // reactions and date answers touch the message row
      .on('postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'messages', filter: `match_id=eq.${id}` },
        () => { refresh().catch(() => {}); })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, me, refresh]);

  async function loadOlder() {
    if (!messages?.length || loadingOlder.current || reachedStart.current) return;
    loadingOlder.current = true;
    try {
      const older = await api.chatMessages(id, messages[messages.length - 1].created_at);
      if (older.length === 0) reachedStart.current = true;
      setMessages((cur) => [...(cur ?? []), ...older.filter((o) => !(cur ?? []).some((c) => c.id === o.id))]);
    } finally {
      loadingOlder.current = false;
    }
  }

  async function send() {
    const body = text.trim();
    if (!body || sending) return;
    setSending(true);
    setText('');
    const reply = replyTo;
    setReplyTo(null);
    try {
      await api.send(id, me, body, reply?.id);
      await refresh();
    } catch {
      setText(body);
      toast(t('chat.sendFailed'), { error: true });
    } finally {
      setSending(false);
    }
  }

  async function sendPhoto() {
    try {
      const img = await pickPhoto();
      if (!img) return;
      setUploading(true);
      const path = await uploadChatPhoto(id, img);
      await api.sendMedia(id, me, { kind: 'photo', path, replyTo: replyTo?.id });
      setReplyTo(null);
      await refresh();
    } catch (e) {
      const tooSoon = e instanceof Error && e.message.includes('photo_too_soon');
      toast(tooSoon ? t('safety.photosLockedSub') : t('chat.sendFailed'), { error: true });
    } finally {
      setUploading(false);
    }
  }

  async function micPress() {
    if (!voice.recording) {
      const ok = await voice.start();
      if (!ok) Alert.alert(t('chat2.micDenied'));
      else bump();
      return;
    }
    const rec = await voice.stop(true);
    if (!rec) return;
    setUploading(true);
    try {
      const path = await uploadVoice(id, rec.uri);
      await api.sendMedia(id, me, { kind: 'voice', path, ms: rec.ms, replyTo: replyTo?.id });
      setReplyTo(null);
      await refresh();
    } catch {
      toast(t('chat.sendFailed'), { error: true });
    } finally {
      setUploading(false);
    }
  }

  // Photo safety: photos unlock once both people have written (the server enforces it too).
  const photosUnlocked = !!messages?.some((x) => x.kind === 'text' && x.sender_id === me)
    && !!messages?.some((x) => x.kind === 'text' && x.sender_id !== me);

  function attach() {
    sheet({
      cancelLabel: t('common.cancel'),
      options: [
        { label: t('chat2.suggest'), onPress: () => setDateOpen(true) },
        photosUnlocked
          ? { label: t('chat2.photo'), onPress: sendPhoto }
          : { label: `${t('chat2.photo')} · ${t('safety.photosLocked')}`, onPress: () => toast(t('safety.photosLockedSub'), { icon: 'lock' }) },
      ],
    });
  }

  function preview(m: { kind: Message['kind']; body: string }) {
    return m.kind === 'photo' ? t('chat2.photo') : m.kind === 'voice' ? t('chat2.voice') : m.kind === 'date' ? t('chat2.dateCard') : m.body;
  }

  function menu() {
    if (!match) return;
    const name = match.other.name;
    sheet({
      cancelLabel: t('common.cancel'),
      options: [
        { label: t('chat.viewProfile'), onPress: () => router.push(`/profile/${match.other.id}`) },
        { label: t('chat.report'), onPress: () => openReportFlow({ t, sheet, me, other: match.other, onDone: () => router.back() }) },
        { label: t('chat.block'), destructive: true, onPress: () => confirmBlock({ t, me, other: match.other, onDone: () => router.back() }) },
        {
          label: t('chat.unmatch'), destructive: true,
          onPress: () => Alert.alert(t('chat.unmatch'), t('chat.unmatchConfirm', { name }), [
            { text: t('common.cancel'), style: 'cancel' },
            { text: t('chat.unmatch'), style: 'destructive', onPress: async () => { await api.unmatch(id); router.back(); } },
          ]),
        },
      ],
    });
  }

  // Conversation starters for an empty chat, built from their profile and shared plans.
  const openers: string[] = [];
  if (match && messages?.length === 0) {
    if (shared[0]) openers.push(t('openers.event', { event: shared[0].title }));
    if (match.other.next_challenge) openers.push(t('openers.challenge', { challenge: match.other.next_challenge }));
    const season = currentSeason();
    const inSeason = match.other.sports.find((x) => {
      const sp = byCode[x.code];
      return sp && (sp.season === season || sp.season === 'all');
    }) ?? match.other.sports[0];
    const sp = inSeason ? byCode[inSeason.code] : undefined;
    if (sp) openers.push(t('openers.sport', { sport: sportName(sp) }));
    openers.push(t('dastarkhan.tea'));
    openers.push(t('openers.weekend'));
  }

  const header = (
    <Stack.Screen options={{
      headerTitle: () => match ? (
        <Pressable onPress={() => router.push(`/profile/${match.other.id}`)} style={({ pressed }) => [styles.headerTitle, pressed && { opacity: 0.6 }]}
          accessibilityRole="button" accessibilityLabel={match.other.name} accessibilityHint={t('chat.viewProfile')}>
          <Image source={{ uri: match.other.photos[0] }} style={styles.headerAvatar} />
          <Text maxFontSizeMultiplier={1.3} style={styles.headerName} numberOfLines={1}>{match.other.name}</Text>
          <Icon name="forward" size={11} color="hint" />
        </Pressable>
      ) : null,
      headerRight: () => (
        <HeaderIconButton icon="more" label={t('chat.menu')} onPress={menu} />
      ),
    }} />
  );

  if (state === 'gone') {
    return (
      <>{header}
        <Empty icon="chats" title={t('chat.gone')} sub={t('chat.goneSub')} action={t('common.back')} onAction={() => router.back()} />
      </>
    );
  }
  if (state === 'failed' && messages === null) return <>{header}<ErrorState onRetry={retry} /></>;
  if (messages === null) return <>{header}<Loading /></>;

  return (
    <SafeAreaView edges={['bottom']} style={{ flex: 1, backgroundColor: colors.bg }}>
      {header}
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={90}>
        <FlatList
          inverted
          data={messages}
          keyExtractor={(m) => m.id}
          onEndReached={loadOlder}
          onEndReachedThreshold={0.3}
          contentContainerStyle={{ paddingHorizontal: layout.margin, paddingVertical: sp.md }}
          ListFooterComponent={match ? (
            <View style={{ gap: sp.md, marginBottom: sp.sm }}>
              {shared.map((e) => (
                <Pressable key={e.id} style={styles.going} onPress={() => router.push(`/event/${e.id}`)} accessibilityRole="button">
                  <Icon name="flag" size={iconSize.row} color="gold" />
                  <Text maxFontSizeMultiplier={1.6} style={styles.goingText} numberOfLines={2}>
                    {t('openers.bothGoing', { event: e.title, when: formatEventTime(e.starts_at, intl) })}
                  </Text>
                  <Icon name="forward" size={iconSize.inline} color="blueMist" />
                </Pressable>
              ))}
              <Text maxFontSizeMultiplier={1.6} style={styles.icebreaker}>
                {t('chat.icebreaker', { when: formatShortDate(match.created_at, intl) })}
              </Text>
            </View>
          ) : null}
          renderItem={({ item: m, index }) => {
            const mine = m.sender_id === me;
            const reactions = m.reactions ?? [];
            // The list is inverted: index + 1 is the older message, index - 1 the newer one.
            const older = messages[index + 1];
            const newer = messages[index - 1];
            const divider = needsDivider(older?.created_at, m.created_at);
            const groupStart = divider || !older || older.sender_id !== m.sender_id || older.kind === 'date';
            const groupEnd = !newer || newer.sender_id !== m.sender_id || needsDivider(m.created_at, newer.created_at) || newer.kind === 'date';
            const lastMineRead = mine && m.read_at && !messages.slice(0, index).some((x) => x.sender_id === me);
            const dividerEl = divider ? <Text maxFontSizeMultiplier={1.4} style={styles.divider}>{formatDivider(m.created_at, intl)}</Text> : null;
            if (m.kind === 'date') {
              return (
                <View style={{ marginTop: sp.sm }}>
                  {dividerEl}
                  <Pressable onLongPress={() => { knock(); setActing(m); }} delayLongPress={300} style={{ alignSelf: mine ? 'flex-end' : 'flex-start' }}>
                    <DateCard m={m} mine={mine} onAnswered={refresh} />
                  </Pressable>
                </View>
              );
            }
            return (
              <View style={{ marginTop: groupStart ? sp.sm : sp.xxs }}>
              {dividerEl}
              <View style={{ alignSelf: mine ? 'flex-end' : 'flex-start', maxWidth: '80%' }}>
                {m.payload?.prompt ? (
                  <View style={[styles.promptQuote, mine && { alignSelf: 'flex-end' }]}>
                    <Text maxFontSizeMultiplier={1.6} style={styles.promptQ}>{t(`prompts.${m.payload.prompt.key}` as TKey)}</Text>
                    <Text maxFontSizeMultiplier={1.6} style={styles.promptA} numberOfLines={2}>{m.payload.prompt.answer}</Text>
                  </View>
                ) : null}
                <Pressable onLongPress={() => { knock(); setActing(m); }} delayLongPress={300}
                  style={[styles.bubble, mine ? styles.mine : styles.theirs, groupEnd && (mine ? styles.tailMine : styles.tailTheirs),
                    m.kind === 'photo' && styles.photoBubble]}
                  accessibilityHint={t('chat2.reply')}>
                  {m.reply ? (
                    <View style={[styles.quote, mine && styles.quoteMine]}>
                      <Text maxFontSizeMultiplier={1.6} style={[styles.quoteText, mine && { color: colors.blueMist }]} numberOfLines={2}>{preview(m.reply)}</Text>
                    </View>
                  ) : null}
                  {m.kind === 'photo' && m.media_path ? <PhotoBubble path={m.media_path} label={t('chat2.photo')} mine={mine}
                      hiddenLabel={t('safety.tapToView')} warnLabel={t('safety.mayContainNudity')} />
                    : m.kind === 'voice' && m.media_path ? <VoiceBubble path={m.media_path} ms={m.media_ms} mine={mine} label={t('chat2.voice')} />
                    : <Text maxFontSizeMultiplier={2} style={[styles.body, mine && { color: colors.white }]}>{m.body}</Text>}
                </Pressable>
                {reactions.length > 0 ? (
                  <View style={[styles.reactions, mine ? { alignSelf: 'flex-end' } : { alignSelf: 'flex-start' }]}>
                    {reactions.map((r) => <Icon key={r.profile_id} name={r.reaction} size={iconSize.inline}
                      color={r.reaction === 'heart' ? 'danger' : r.reaction === 'fire' ? 'clay' : 'blueText'} />)}
                  </View>
                ) : null}
                {lastMineRead ? <Text maxFontSizeMultiplier={1.4} style={styles.read}>{t('chat2.read')}</Text> : null}
              </View>
              </View>
            );
          }}
        />
        {openers.length > 0 && (
          <View style={styles.openers}>
            <Text maxFontSizeMultiplier={1.6} style={styles.openersTitle}>{t('openers.title')}</Text>
            <FlatList
              horizontal
              data={openers}
              keyExtractor={(o) => o}
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={{ gap: sp.sm, paddingHorizontal: layout.margin }}
              renderItem={({ item: o }) => (
                <Pressable style={styles.opener} onPress={() => setText(o)} accessibilityRole="button">
                  <Text maxFontSizeMultiplier={1.4} style={styles.openerText} numberOfLines={1}>{o}</Text>
                </Pressable>
              )}
            />
          </View>
        )}
        {replyTo ? (
          <View style={styles.replyBar}>
            <Icon name="reply" size={iconSize.row} color="blueText" />
            <View style={{ flex: 1 }}>
              <Text maxFontSizeMultiplier={1.6} style={styles.replyLabel}>{t('chat2.replyingTo', { name: replyTo.sender_id === me ? (profile?.name ?? '') : (match?.other.name ?? '') })}</Text>
              <Text maxFontSizeMultiplier={1.6} style={styles.replyText} numberOfLines={1}>{preview(replyTo)}</Text>
            </View>
            <Pressable onPress={() => setReplyTo(null)} hitSlop={10} accessibilityRole="button" accessibilityLabel={t('chat2.cancel')}>
              <Icon name="close" size={iconSize.inline} color="muted" weight="bold" />
            </Pressable>
          </View>
        ) : null}
        <View style={styles.composer}>
          {voice.recording ? (
            <>
              <Pressable onPress={() => voice.stop(false)} hitSlop={8} style={styles.tool} accessibilityRole="button" accessibilityLabel={t('chat2.cancel')}>
                <Icon name="close" size={18} color="danger" weight="bold" />
              </Pressable>
              <View style={styles.recording}>
                <View style={styles.dot} />
                <Text maxFontSizeMultiplier={1.6} style={styles.recordingText}>{t('chat2.hold')} · {Math.floor(voice.ms / 60000)}:{String(Math.floor(voice.ms / 1000) % 60).padStart(2, '0')}</Text>
              </View>
              <Pressable onPress={micPress} style={styles.send} accessibilityRole="button" accessibilityLabel={t('chat.send')}>
                <Icon name="send" size={17} color="white" weight="bold" />
              </Pressable>
            </>
          ) : (
            <>
              <Pressable onPress={attach} style={styles.tool} hitSlop={6} accessibilityRole="button" accessibilityLabel={t('chat2.attach')}>
                <Icon name="add" size={18} color="blueText" weight="bold" />
              </Pressable>
              <TextInput
                value={text}
                onChangeText={setText}
                placeholder={t('chat.placeholder')}
                placeholderTextColor={colors.hint}
                style={styles.input}
                multiline
                maxLength={2000}
              />
              {text.trim() ? (
                <Pressable onPress={send} disabled={sending} style={styles.send} accessibilityRole="button" accessibilityLabel={t('chat.send')}>
                  <Icon name="send" size={17} color="white" weight="bold" />
                </Pressable>
              ) : (
                <Pressable onPress={micPress} disabled={uploading} style={[styles.send, styles.mic]} accessibilityRole="button"
                  accessibilityLabel={t('chat2.mic')}>
                  {uploading ? <ActivityIndicator /> : <Icon name="mic" size={17} color="blueText" />}
                </Pressable>
              )}
            </>
          )}
        </View>
      </KeyboardAvoidingView>
      <MessageActions message={acting} meId={me} onClose={() => setActing(null)}
        onReact={async (r) => { const m = acting; setActing(null); if (m) { await api.react(m.id, r).catch(() => {}); refresh(); } }}
        onReply={() => { tick(); setReplyTo(acting); setActing(null); }} />
      {match ? (
        <DateSheet visible={dateOpen} matchId={id} onClose={() => setDateOpen(false)}
          sportCodes={match.other.sports.map((x) => x.code).filter((c) => profileSports.includes(c)).concat(
            match.other.sports.map((x) => x.code).filter((c) => !profileSports.includes(c))).slice(0, 6)}
          onSent={() => { setDateOpen(false); refresh(); }} />
      ) : null}
    </SafeAreaView>
  );
}

const BUBBLE = 18;
const CONTROL = 34;

const styles = StyleSheet.create({
  headerTitle: { flexDirection: 'row', alignItems: 'center', gap: sp.sm, maxWidth: 220 },
  headerAvatar: { width: 28, height: 28, borderRadius: 14, backgroundColor: colors.line },
  headerName: { ...type.headline, color: colors.ink, flexShrink: 1 },
  icebreaker: { ...type.footnote, textAlign: 'center', color: colors.muted, marginVertical: sp.lg, paddingHorizontal: sp.lg },
  divider: { ...type.caption, fontFamily: fonts.text600, textAlign: 'center', color: colors.muted, marginTop: sp.md, marginBottom: sp.sm },
  bubble: { paddingHorizontal: 14, paddingVertical: sp.sm, borderRadius: BUBBLE, ...curve },
  mine: { alignSelf: 'flex-end', backgroundColor: colors.blue },
  theirs: { alignSelf: 'flex-start', backgroundColor: colors.card },
  tailMine: { borderBottomRightRadius: 4 },
  tailTheirs: { borderBottomLeftRadius: 4 },
  body: { ...type.body, lineHeight: 22, color: colors.ink },
  read: { ...type.caption, fontFamily: fonts.text600, color: colors.muted, alignSelf: 'flex-end', marginTop: sp.xs },
  photoBubble: { padding: 3, backgroundColor: 'transparent' },
  promptQuote: {
    alignSelf: 'flex-start', backgroundColor: colors.blueTint, borderRadius: radius.md, paddingHorizontal: sp.md,
    paddingVertical: sp.sm, marginBottom: sp.xs, maxWidth: 260, gap: sp.xxs,
  },
  promptQ: { ...type.caption, fontFamily: fonts.text600, color: colors.muted },
  promptA: { ...type.footnote, fontFamily: fonts.text600, color: colors.blueText },
  quote: { borderLeftWidth: 3, borderLeftColor: colors.blueText, paddingLeft: sp.sm, marginBottom: sp.xs + 2 },
  quoteMine: { borderLeftColor: colors.blueMist },
  quoteText: { ...type.footnote, color: colors.muted },
  reactions: {
    flexDirection: 'row', gap: 3, marginTop: -sp.sm, marginHorizontal: sp.sm, backgroundColor: colors.card, borderRadius: radius.pill,
    paddingHorizontal: 7, paddingVertical: 4, ...shadowSoft, shadowOpacity: 0.1,
  },
  replyBar: {
    flexDirection: 'row', alignItems: 'center', gap: sp.md, paddingHorizontal: layout.margin, paddingVertical: sp.sm,
    borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line, backgroundColor: colors.card,
  },
  replyLabel: { ...type.caption, color: colors.blueText },
  replyText: { ...type.footnote, color: colors.muted },
  tool: { width: CONTROL, height: CONTROL, borderRadius: CONTROL / 2, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center', marginBottom: 1 },
  mic: { backgroundColor: colors.blueTint },
  recording: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: sp.sm, minHeight: 36 },
  dot: { width: 10, height: 10, borderRadius: 5, backgroundColor: colors.danger },
  recordingText: { ...type.callout, color: colors.inkSoft, fontVariant: ['tabular-nums'] },
  composer: {
    flexDirection: 'row', alignItems: 'flex-end', gap: sp.sm, paddingVertical: sp.sm, paddingHorizontal: sp.md,
    borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line, backgroundColor: colors.card,
  },
  input: {
    flex: 1, minHeight: 36, maxHeight: 120, backgroundColor: colors.bg, borderRadius: 18, ...curve, paddingHorizontal: 14,
    paddingTop: 8, paddingBottom: 8, ...type.body, lineHeight: undefined, color: colors.ink,
  },
  going: {
    flexDirection: 'row', alignItems: 'center', gap: sp.md, backgroundColor: colors.blue, borderRadius: radius.md, ...curve,
    paddingHorizontal: sp.lg, paddingVertical: sp.md,
  },
  goingText: { flex: 1, ...type.callout, fontFamily: fonts.text700, color: colors.white },
  openers: { gap: sp.sm, paddingVertical: sp.sm, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line },
  openersTitle: { ...type.overline, paddingHorizontal: layout.margin, color: colors.muted },
  opener: {
    maxWidth: 280, backgroundColor: colors.blueTint, borderRadius: radius.pill, paddingHorizontal: 14, paddingVertical: sp.sm,
  },
  openerText: { ...type.callout, color: colors.blueText },
  send: { width: CONTROL, height: CONTROL, borderRadius: CONTROL / 2, backgroundColor: colors.blue, alignItems: 'center', justifyContent: 'center', marginBottom: 1 },
});
