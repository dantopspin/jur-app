import { Alert } from 'react-native';
import type { SheetOption } from '../components/Sheet';
import type { TKey } from '../i18n';
import { api } from './api';
import { showError } from './errors';
import type { ProfileCard } from './types';

const REASONS = ['fake', 'inappropriate', 'harassment', 'underage', 'scam', 'other'] as const;

type T = (k: TKey, v?: Record<string, string | number>) => string;
type OpenSheet = (s: { title?: string; options: SheetOption[]; cancelLabel: string }) => void;
type Other = Pick<ProfileCard, 'id' | 'name'>;

/** Report with a reason picker. Reporting also blocks, server-side. */
export function openReportFlow({
  t, sheet, me, other, onDone,
}: { t: T; sheet: OpenSheet; me: string; other: Other; onDone?: () => void }) {
  sheet({
    title: t('report.title', { name: other.name }),
    cancelLabel: t('common.cancel'),
    options: REASONS.map((r) => ({
      label: t(`report.${r}` as TKey),
      onPress: async () => {
        try {
          await api.report(me, other.id, r);
          Alert.alert(t('report.thanks'));
          onDone?.();
        } catch (e) {
          showError(t, e);
        }
      },
    })),
  });
}

export function confirmBlock({
  t, me, other, onDone,
}: { t: T; me: string; other: Other; onDone?: () => void }) {
  Alert.alert(t('chat.block'), t('chat.blockConfirm', { name: other.name }), [
    { text: t('common.cancel'), style: 'cancel' },
    {
      text: t('chat.block'), style: 'destructive',
      onPress: async () => {
        try {
          await api.block(me, other.id);
          onDone?.();
        } catch (e) {
          showError(t, e);
        }
      },
    },
  ]);
}
