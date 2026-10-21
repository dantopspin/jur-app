// A sheet of choices. iOS: the system action sheet (native look, haptics,
// dark mode, VoiceOver). Android: a bottom sheet, since Android alerts can't
// show more than three buttons.
import React, { createContext, useCallback, useContext, useState } from 'react';
import { ActionSheetIOS, Appearance, Modal, Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { colors, fonts, radius, space } from '../lib/theme';

export interface SheetOption {
  label: string;
  onPress: () => void;
  destructive?: boolean;
}

interface SheetSpec {
  title?: string;
  options: SheetOption[];
  cancelLabel: string;
}

const Ctx = createContext<(s: SheetSpec) => void>(() => {});

export function SheetProvider({ children }: { children: React.ReactNode }) {
  const [spec, setSpec] = useState<SheetSpec | null>(null);
  const open = useCallback((s: SheetSpec) => {
    if (Platform.OS === 'ios') {
      const destructive = s.options.map((o, i) => (o.destructive ? i : -1)).filter((i) => i >= 0);
      ActionSheetIOS.showActionSheetWithOptions({
        title: s.title,
        options: [...s.options.map((o) => o.label), s.cancelLabel],
        cancelButtonIndex: s.options.length,
        destructiveButtonIndex: destructive.length ? destructive : undefined,
        userInterfaceStyle: Appearance.getColorScheme() === 'dark' ? 'dark' : 'light',
      }, (i) => { if (i < s.options.length) setTimeout(s.options[i].onPress, 120); }); // lets a follow-up sheet present cleanly
      return;
    }
    setSpec(s);
  }, []);
  const close = () => setSpec(null);

  return (
    <Ctx.Provider value={open}>
      {children}
      <Modal visible={!!spec} transparent animationType="slide" onRequestClose={close}>
        <Pressable style={styles.bg} onPress={close} />
        <SafeAreaView edges={['bottom']} style={styles.sheet}>
          {spec?.title ? <Text maxFontSizeMultiplier={1.3} style={styles.title}>{spec.title}</Text> : null}
          <View style={styles.group}>
            {spec?.options.map((o, i) => (
              <Pressable
                key={i}
                style={({ pressed }) => [styles.option, i > 0 && styles.sep, pressed && { backgroundColor: colors.bg }]}
                onPress={() => { close(); setTimeout(o.onPress, 250); }}
              >
                <Text maxFontSizeMultiplier={1.6} style={[styles.label, o.destructive && { color: colors.danger }]}>{o.label}</Text>
              </Pressable>
            ))}
          </View>
          <Pressable style={[styles.group, styles.option, { marginTop: space(1) }]} onPress={close}>
            <Text maxFontSizeMultiplier={1.6} style={[styles.label, { fontFamily: fonts.text700 }]}>{spec?.cancelLabel}</Text>
          </Pressable>
        </SafeAreaView>
      </Modal>
    </Ctx.Provider>
  );
}

export function useSheet() {
  return useContext(Ctx);
}

const styles = StyleSheet.create({
  bg: { flex: 1, backgroundColor: colors.overlay },
  sheet: { backgroundColor: colors.bg, padding: space(1.5), paddingBottom: space(1), borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl },
  title: { textAlign: 'center', color: colors.muted, fontFamily: fonts.text600, fontSize: 14, padding: space(1.5) },
  group: { backgroundColor: colors.card, borderRadius: radius.md, overflow: 'hidden' },
  option: { minHeight: 56, justifyContent: 'center', alignItems: 'center' },
  sep: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line },
  label: { fontFamily: fonts.text500, fontSize: 17, color: colors.ink },
});
