// Today's picks (Hinge "Most Compatible"): five people a day, chosen for the
// sports, events and clubs you share. The same five all day; new ones each evening.
import { useRouter } from 'expo-router';
import React, { useCallback, useEffect, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { Mark } from '../src/components/Brand';
import { Icon } from '../src/components/Icon';
import { MatchMoment } from '../src/components/MatchMoment';
import { NoteSheet } from '../src/components/NoteSheet';
import { ProfileCardView } from '../src/components/ProfileCard';
import { toast } from '../src/components/Toast';
import { Button, Empty, ErrorState, Row, SkeletonList, T, Tag } from '../src/components/ui';
import { useI18n } from '../src/i18n';
import { api } from '../src/lib/api';
import { feedback } from '../src/lib/feedback';
import { useSession } from '../src/lib/session';
import { colors, layout, lightPalette, sp, type } from '../src/lib/theme';
import type { ProfileCard, PromptKey, SwipeKind } from '../src/lib/types';
import { features } from '../src/lib/features';

export default function Picks() {
  const { t } = useI18n();
  const router = useRouter();
  const { profile, refreshLimits } = useSession();
  const [picks, setPicks] = useState<ProfileCard[] | null>(null);
  const [note, setNote] = useState<{ p: ProfileCard; prompt?: PromptKey } | null>(null);
  const [match, setMatch] = useState<{ id: string; other: ProfileCard } | null>(null);

  const [failed, setFailed] = useState(false);
  const load = useCallback(async () => {
    try { setFailed(false); setPicks(await api.dailyPicks()); } catch { setFailed(true); }
  }, []);
  useEffect(() => { load(); }, [load]);

  async function swipe(p: ProfileCard, kind: SwipeKind, text?: string, prompt?: PromptKey) {
    try {
      const r = await api.swipe(p.id, kind, text, prompt);
      if (!r.ok) {
        if (r.error === 'like_limit' || r.error === 'super_limit') router.push('/paywall');
        return;
      }
      setPicks((cur) => (cur ?? []).map((x) => (x.id === p.id ? { ...x, my_swipe: kind } : x)));
      if (r.match_id) setMatch({ id: r.match_id, other: p });
      else if (kind !== 'pass') feedback(kind === 'super' ? 'super' : 'like');
      refreshLimits();
    } catch {
      toast(t('common.error'), { error: true });
    }
  }

  if (failed && picks === null) return <ErrorState onRetry={load} />;
  if (picks === null) return <SkeletonList kind="card" rows={3} />;
  if (picks.length === 0) return <Empty icon="sparkle" title={t('picks.empty')} sub={t('picks.emptySub')} />;

  return (
    <>
      <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 }}>
        <T variant="callout">{features.events ? t('picks.sub') : t('picks.subApp')}</T>
        {picks.map((p, i) => (
          <View key={p.id} style={{ gap: sp.md }}>
            <View style={styles.indexRow}>
              <Text maxFontSizeMultiplier={1.3} style={styles.index}>{i + 1} / {picks.length}</Text>
              {p.my_swipe ? (
                <Tag tone={p.my_swipe === 'pass' ? 'neutral' : 'good'} icon={p.my_swipe === 'pass' ? 'close' : 'tick'}
                  label={p.my_swipe === 'pass' ? t('picks.passed') : t('picks.liked')} />
              ) : null}
            </View>
            <ProfileCardView p={p} onComment={p.my_swipe ? undefined : (k) => setNote({ p, prompt: k })} />
            {p.my_swipe ? null : (
              <Row>
                <Button title="" accessibilityLabel="pass" variant="secondary" onPress={() => swipe(p, 'pass')} style={{ flex: 1 }}
                  icon={<Icon name="close" size={24} color="clay" weight="bold" />} />
                <Button title="" accessibilityLabel={t('note.add')} variant="secondary" onPress={() => setNote({ p })} style={{ flex: 1 }}
                  icon={<Icon name="note" size={22} color="blueText" />} />
                <Button title="" accessibilityLabel="like" onPress={() => swipe(p, 'like')} style={{ flex: 1.5 }}
                  icon={<Mark size={30} color={lightPalette.gold} />} />
              </Row>
            )}
          </View>
        ))}
      </ScrollView>
      <NoteSheet visible={!!note} name={note?.p.name ?? ''} challenge={note?.p.next_challenge}
        prompt={note?.prompt ? note.p.prompts?.find((q) => q.key === note.prompt) : null}
        onClose={() => setNote(null)}
        onSend={(text) => { const n = note; setNote(null); if (n) swipe(n.p, 'like', text, n.prompt); }} />
      <MatchMoment visible={!!match} buddy={match?.other.match_mode === 'buddy'} name={match?.other.name ?? ''}
        myPhoto={profile?.photos[0]} theirPhoto={match?.other.photos[0]} onClose={() => setMatch(null)}
        onWrite={() => { const m = match; setMatch(null); if (m) router.push(`/chat/${m.id}`); }} />
    </>
  );
}

const styles = StyleSheet.create({
  indexRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', minHeight: 24 },
  index: { ...type.overline, color: colors.clayDeep, fontVariant: ['tabular-nums'] },
});
