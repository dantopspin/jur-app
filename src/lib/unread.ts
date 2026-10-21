// Unread message count for the Matches tab badge (and the app icon widget).
// Refreshes on launch, when the app comes to the foreground, on any new message,
// and when a chat marks messages as read.
import { useEffect, useState } from 'react';
import { AppState } from 'react-native';
import { api } from './api';
import { useSession } from './session';
import { supabase } from './supabase';

const listeners = new Set<() => void>();

/** Call after marking a chat as read. */
export function refreshUnread() {
  listeners.forEach((l) => l());
}

export function useUnread(): number {
  const { profile } = useSession();
  const [n, setN] = useState(0);

  useEffect(() => {
    if (!profile) return;
    let alive = true;
    const load = () => api.matches()
      .then((rows) => { if (alive) setN(rows.reduce((sum, r) => sum + r.unread, 0)); })
      .catch(() => {});
    load();
    listeners.add(load);
    const app = AppState.addEventListener('change', (s) => { if (s === 'active') load(); });
    const ch = supabase.channel(`unread:${profile.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, () => load())
      .subscribe();
    return () => {
      alive = false;
      listeners.delete(load);
      app.remove();
      supabase.removeChannel(ch);
    };
  }, [profile]);

  return n;
}
