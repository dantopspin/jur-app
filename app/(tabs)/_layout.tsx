// iOS: the system tab bar (Liquid Glass on iOS 26, minimises while scrolling),
// with SF Symbols, the system font for labels, and a native badge for unread chats.
// Android: the JavaScript tab bar styled to the brand.
import Ionicons from '@expo/vector-icons/Ionicons';
import { Tabs } from 'expo-router';
import { Badge, Icon, Label, NativeTabs } from 'expo-router/unstable-native-tabs';
import React from 'react';
import { Platform } from 'react-native';
import { useI18n } from '../../src/i18n';
import { useUnread } from '../../src/lib/unread';
import { fonts, useTheme } from '../../src/lib/theme';
import { features } from '../../src/lib/features';

type IonName = React.ComponentProps<typeof Ionicons>['name'];

function ionIcon(name: IonName, active: IonName) {
  return ({ color, focused }: { color: string; focused: boolean }) => (
    <Ionicons name={focused ? active : name} size={24} color={color} />
  );
}

export default function TabsLayout() {
  const { t } = useI18n();
  const { raw } = useTheme();
  const unread = useUnread();

  if (Platform.OS === 'ios') {
    return (
      <NativeTabs tintColor={raw.blueText} minimizeBehavior="onScrollDown">
        <NativeTabs.Trigger name="discover">
          <Label>{t('tabs.discover')}</Label>
          <Icon sf={{ default: 'safari', selected: 'safari.fill' }} />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="events" hidden={!features.events}>
          <Label>{t('tabs.events')}</Label>
          <Icon sf={{ default: 'flag', selected: 'flag.fill' }} />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="matches">
          <Label>{t('tabs.matches')}</Label>
          <Icon sf={{ default: 'bubble.left.and.bubble.right', selected: 'bubble.left.and.bubble.right.fill' }} />
          {unread > 0 ? <Badge>{unread > 9 ? '9+' : String(unread)}</Badge> : null}
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="me">
          <Label>{t('tabs.me')}</Label>
          <Icon sf={{ default: 'person.crop.circle', selected: 'person.crop.circle.fill' }} />
        </NativeTabs.Trigger>
      </NativeTabs>
    );
  }

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: raw.blueText,
        tabBarInactiveTintColor: raw.muted,
        tabBarStyle: { backgroundColor: raw.card, borderTopColor: raw.line },
        tabBarLabelStyle: { fontFamily: fonts.text700, fontSize: 11 },
      }}
    >
      <Tabs.Screen name="discover" options={{ title: t('tabs.discover'), tabBarIcon: ionIcon('compass-outline', 'compass') }} />
      <Tabs.Screen name="events" options={{ title: t('tabs.events'), tabBarIcon: ionIcon('flag-outline', 'flag'), href: features.events ? undefined : null }} />
      <Tabs.Screen name="matches" options={{
        title: t('tabs.matches'), tabBarIcon: ionIcon('chatbubbles-outline', 'chatbubbles'),
        tabBarBadge: unread > 0 ? (unread > 9 ? '9+' : unread) : undefined,
        tabBarBadgeStyle: { backgroundColor: raw.blue, color: '#FFFFFF', fontFamily: fonts.text800 },
      }} />
      <Tabs.Screen name="me" options={{ title: t('tabs.me'), tabBarIcon: ionIcon('person-outline', 'person') }} />
    </Tabs>
  );
}
