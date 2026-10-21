// Club group chat: plans, routes, who's driving.
import { Stack, useLocalSearchParams } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { GroupChat } from '../../../src/components/GroupChat';
import { useI18n } from '../../../src/i18n';
import { api } from '../../../src/lib/api';
import { useSession } from '../../../src/lib/session';

export default function ClubChat() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useI18n();
  const { profile } = useSession();
  const [title, setTitle] = useState('');
  useEffect(() => { api.club(id).then((c) => setTitle(c?.name ?? '')).catch(() => {}); }, [id]);
  return (
    <>
      <Stack.Screen options={{ title: title || t('clubs.chat') }} />
      <GroupChat channel={`club:${id}`} table="club_messages" filter={`club_id=eq.${id}`}
        fetchPage={(before) => api.clubFeed(id, before)}
        send={(body) => api.sendClubMessage(id, profile?.id ?? '', body)}
        empty={t('clubs.chatEmpty')} />
    </>
  );
}
