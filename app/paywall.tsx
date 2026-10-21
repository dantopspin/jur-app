import AsyncStorage from '@react-native-async-storage/async-storage';
import { useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PACKAGE_TYPE, type PurchasesPackage } from 'react-native-purchases';
import { Mark } from '../src/components/Brand';
import { Icon } from '../src/components/Icon';
import { LegalFooter } from '../src/components/LegalFooter';
import { Button, CloseButton, Screen } from '../src/components/ui';
import { useI18n } from '../src/i18n';
import {
  buy, loadOfferings, packCount, purchasesAvailable, restore, sortProPackages, type Offerings,
} from '../src/lib/purchases';
import { useSession } from '../src/lib/session';
// The paywall is a fixed brand surface (blue in light and dark), so it uses the light palette directly.
import { curve, fonts, iconSize, lightPalette as colors, radius, sp, space, type } from '../src/lib/theme';
import { showError } from '../src/lib/errors';

export const INTRO_KEY = 'qadam.introOfferShown';

export default function Paywall() {
  const { t } = useI18n();
  const router = useRouter();
  const { refreshLimits, limits } = useSession();
  const [offerings, setOfferings] = useState<Offerings | null>(null);
  const [selected, setSelected] = useState<PurchasesPackage | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const available = purchasesAvailable();

  useEffect(() => {
    if (!available) return;
    loadOfferings()
      .then((o) => {
        setOfferings(o);
        const pkgs = sortProPackages(o.pro?.availablePackages ?? []);
        setSelected(pkgs.find((p) => p.packageType === PACKAGE_TYPE.MONTHLY) ?? pkgs[0] ?? null);
      })
      .catch((e) => {
        console.warn('offerings failed', e);
        setOfferings({ pro: null, boosts: null, supers: null, intro: null });
      });
  }, [available]);

  /** The webhook updates the server a moment after the store confirms; poll briefly. */
  async function syncAfterPurchase() {
    for (let i = 0; i < 6; i++) {
      await new Promise((r) => setTimeout(r, 1500));
      await refreshLimits();
    }
  }

  async function purchase(pkg: PurchasesPackage, isPro: boolean) {
    setBusy(pkg.identifier);
    try {
      const ok = await buy(pkg);
      if (!ok) return;
      Alert.alert(isPro ? t('paywall.success') : t('paywall.creditsSuccess'));
      syncAfterPurchase();
      if (isPro) router.back();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(null);
    }
  }

  /** First time someone walks away from the paywall, offer the intro price once. */
  async function close() {
    const intro = offerings?.intro?.availablePackages?.[0];
    if (!limits?.pro && intro?.product.introPrice && !(await AsyncStorage.getItem(INTRO_KEY).catch(() => null))) {
      await AsyncStorage.setItem(INTRO_KEY, new Date().toISOString()).catch(() => {});
      router.replace('/offer');
      return;
    }
    router.back();
  }

  async function doRestore() {
    setBusy('restore');
    try {
      await restore();
      Alert.alert(t('paywall.restored'));
      syncAfterPurchase();
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(null);
    }
  }

  const proPkgs = sortProPackages(offerings?.pro?.availablePackages ?? []);
  const extras = [
    ...(offerings?.boosts?.availablePackages ?? []).map((p) => ({ p, label: t('paywall.boostPack', { n: packCount(p) }), icon: 'boost' as const })),
    ...(offerings?.supers?.availablePackages ?? []).map((p) => ({ p, label: t('paywall.superPack', { n: packCount(p) }), icon: 'star' as const })),
  ];

  return (
    <Screen edges={['top', 'bottom']} style={{ backgroundColor: colors.blue }}>
      <CloseButton onPress={close} label={t('common.close')} onDark />
      <ScrollView contentContainerStyle={styles.wrap}>
        <View style={styles.hero}>
          <Mark size={88} color={colors.gold} animate />
          <Text maxFontSizeMultiplier={1.3} style={styles.brand}>Qadam</Text>
          <Text maxFontSizeMultiplier={1.3} style={styles.pro}>Pro</Text>
          <Text maxFontSizeMultiplier={1.6} style={styles.sub}>{t('paywall.sub')}</Text>
        </View>

        <View style={{ gap: sp.md }}>
          {(['f1', 'f2', 'f3', 'f4'] as const).map((k) => (
            <View key={k} style={styles.feature}>
              <Icon name="check" size={iconSize.toolbar} color={colors.gold} />
              <Text maxFontSizeMultiplier={1.6} style={styles.featureText}>{t(`paywall.${k}`)}</Text>
            </View>
          ))}
        </View>

        {!available ? (
          <Text maxFontSizeMultiplier={1.6} style={styles.note}>{t('paywall.unavailable')}</Text>
        ) : offerings === null ? (
          <ActivityIndicator color={colors.white} />
        ) : (
          <>
            <View style={{ gap: sp.sm }}>
              {proPkgs.map((p) => {
                const on = selected?.identifier === p.identifier;
                const label = p.packageType === PACKAGE_TYPE.WEEKLY ? t('paywall.weekly')
                  : p.packageType === PACKAGE_TYPE.MONTHLY ? t('paywall.monthly')
                  : p.packageType === PACKAGE_TYPE.SIX_MONTH ? t('paywall.sixMonths') : p.product.title;
                const perUnit = p.packageType === PACKAGE_TYPE.SIX_MONTH && p.product.pricePerMonthString
                  ? `${p.product.pricePerMonthString} ${t('paywall.perMonth')}` : null;
                return (
                  <Pressable key={p.identifier} onPress={() => setSelected(p)} style={[styles.plan, on && styles.planOn]}
                    accessibilityRole="radio" accessibilityState={{ selected: on }}>
                    <Icon name={on ? 'check' : 'circle'} size={iconSize.toolbar} color={on ? colors.blue : 'rgba(255,255,255,0.5)'} />
                    <View style={{ flex: 1, gap: sp.xxs }}>
                      <Text maxFontSizeMultiplier={1.6} style={[styles.planName, on && { color: colors.ink }]}>{label}</Text>
                      {perUnit ? <Text maxFontSizeMultiplier={1.6} style={[styles.planSub, on && { color: colors.inkSoft }]}>{perUnit}</Text> : null}
                    </View>
                    {p.packageType === PACKAGE_TYPE.SIX_MONTH && (
                      <View style={styles.best}><Text maxFontSizeMultiplier={1.6} style={styles.bestText}>{t('paywall.best')}</Text></View>
                    )}
                    <Text maxFontSizeMultiplier={1.3} style={[styles.price, on && { color: colors.ink }]}>{p.product.priceString}</Text>
                  </Pressable>
                );
              })}
            </View>

            {selected && (
              <Button title={t('paywall.buy')} variant="accent" loading={busy === selected.identifier}
                onPress={() => purchase(selected, true)} />
            )}

            {extras.length > 0 && (
              <View style={{ gap: sp.sm }}>
                <Text maxFontSizeMultiplier={1.6} style={styles.extrasTitle}>{t('paywall.extras')}</Text>
                <View style={styles.extras}>
                  {extras.map(({ p, label, icon }) => (
                    <Pressable key={p.identifier} style={styles.extra} onPress={() => purchase(p, false)} disabled={!!busy}>
                      {busy === p.identifier ? <ActivityIndicator color={colors.white} /> : (
                        <>
                          <Icon name={icon} size={iconSize.toolbar} color={colors.gold} />
                          <Text maxFontSizeMultiplier={1.6} style={styles.extraLabel}>{label}</Text>
                          <Text maxFontSizeMultiplier={1.6} style={styles.extraPrice}>{p.product.priceString}</Text>
                        </>
                      )}
                    </Pressable>
                  ))}
                </View>
              </View>
            )}

            <Text maxFontSizeMultiplier={1.6} style={styles.link} onPress={doRestore}>{busy === 'restore' ? '…' : t('paywall.restore')}</Text>
          </>
        )}

        <LegalFooter lead="paywall.legal" onDark />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  wrap: { padding: sp.lg, paddingTop: space(6), gap: sp.xl },
  hero: { alignItems: 'center', gap: sp.sm, paddingTop: sp.lg },
  brand: { ...type.title2, color: colors.bg, marginTop: sp.sm },
  pro: { fontFamily: fonts.display, fontSize: 64, lineHeight: 70, color: colors.gold },
  sub: { ...type.body, color: colors.blueMist, textAlign: 'center' },
  feature: { flexDirection: 'row', alignItems: 'center', gap: sp.md },
  featureText: { flex: 1, ...type.body, fontFamily: fonts.text600, color: colors.white },
  plan: {
    flexDirection: 'row', alignItems: 'center', gap: sp.md, borderRadius: radius.md, ...curve, padding: sp.lg,
    backgroundColor: 'rgba(255,255,255,0.08)', borderWidth: 2, borderColor: 'transparent',
  },
  planOn: { backgroundColor: colors.card, borderColor: colors.gold },
  planName: { ...type.headline, color: colors.white },
  planSub: { ...type.footnote, color: 'rgba(255,255,255,0.7)' },
  price: { ...type.title3, color: colors.white, fontVariant: ['tabular-nums'] },
  best: { backgroundColor: colors.gold, borderRadius: radius.pill, paddingHorizontal: sp.sm, paddingVertical: sp.xs },
  bestText: { ...type.caption, color: colors.ink },
  extrasTitle: { ...type.overline, color: 'rgba(255,255,255,0.75)' },
  extras: { flexDirection: 'row', flexWrap: 'wrap', gap: sp.sm },
  extra: {
    flexGrow: 1, flexBasis: '45%', minHeight: 92, borderRadius: radius.md, ...curve, padding: sp.md, gap: sp.xs, justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  extraLabel: { ...type.callout, fontFamily: fonts.text700, color: colors.white },
  extraPrice: { ...type.callout, fontFamily: fonts.text700, color: colors.gold },
  link: { ...type.callout, color: colors.bg, textAlign: 'center', paddingVertical: sp.sm },
  note: { ...type.callout, color: colors.blueMist, textAlign: 'center' },
  legal: { ...type.caption, fontFamily: fonts.text500, color: 'rgba(255,255,255,0.75)', textAlign: 'center' },
});
