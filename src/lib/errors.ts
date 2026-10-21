// One way to tell people an action failed: a red toast in their language, never
// the raw server or network message. The raw error goes to the dev console.
import { toast } from '../components/Toast';
import type { TKey } from '../i18n';

export function showError(t: (k: TKey) => string, e?: unknown) {
  if (__DEV__ && e) console.warn(e);
  toast(t('common.error'), { error: true });
}
