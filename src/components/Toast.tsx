// A short confirmation that needs no decision ("Boost on", "Copied", "Invite sent").
// Shows for 1.5 s under the status bar with the success haptic, then leaves.
// Alerts are for decisions and blocking errors only.
//   toast(t('states.copied'))            toast(text, { icon: 'warn', error: true })
import React, { useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { failure, success } from '../lib/haptics';
import { colors, iconSize, shadowSoft, sp, type } from '../lib/theme';
import { Icon, type IconName } from './Icon';

type Msg = { id: number; text: string; icon: IconName; error?: boolean };
let listener: ((m: Msg) => void) | null = null;
let seq = 0;

export function toast(text: string, opts: { icon?: IconName; error?: boolean } = {}) {
  const m = { id: ++seq, text, icon: opts.icon ?? (opts.error ? 'warn' : 'check'), error: opts.error };
  if (m.error) failure(); else success();
  AccessibilityInfo.announceForAccessibility(text);
  listener?.(m);
}

/** Mount once, at the root. */
export function ToastHost() {
  const insets = useSafeAreaInsets();
  const [msg, setMsg] = useState<Msg | null>(null);
  const y = useRef(new Animated.Value(-80)).current;
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    listener = (m) => {
      setMsg(m);
      if (timer.current) clearTimeout(timer.current);
      Animated.spring(y, { toValue: 0, damping: 18, stiffness: 220, useNativeDriver: true }).start();
      timer.current = setTimeout(() => {
        Animated.timing(y, { toValue: -80 - insets.top, duration: 200, useNativeDriver: true }).start(() => setMsg(null));
      }, 1500);
    };
    return () => { listener = null; if (timer.current) clearTimeout(timer.current); };
  }, [y, insets.top]);

  if (!msg) return null;
  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFill, { alignItems: 'center' }]}>
      <Animated.View accessibilityLiveRegion="polite"
        style={[styles.pill, { marginTop: insets.top + sp.sm, transform: [{ translateY: y }] }]}>
        <Icon name={msg.icon} size={iconSize.row} color={msg.error ? 'danger' : 'good'} />
        <Text maxFontSizeMultiplier={1.4} style={[type.callout, { color: colors.ink }]} numberOfLines={2}>{msg.text}</Text>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  pill: {
    flexDirection: 'row', alignItems: 'center', gap: sp.sm, maxWidth: 320, backgroundColor: colors.card,
    borderRadius: 999, paddingHorizontal: sp.lg, paddingVertical: sp.md, ...shadowSoft,
  },
});
