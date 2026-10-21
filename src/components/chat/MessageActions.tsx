// Long-press a message: quick reactions (SF Symbols, not emoji), reply, copy.
import * as Clipboard from 'expo-clipboard';
import React from 'react';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../../i18n';
import { formatClock } from '../../lib/dates';
import { tick } from '../../lib/haptics';
import { colors, curve, fonts, iconSize, radius, shadowSoft, sp, type } from '../../lib/theme';
import { toast } from '../Toast';
import type { Message, Reaction } from '../../lib/types';
import { Icon } from '../Icon';

export const REACTIONS: Reaction[] = ['heart', 'fire', 'clap', 'laugh', 'thumbsup'];

export function MessageActions({
  message, meId, onReact, onReply, onClose,
}: {
  message: Message | null; meId: string;
  onReact: (r: Reaction) => void; onReply: () => void; onClose: () => void;
}) {
  const { t, intl } = useI18n();
  const myReaction = message?.reactions?.find((r) => r.profile_id === meId)?.reaction;
  return (
    <Modal visible={!!message} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.scrim} onPress={onClose} accessibilityLabel={t('common.close')} />
      <View style={styles.center} pointerEvents="box-none">
        <View style={styles.bar} accessibilityRole="menu">
          {REACTIONS.map((r) => (
            <Pressable key={r} onPress={() => { tick(); onReact(r); }} style={[styles.reaction, myReaction === r && styles.on]}
              accessibilityRole="button" accessibilityLabel={r} hitSlop={4}>
              <Icon name={r} size={26} color={r === 'heart' ? 'danger' : r === 'fire' ? 'clay' : 'blueText'} />
            </Pressable>
          ))}
        </View>
        {message?.kind === 'text' ? (
          <View style={[styles.preview, message.sender_id === meId ? styles.previewMine : null]}>
            <Text maxFontSizeMultiplier={1.6} numberOfLines={6}
              style={[type.body, { color: message.sender_id === meId ? colors.white : colors.ink }]}>{message.body}</Text>
          </View>
        ) : null}
        <View style={styles.menu}>
          {message ? (
            <View style={styles.when}>
              <Icon name="clock" size={iconSize.inline} color="muted" />
              <Text maxFontSizeMultiplier={1.4} style={[type.footnote, { color: colors.muted }]}>{formatClock(message.created_at, intl)}</Text>
            </View>
          ) : null}
          <Pressable style={({ pressed }) => [styles.item, styles.sep, pressed && styles.pressed]} onPress={onReply} accessibilityRole="button">
            <Text maxFontSizeMultiplier={1.6} style={styles.itemText}>{t('chat2.reply')}</Text><Icon name="reply" size={iconSize.row} color="ink" />
          </Pressable>
          {message?.kind === 'text' ? (
            <Pressable style={({ pressed }) => [styles.item, styles.sep, pressed && styles.pressed]} accessibilityRole="button"
              onPress={() => { Clipboard.setStringAsync(message.body).catch(() => {}); onClose(); toast(t('states.copied'), { icon: 'copy' }); }}>
              <Text maxFontSizeMultiplier={1.6} style={styles.itemText}>{t('chat2.copy')}</Text><Icon name="copy" size={iconSize.row} color="ink" />
            </Pressable>
          ) : null}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  scrim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.35)' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: sp.md, padding: sp.xl },
  bar: {
    flexDirection: 'row', gap: sp.xs, backgroundColor: colors.card, borderRadius: radius.pill, paddingHorizontal: sp.sm,
    paddingVertical: sp.xs, ...shadowSoft,
  },
  reaction: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  on: { backgroundColor: colors.blueTint },
  preview: {
    maxWidth: '85%', alignSelf: 'center', backgroundColor: colors.card, borderRadius: 18, ...curve,
    paddingHorizontal: 14, paddingVertical: sp.sm,
  },
  previewMine: { backgroundColor: colors.blue },
  menu: { width: 250, backgroundColor: colors.card, borderRadius: 13, ...curve, overflow: 'hidden', ...shadowSoft },
  when: { flexDirection: 'row', alignItems: 'center', gap: sp.xs, paddingHorizontal: sp.lg, paddingVertical: sp.sm },
  item: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: sp.lg, minHeight: 44 },
  pressed: { backgroundColor: colors.line },
  sep: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line },
  itemText: { fontFamily: fonts.text500, fontSize: 17, color: colors.ink },
});
