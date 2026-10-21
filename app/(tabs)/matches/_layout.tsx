import { Stack } from 'expo-router';
import React from 'react';
import { useLargeTitleOptions } from '../../../src/components/nav';
import { useI18n } from '../../../src/i18n';

export default function Layout() {
  const { t } = useI18n();
  const options = useLargeTitleOptions();
  return (
    <Stack screenOptions={options}>
      <Stack.Screen name="index" options={{ title: t('matches.title') }} />
    </Stack>
  );
}
