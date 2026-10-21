// Navigation-bar buttons: a text action (Cancel, Done) or a 22 pt symbol, with a
// 44 pt touch target, tinted like the system bar items.
import React from 'react';
import { Pressable, Text, View } from 'react-native';
import { fonts, iconSize, useTheme } from '../lib/theme';
import { Icon, type IconName } from './Icon';

export function HeaderTextButton({ title, onPress, bold, disabled }: { title: string; onPress: () => void; bold?: boolean; disabled?: boolean }) {
  const { raw } = useTheme();
  return (
    <Pressable onPress={onPress} disabled={disabled} hitSlop={10} accessibilityRole="button"
      style={({ pressed }) => ({ opacity: disabled ? 0.35 : pressed ? 0.5 : 1, paddingHorizontal: 4, minHeight: 44, justifyContent: 'center' })}>
      <Text maxFontSizeMultiplier={1.3} style={{ fontFamily: bold ? fonts.text700 : fonts.text500, fontSize: 17, color: raw.blueText }}>{title}</Text>
    </Pressable>
  );
}

export function HeaderIconButton({ icon, label, onPress, badge }: { icon: IconName; label: string; onPress: () => void; badge?: string }) {
  const { raw } = useTheme();
  return (
    <Pressable onPress={onPress} hitSlop={8} accessibilityRole="button" accessibilityLabel={badge ? `${label}, ${badge}` : label}
      style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1, width: 44, height: 44, alignItems: 'center', justifyContent: 'center' })}>
      <Icon name={icon} size={iconSize.toolbar} color="blueText" weight="regular" />
      {badge ? (
        <Text maxFontSizeMultiplier={1.2} style={{
          position: 'absolute', top: 4, right: 2, minWidth: 18, paddingHorizontal: 4, borderRadius: 9, overflow: 'hidden',
          backgroundColor: raw.blue, color: '#FFFFFF', fontFamily: fonts.text800, fontSize: 11, lineHeight: 18, textAlign: 'center',
        }}>{badge}</Text>
      ) : null}
    </Pressable>
  );
}

/** The top bar of a page sheet: Cancel · centred title · optional bold action (iOS sheet pattern). */
export function SheetHeader({
  title, cancelLabel, onCancel, action, onAction, actionDisabled,
}: {
  title: string; cancelLabel: string; onCancel: () => void; action?: string; onAction?: () => void; actionDisabled?: boolean;
}) {
  const { raw } = useTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', minHeight: 56, paddingHorizontal: 12 }}>
      <View style={{ flex: 1, alignItems: 'flex-start' }}>
        <HeaderTextButton title={cancelLabel} onPress={onCancel} />
      </View>
      <Text maxFontSizeMultiplier={1.3} numberOfLines={1} accessibilityRole="header"
        style={{ flex: 2, textAlign: 'center', fontFamily: fonts.text700, fontSize: 17, color: raw.ink }}>{title}</Text>
      <View style={{ flex: 1, alignItems: 'flex-end' }}>
        {action && onAction ? <HeaderTextButton title={action} onPress={onAction} bold disabled={actionDisabled} /> : null}
      </View>
    </View>
  );
}
