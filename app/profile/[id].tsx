import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { Pressable, ScrollView } from 'react-native';
import { Mark } from '../../src/components/Brand';
import { Icon } from '../../src/components/Icon';
import { MatchMoment } from '../../src/components/MatchMoment';
import { NoteSheet } from '../../src/components/NoteSheet';
import { ProfileCardView } from '../../src/components/ProfileCard';
import { useSheet } from '../../src/components/Sheet';
import { Button, Empty, Loading, Row, Screen } from '../../src/components/ui';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { feedback } from '../../src/lib/feedback';
import { confirmBlock, openReportFlow } from '../../src/lib/safety';
import { useSession } from '../../src/lib/session';
import { lightPalette, space } from '../../src/lib/theme';
import type { ProfileCard, PromptKey, SwipeKind } from '../../src/lib/types';
import { showError } from '../../src/lib/errors';

/** Someone else's profile, opened from a chat, an event or the likes list. */
export default function ProfileScreen() {
  const { id, from } = useLocalSearchParams<{ id: string; from?: string }>();
  const { t } = useI18n();
  const router = useRouter();
  const sheet = useSheet();
  const { profile, refreshLimits } = useSession();
  const me = profile?.id ?? '';
  const [p, setP] = useState<ProfileCard | null | undefined>(undefined);
  const [done, setDone] = useState<SwipeKind | null>(null);
  const [noteOpen, setNoteOpen] = useState(false);
  const [notePrompt, setNotePrompt] = useState<PromptKey | undefined>(undefined);
  const [matchId, setMatchId] = useState<string | null>(null);

  useEffect(() => {
    api.getProfile(id).then(setP).catch(() => setP(null));
  }, [id]);

  async function swipe(kind: SwipeKind, note?: string, prompt?: PromptKey) {
    try {
      const r = await api.swipe(id, kind, note, prompt);
      if (!r.ok) {
        if (r.error === 'like_limit' || r.error === 'super_limit') router.push('/paywall');
        return;
      }
      setDone(kind);
      if (!r.match_id && kind !== 'pass') feedback(kind === 'super' ? 'super' : 'like');
      refreshLimits();
      if (r.match_id) setMatchId(r.match_id); // MatchMoment plays its own sound
    } catch (e) {
      showError(t, e);
    }
  }

  const showActions = from === 'likes' || from === 'event';

  return (
    <Screen edges={['bottom']}>
      <Stack.Screen options={{
        title: p?.name ?? '',
        headerRight: () => p && p.id !== me ? (
          <Pressable hitSlop={12} onPress={() => sheet({
            cancelLabel: t('common.cancel'),
            options: [
              { label: t('chat.report'), onPress: () => openReportFlow({ t, sheet, me, other: p, onDone: () => router.back() }) },
              { label: t('chat.block'), destructive: true, onPress: () => confirmBlock({ t, me, other: p, onDone: () => router.back() }) },
            ],
          })}>
            <Icon name="more" size={22} color="blueText" />
          </Pressable>
        ) : null,
      }} />
      {p === undefined ? <Loading /> : p === null ? <Empty title={t('common.error')} /> : (
        <ScrollView contentContainerStyle={{ padding: space(2), gap: space(2), paddingBottom: space(6) }}>
          <ProfileCardView p={p} onComment={showActions && !done && p.id !== me ? (k) => { setNotePrompt(k); setNoteOpen(true); } : undefined} />
          {showActions && p.id !== me && (
            done ? (
              <Button title={t('common.close')} variant="secondary" onPress={() => router.back()} />
            ) : (
              <Row>
                <Button title="" accessibilityLabel="pass" variant="secondary" onPress={() => swipe('pass')} style={{ flex: 1 }}
                  icon={<Icon name="close" size={24} color="clay" weight="bold" />} />
                <Button title="" accessibilityLabel="super like" variant="secondary" onPress={() => swipe('super')} style={{ flex: 1 }}
                  icon={<Icon name="star" size={22} color="gold" />} />
                <Button title="" accessibilityLabel={t('note.add')} variant="secondary" onPress={() => { setNotePrompt(undefined); setNoteOpen(true); }} style={{ flex: 1 }}
                  icon={<Icon name="note" size={22} color="blueText" />} />
                <Button title="" accessibilityLabel="like" onPress={() => swipe('like')} style={{ flex: 1.5 }}
                  icon={<Mark size={30} color={lightPalette.gold} />} />
              </Row>
            )
          )}
        </ScrollView>
      )}
      {p ? (
        <NoteSheet visible={noteOpen} name={p.name} challenge={p.next_challenge}
          prompt={notePrompt ? p.prompts?.find((q) => q.key === notePrompt) : null}
          onClose={() => setNoteOpen(false)} onSend={(note) => { setNoteOpen(false); swipe('like', note, notePrompt); }} />
      ) : null}
      <MatchMoment
        visible={!!matchId}
        name={p?.name ?? ''}
        myPhoto={profile?.photos[0]}
        theirPhoto={p?.photos[0]}
        onClose={() => setMatchId(null)}
        onWrite={() => { const m = matchId; setMatchId(null); if (m) router.replace(`/chat/${m}`); }}
      />
    </Screen>
  );
}
