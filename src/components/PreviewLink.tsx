// A row or card that opens a screen, with the iOS long-press preview and context
// menu (peek, then actions). Android: tap opens, long-press shows the action sheet.
import { Link, useRouter, type Href } from 'expo-router';
import React from 'react';
import { Platform, Pressable, type StyleProp, type ViewStyle } from 'react-native';
import { knock } from '../lib/haptics';
import { sfName, type IconName } from './Icon';
import { useSheet } from './Sheet';

export interface PreviewAction {
  title: string;
  icon?: IconName;
  destructive?: boolean;
  onPress: () => void;
}

export function PreviewLink({
  href, children, actions = [], style, cancelLabel, accessibilityLabel,
}: {
  href: Href;
  children: React.ReactNode;
  actions?: PreviewAction[];
  style?: StyleProp<ViewStyle> | ((s: { pressed: boolean }) => StyleProp<ViewStyle>);
  cancelLabel: string;
  accessibilityLabel?: string;
}) {
  const router = useRouter();
  const sheet = useSheet();

  if (Platform.OS === 'ios') {
    return (
      <Link href={href} asChild>
        <Link.Trigger>
          <Pressable style={style} accessibilityRole="button" accessibilityLabel={accessibilityLabel}>{children}</Pressable>
        </Link.Trigger>
        <Link.Preview />
        {actions.length > 0 ? (
          <Link.Menu>
            {actions.map((a) => (
              <Link.MenuAction key={a.title} title={a.title} icon={a.icon ? sfName(a.icon) : undefined}
                destructive={a.destructive} onPress={a.onPress} />
            ))}
          </Link.Menu>
        ) : null}
      </Link>
    );
  }

  return (
    <Pressable
      style={style}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      onPress={() => router.push(href)}
      onLongPress={actions.length ? () => {
        knock();
        sheet({ cancelLabel, options: actions.map((a) => ({ label: a.title, destructive: a.destructive, onPress: a.onPress })) });
      } : undefined}
    >
      {children}
    </Pressable>
  );
}
