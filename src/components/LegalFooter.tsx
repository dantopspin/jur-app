// The legal line under every purchase and sign-in screen: one sentence plus
// working, translated links to the Terms of Use and Privacy Policy.
import React from 'react';
import { Linking, StyleSheet, Text } from 'react-native';
import { useI18n, type TKey } from '../i18n';
import { env } from '../lib/env';
import { colors, fonts, lightPalette, sp } from '../lib/theme';

export function LegalFooter({ lead, onDark }: { lead: TKey; onDark?: boolean }) {
  const { t } = useI18n();
  const color = onDark ? 'rgba(255,255,255,0.8)' : colors.muted;
  return (
    <Text maxFontSizeMultiplier={1.6} style={[styles.text, { color }]}>
      {t(lead)}{' '}
      <Text maxFontSizeMultiplier={1.6} style={[styles.link, onDark && { color: lightPalette.white }]} accessibilityRole="link"
        onPress={() => Linking.openURL(env.termsUrl)}>{t('legal.terms')}</Text>
      {' · '}
      <Text maxFontSizeMultiplier={1.6} style={[styles.link, onDark && { color: lightPalette.white }]} accessibilityRole="link"
        onPress={() => Linking.openURL(env.privacyUrl)}>{t('legal.privacy')}</Text>
    </Text>
  );
}

const styles = StyleSheet.create({
  text: { fontFamily: fonts.text500, fontSize: 12, lineHeight: 17, textAlign: 'center', marginTop: sp.xs },
  link: { textDecorationLine: 'underline', fontFamily: fonts.text600 },
});
