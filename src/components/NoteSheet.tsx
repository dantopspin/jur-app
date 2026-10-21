// "Like with a note" (Hinge-style): a short message sent with the like.
// If the like turns into a match, the note opens the chat.
import React, { useEffect, useState } from 'react';
import { KeyboardAvoidingView, Modal, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useI18n } from '../i18n';
import { colors, fonts, radius, sp, type } from '../lib/theme';
import type { PromptAnswer } from '../lib/types';
import type { TKey } from '../i18n';
import { SheetHeader } from './HeaderButton';

const MAX = 140;

export function NoteSheet({
  visible, name, challenge, prompt, sending, onSend, onClose,
}: {
  visible: boolean;
  /** the prompt answer this note is about (shown instead of the challenge) */
  prompt?: PromptAnswer | null;
  name: string;
  challenge?: string | null;
  sending?: boolean;
  onSend: (note: string) => void;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const [text, setText] = useState('');
  useEffect(() => { if (visible) setText(''); }, [visible]);
  const body = text.trim();
  const ios = Platform.OS === 'ios';

  return (
    // iOS: a native page sheet (swipe down to dismiss). Android: a bottom sheet over a scrim.
    <Modal visible={visible} transparent={!ios} presentationStyle={ios ? 'pageSheet' : undefined}
      animationType="slide" onRequestClose={onClose}>
      {!ios && <Pressable style={styles.scrim} onPress={onClose} accessibilityLabel={t('common.close')} />}
      <KeyboardAvoidingView behavior={ios ? 'padding' : undefined} style={ios ? styles.iosFill : undefined}>
        <SafeAreaView edges={['bottom']} style={[styles.sheet, ios && styles.sheetIOS]}>
          {!ios && <View style={styles.grab} />}
          <SheetHeader title={t('note.title', { name })} cancelLabel={t('common.cancel')} onCancel={onClose}
            action={t('note.send')} onAction={() => onSend(body)} actionDisabled={!body || sending} />
          {prompt ? (
            <View style={styles.quote}>
              <Text maxFontSizeMultiplier={1.6} style={styles.quoteLabel}>{t(`prompts.${prompt.key}` as TKey)}</Text>
              <Text maxFontSizeMultiplier={1.6} style={styles.quoteText}>{prompt.answer}</Text>
            </View>
          ) : challenge ? (
            <View style={styles.quote}>
              <Text maxFontSizeMultiplier={1.6} style={styles.quoteText}>{t('note.about', { challenge })}</Text>
            </View>
          ) : null}
          <TextInput
            value={text}
            onChangeText={(v) => setText(v.slice(0, MAX))}
            placeholder={t('note.placeholder')}
            placeholderTextColor={colors.hint}
            style={styles.input}
            multiline
            autoFocus
            maxLength={MAX}
          />
          <View style={styles.row}>
            <Text maxFontSizeMultiplier={1.6} style={styles.hint}>{t('note.hint')}</Text>
            <Text maxFontSizeMultiplier={1.3} style={styles.count}>{MAX - text.length}</Text>
          </View>
        </SafeAreaView>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  scrim: { flex: 1, backgroundColor: colors.overlay },
  sheet: {
    backgroundColor: colors.bg, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    paddingHorizontal: sp.lg, paddingBottom: sp.lg, gap: sp.md,
  },
  iosFill: { flex: 1, backgroundColor: colors.bg },
  sheetIOS: { flex: 1, borderTopLeftRadius: 0, borderTopRightRadius: 0, paddingHorizontal: sp.lg },
  grab: { alignSelf: 'center', width: 36, height: 5, borderRadius: 3, backgroundColor: colors.line, marginTop: sp.sm },
  quote: { backgroundColor: colors.blueTint, borderRadius: radius.md, paddingHorizontal: sp.lg, paddingVertical: sp.md, gap: sp.xxs },
  quoteLabel: { ...type.footnote, color: colors.muted },
  quoteText: { ...type.callout, color: colors.blueText },
  input: {
    minHeight: 120, maxHeight: 200, backgroundColor: colors.card, borderRadius: radius.md, paddingHorizontal: sp.lg,
    paddingTop: 14, paddingBottom: 14, ...type.body, color: colors.ink, textAlignVertical: 'top',
  },
  row: { flexDirection: 'row', justifyContent: 'space-between', gap: sp.sm },
  hint: { flex: 1, ...type.footnote, color: colors.muted },
  count: { ...type.footnote, fontFamily: fonts.text600, color: colors.muted, fontVariant: ['tabular-nums'] },
});
