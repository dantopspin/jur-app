import { Stack, useRouter } from 'expo-router';
import React from 'react';
import { HeaderIconButton } from '../../../src/components/HeaderButton';
import { useLargeTitleOptions } from '../../../src/components/nav';
import { useI18n } from '../../../src/i18n';

export default function Layout() {
  const { t } = useI18n();
  const router = useRouter();
  const options = useLargeTitleOptions();
  return (
    <Stack screenOptions={options}>
      <Stack.Screen name="index" options={{
        title: t('tabs.me'),
        headerRight: () => <HeaderIconButton icon="gear" label={t('me.settings')} onPress={() => router.push('/settings')} />,
      }} />
    </Stack>
  );
}
