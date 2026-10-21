// The four-person chat for a double date.
import { useLocalSearchParams } from 'expo-router';
import React from 'react';
import { GroupChat } from '../../../src/components/GroupChat';
import { useI18n } from '../../../src/i18n';
import { api } from '../../../src/lib/api';
import { useSession } from '../../../src/lib/session';

export default function DuoChat() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useI18n();
  const { profile } = useSession();
  return (
    <GroupChat channel={`duo:${id}`} table="duo_messages" filter={`duo_match_id=eq.${id}`}
      fetchPage={(before) => api.duoFeed(id, before)}
      send={(body) => api.sendDuoMessage(id, profile?.id ?? '', body)}
      empty={t('duo.matched')} />
  );
}
