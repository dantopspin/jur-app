// Feeds the iOS Home Screen widget (targets/widget): a small JSON snapshot in
// the shared App Group, then a widget reload. Strings are translated here.
import { ExtensionStorage } from '@bacons/apple-targets';
import { Platform } from 'react-native';
import { api } from './api';
import { formatEventTime } from './dates';

const GROUP = 'group.kz.qadam.app';
const storage = Platform.OS === 'ios' ? new ExtensionStorage(GROUP) : null;

type T = (k: 'widget.likes' | 'widget.unread' | 'widget.next' | 'widget.none') => string;

export async function refreshWidget(t: T, intl: string) {
  if (!storage) return;
  try {
    const [likes, matches, events] = await Promise.all([api.likesReceived(), api.matches(), api.upcomingEvents()]);
    const next = events
      .filter((e) => e.i_am_going && !e.cancelled && new Date(e.starts_at).getTime() > Date.now())
      .sort((a, b) => a.starts_at.localeCompare(b.starts_at))[0];
    storage.set('widget', JSON.stringify({
      likes: likes.count,
      unread: matches.reduce((n, m) => n + m.unread, 0),
      event: next ? { id: next.id, title: next.title, when: formatEventTime(next.starts_at, intl), place: next.meeting_point } : null,
      labels: { likes: t('widget.likes'), unread: t('widget.unread'), next: t('widget.next'), none: t('widget.none') },
    }));
    ExtensionStorage.reloadWidget();
  } catch {
    // the widget keeps its last snapshot
  }
}

/** On sign-out, show the empty state rather than someone else's numbers. */
export function clearWidget() {
  if (!storage) return;
  storage.set('widget', undefined);
  ExtensionStorage.reloadWidget();
}
