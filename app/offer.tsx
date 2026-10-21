// One-time intro offer: the first month of Pro at 50% off, shown once when
// someone closes the paywall (the "50% off" plans Ritmo lists next to full price).
// No fake countdowns: it simply doesn't come back.
import { useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, StyleSheet, Text, View } from 'react-native';
import { type PurchasesPackage } from 'react-native-purchases';
import { Mark, Shanyrak } from '../src/components/Brand';
import { LegalFooter } from '../src/components/LegalFooter';
import { Button, CloseButton, Screen } from '../src/components/ui';
import { useI18n } from '../src/i18n';
import { buy, loadOfferings } from '../src/lib/purchases';
import { useSession } from '../src/lib/session';
import { fonts, lightPalette as c, radius, space } from '../src/lib/theme';
import { showError } from '../src/lib/errors';

export default function Offer() {
  const { t } = useI18n();
  const router = useRouter();
  const { refreshLimits } = useSession();
  const [intro, setIntro] = useState<PurchasesPackage | null>(null);

  const [busy, setBusy] = useState(false);

  useEffect(() => {
    loadOfferings().then((o) => {
      const pkg = o.intro?.availablePackages?.[0] ?? null;
      // Without a store intro price there is nothing honest to show: leave.
      if (!pkg?.product.introPrice) { router.back(); return; }
      setIntro(pkg);
    }).catch(() => router.back());
  }, [router]);

  async function purchase() {
    if (!intro) return;
    setBusy(true);
    try {
      if (await buy(intro)) {
        Alert.alert(t('paywall.success'));
        for (let i = 0; i < 6; i++) { await new Promise((r) => setTimeout(r, 1500)); await refreshLimits(); }
        router.back();
      }
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen edges={['top', 'bottom']} style={{ backgroundColor: c.blue }}>
      <CloseButton onPress={() => router.back()} label={t('common.close')} onDark />
      <View style={styles.wrap}>
        <Text maxFontSizeMultiplier={1.6} style={styles.badge}>{t('offer.badge').toUpperCase()}</Text>
        <View style={styles.seal}>
          <Shanyrak size={220} color={c.gold} animate slats={0.2} style={StyleSheet.absoluteFill} />
          <Text maxFontSizeMultiplier={1.3} style={styles.pct}>−50%</Text>
        </View>
        <Mark size={44} color={c.gold} />
        <Text maxFontSizeMultiplier={1.3} style={styles.title}>{t('offer.title')}</Text>
        <Text maxFontSizeMultiplier={1.6} style={styles.sub}>{t('offer.sub')}</Text>
        {intro?.product.introPrice ? (
          <View style={styles.price}>
            <Text maxFontSizeMultiplier={1.3} style={styles.now}>{intro.product.introPrice.priceString}</Text>
            <Text maxFontSizeMultiplier={1.6} style={styles.was}>{t('offer.was', { price: intro.product.priceString })}</Text>
          </View>
        ) : <ActivityIndicator color="#FFFFFF" />}
        {intro?.product.introPrice ? (
          <Text maxFontSizeMultiplier={1.6} style={styles.terms}>
            {intro.product.introPrice.priceString} {t('offer.then', { price: intro.product.priceString })}
          </Text>
        ) : null}
      </View>
      <View style={styles.actions}>
        <Button title={t('offer.buy')} variant="accent" onPress={purchase} loading={busy} disabled={!intro} />
        <Button title={t('offer.no')} variant="ghost" textColor="#FFFFFF" onPress={() => router.back()} />
        <LegalFooter lead="paywall.legal" onDark />
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: space(2), gap: space(1.25) },
  badge: { fontFamily: fonts.text800, fontSize: 12, letterSpacing: 2, color: c.gold },
  seal: { width: 220, height: 220, alignItems: 'center', justifyContent: 'center' },
  pct: { fontFamily: fonts.display, fontSize: 56, color: '#FFFFFF', letterSpacing: -1 },
  title: { fontFamily: fonts.display, fontSize: 26, lineHeight: 32, color: '#FFFFFF', textAlign: 'center' },
  sub: { fontFamily: fonts.text500, fontSize: 16, lineHeight: 23, color: c.blueMist, textAlign: 'center' },
  price: { alignItems: 'center', marginTop: space(1), backgroundColor: c.blueDeep, borderRadius: radius.md, paddingHorizontal: space(2.5), paddingVertical: space(1.25) },
  now: { fontFamily: fonts.display, fontSize: 28, color: '#FFFFFF' },
  was: { fontFamily: fonts.text600, fontSize: 14, color: c.blueMist, textDecorationLine: 'line-through' },
  actions: { padding: space(2), gap: space(0.5) },
  terms: { fontFamily: fonts.text600, fontSize: 14, lineHeight: 20, color: '#FFFFFF', textAlign: 'center', marginTop: space(0.5) },
  legal: { fontFamily: fonts.text500, fontSize: 12, lineHeight: 16, color: c.blueMist, textAlign: 'center', marginTop: space(0.5) },
});
