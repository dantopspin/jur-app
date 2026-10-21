// Edit your prompts (Hinge-style): up to three questions with short answers.
// People can like a specific answer and leave a note on it.
import { Stack, useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Icon } from '../src/components/Icon';
import { useSheet } from '../src/components/Sheet';
import { HeaderTextButton } from '../src/components/HeaderButton';
import { Field, Loading, T } from '../src/components/ui';
import { useI18n, type TKey } from '../src/i18n';
import { api } from '../src/lib/api';
import { useSession } from '../src/lib/session';
import { colors, curve, iconSize, layout, radius, sp, type } from '../src/lib/theme';
import { PROMPT_KEYS, type PromptAnswer, type PromptKey } from '../src/lib/types';
import { showError } from '../src/lib/errors';

export default function Prompts() {
  const { t } = useI18n();
  const router = useRouter();
  const sheet = useSheet();
  const { profile } = useSession();
  const [items, setItems] = useState<PromptAnswer[] | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => { api.myPrompts().then(setItems).catch(() => setItems([])); }, []);
  if (!items || !profile) return <Loading />;

  function choose(index: number) {
    const used = new Set(items!.map((x, i) => (i === index ? null : x.key)));
    sheet({
      title: t('prompts.choose'),
      cancelLabel: t('common.cancel'),
      options: PROMPT_KEYS.filter((k) => !used.has(k)).map((k) => ({
        label: t(`prompts.${k}` as TKey),
        onPress: () => setItems((cur) => {
          const copy = [...(cur ?? [])];
          if (index < copy.length) copy[index] = { ...copy[index], key: k as PromptKey };
          else copy.push({ key: k as PromptKey, answer: '' });
          return copy;
        }),
      })),
    });
  }

  function slotMenu(i: number) {
    sheet({
      cancelLabel: t('common.cancel'),
      options: [
        { label: t('prompts.change'), onPress: () => choose(i) },
        { label: t('common.delete'), destructive: true, onPress: () => setItems((cur) => (cur ?? []).filter((_, j) => j !== i)) },
      ],
    });
  }

  async function save() {
    setSaving(true);
    try {
      await api.savePrompts(profile!.id, items!);
      router.back();
    } catch (e) {
      showError(t, e);
    } finally {
      setSaving(false);
    }
  }

  return (
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1, backgroundColor: colors.bg }}>
      <Stack.Screen options={{ headerRight: () => <HeaderTextButton title={t('common.save')} bold onPress={save} disabled={saving} /> }} />
      <ScrollView contentContainerStyle={{ padding: layout.margin, gap: sp.md, paddingBottom: sp.xxl * 2 }} keyboardShouldPersistTaps="handled">
        <T variant="callout" style={{ marginBottom: sp.xs }}>{t('prompts.hint')}</T>
        {items.map((q, i) => (
          <View key={i} style={styles.card}>
            <View style={styles.question}>
              <Pressable style={{ flex: 1 }} onPress={() => choose(i)} accessibilityRole="button" accessibilityHint={t('prompts.change')}>
                <Text maxFontSizeMultiplier={1.35} style={styles.questionText}>{t(`prompts.${q.key}` as TKey)}</Text>
              </Pressable>
              <Pressable style={styles.more} onPress={() => slotMenu(i)} accessibilityRole="button" accessibilityLabel={t('chat.menu')} hitSlop={6}>
                <Icon name="more" size={iconSize.row} color="muted" />
              </Pressable>
            </View>
            <Field value={q.answer} placeholder={t('prompts.answer')} maxLength={150} multiline onCard
              onChangeText={(v) => setItems((cur) => (cur ?? []).map((x, j) => (j === i ? { ...x, answer: v } : x)))} />
            <T variant="caption" style={{ alignSelf: 'flex-end', fontVariant: ['tabular-nums'] }}>{150 - q.answer.length}</T>
          </View>
        ))}
        {items.length < 3 && (
          <Pressable style={styles.add} onPress={() => choose(items.length)} accessibilityRole="button">
            <Icon name="plusCircle" size={iconSize.toolbar} color="blueText" />
            <Text maxFontSizeMultiplier={1.6} style={styles.addText}>{t('prompts.add')}</Text>
          </Pressable>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, padding: sp.lg, gap: sp.md },
  question: { flexDirection: 'row', alignItems: 'flex-start', gap: sp.sm },
  questionText: { ...type.title3, fontSize: 16, lineHeight: 22, color: colors.ink },
  more: { width: 32, height: 32, borderRadius: 16, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center', marginTop: -4 },
  add: {
    flexDirection: 'row', alignItems: 'center', gap: sp.md, minHeight: 56, borderRadius: radius.lg, ...curve,
    backgroundColor: colors.blueTint, paddingHorizontal: sp.lg,
  },
  addText: { ...type.headline, color: colors.blueText },
});
