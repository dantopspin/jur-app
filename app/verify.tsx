import { useRouter } from 'expo-router';
import React, { useState } from 'react';
import { Alert, StyleSheet, View } from 'react-native';
import { Icon } from '../src/components/Icon';
import { Button, P, Screen } from '../src/components/ui';
import { useI18n } from '../src/i18n';
import { api } from '../src/lib/api';
import { useSession } from '../src/lib/session';
import { space } from '../src/lib/theme';
import { takeSelfie, uploadSelfie } from '../src/lib/upload';
import { showError } from '../src/lib/errors';

export default function Verify() {
  const { t } = useI18n();
  const router = useRouter();
  const { profile, refreshProfile } = useSession();
  const [busy, setBusy] = useState(false);

  async function go() {
    if (!profile) return;
    try {
      const img = await takeSelfie();
      if (!img) return;
      setBusy(true);
      const path = await uploadSelfie(profile.id, img);
      await api.requestVerification(path);
      await refreshProfile();
      Alert.alert(t('verify.sent'));
      router.back();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen edges={['bottom']}>
      <View style={styles.wrap}>
        <Icon name="selfie" size={72} color="blueText" weight="regular" />
        <P style={{ textAlign: 'center' }}>{t('verify.body')}</P>
        <Button title={t('verify.take')} variant="accent" onPress={go} loading={busy} style={{ alignSelf: 'stretch' }} />
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, padding: space(2), alignItems: 'center', justifyContent: 'center', gap: space(3) },
});
