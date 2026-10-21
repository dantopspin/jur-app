// Welcome → one-tap sign-in (Apple on iPhone, Google) or an email code.
import Ionicons from '@expo/vector-icons/Ionicons';
import * as AppleAuthentication from 'expo-apple-authentication';
import React, { useEffect, useState } from 'react';
import {
  KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions,
} from 'react-native';
import { Mark, Ridge } from '../src/components/Brand';
import { Icon } from '../src/components/Icon';
import { LegalFooter } from '../src/components/LegalFooter';
import { Button, Field, H1, P, Screen } from '../src/components/ui';
import { snowOnHorizon } from '../src/lib/season';
import { useI18n } from '../src/i18n';
import { isConfigured } from '../src/lib/env';
import { appleAvailable, googleEnabled, signInWithApple, signInWithGoogle, type SocialResult } from '../src/lib/socialAuth';
import { supabase } from '../src/lib/supabase';
import { colors, fonts, lightPalette, space } from '../src/lib/theme';
import type { Locale } from '../src/lib/types';

type Mode = 'welcome' | 'email' | 'code' | 'password';

export default function SignIn() {
  const { t, locale, setLocale } = useI18n();
  const { width } = useWindowDimensions();
  const [mode, setMode] = useState<Mode>('welcome');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState<null | 'apple' | 'google' | 'email'>(null);
  const [error, setError] = useState<string | null>(null);
  const [hasApple, setHasApple] = useState(false);

  useEffect(() => { appleAvailable().then(setHasApple); }, []);

  const validEmail = /^\S+@\S+\.\S+$/.test(email.trim());

  async function social(kind: 'apple' | 'google') {
    setError(null);
    setBusy(kind);
    const r: SocialResult = kind === 'apple' ? await signInWithApple() : await signInWithGoogle();
    setBusy(null);
    if (r === 'error') setError(t('welcome.socialFailed'));
    // 'ok': the session listener routes to onboarding or the app
  }

  async function sendCode() {
    if (!validEmail) return setError(t('auth.badEmail'));
    setBusy('email');
    setError(null);
    const { error: e } = await supabase.auth.signInWithOtp({
      email: email.trim().toLowerCase(),
      options: { shouldCreateUser: true },
    });
    setBusy(null);
    if (e) return setError(e.message);
    setMode('code');
  }

  async function verifyCode(value = code) {
    setBusy('email');
    setError(null);
    const { error: e } = await supabase.auth.verifyOtp({
      email: email.trim().toLowerCase(),
      token: value.trim(),
      type: 'email',
    });
    setBusy(null);
    if (e) setError(t('auth.badCode'));
  }

  async function signInWithPassword() {
    if (!validEmail) return setError(t('auth.badEmail'));
    setBusy('email');
    setError(null);
    const { error: e } = await supabase.auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
    setBusy(null);
    if (e) setError(e.message);
  }

  const legal = <LegalFooter lead="auth.legal" onDark={mode === 'welcome'} />;

  // ---------- Welcome ----------
  if (mode === 'welcome') {
    return (
      <Screen edges={['top', 'bottom']} style={{ backgroundColor: lightPalette.blue }}>
        <Ridge width={width} height={110} fill={lightPalette.blueDeep} snow={snowOnHorizon()} style={styles.ridge} />
        <View style={styles.wrap}>
          <View style={styles.langs}>
            {(['kk', 'ru', 'en'] as Locale[]).map((l) => (
              <Pressable key={l} onPress={() => setLocale(l)} hitSlop={8} accessibilityRole="button">
                <Text maxFontSizeMultiplier={1.6} style={[styles.lang, l === locale && styles.langOn]}>
                  {l === 'kk' ? 'ҚАЗ' : l === 'ru' ? 'РУС' : 'ENG'}
                </Text>
              </Pressable>
            ))}
          </View>

          <View style={styles.hero}>
            <Mark size={112} color={lightPalette.gold} animate />
            <Text maxFontSizeMultiplier={1.3} style={styles.word}>Qadam</Text>
            <Text maxFontSizeMultiplier={1.3} style={styles.tagline}>{t('auth.tagline')}</Text>
            <Text maxFontSizeMultiplier={1.6} style={styles.sub}>{t('auth.sub')}</Text>
          </View>

          <View style={styles.buttons}>
            {!isConfigured && <Text maxFontSizeMultiplier={1.6} style={styles.errorOnBlue}>{t('auth.notConfigured')}</Text>}
            {hasApple && (
              <AppleAuthentication.AppleAuthenticationButton
                buttonType={AppleAuthentication.AppleAuthenticationButtonType.CONTINUE}
                buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.WHITE}
                cornerRadius={25}
                style={styles.appleBtn}
                onPress={() => social('apple')}
              />
            )}
            {googleEnabled && (
              <Button title={t('welcome.google')} variant="secondary" onPress={() => social('google')}
                style={{ backgroundColor: '#FFFFFF', borderColor: '#FFFFFF' }} textColor={lightPalette.ink}
                loading={busy === 'google'} icon={<Ionicons name="logo-google" size={18} color={lightPalette.ink} />} />
            )}
            <Button title={t('welcome.email')} variant="ghost" textColor={colors.white}
              style={{ borderColor: 'rgba(255,255,255,0.55)' }}
              icon={<Icon name="mail" size={19} color="#FFFFFF" />}
              onPress={() => { setError(null); setMode('email'); }} />
            {error && <Text maxFontSizeMultiplier={1.6} style={styles.errorOnBlue}>{error}</Text>}
            {legal}
          </View>
        </View>
      </Screen>
    );
  }

  // ---------- Email, code, password ----------
  return (
    <Screen edges={['top', 'bottom']}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <Pressable style={styles.back} hitSlop={12} accessibilityRole="button" accessibilityLabel={t('common.back')}
          onPress={() => { setError(null); setCode(''); setMode(mode === 'code' ? 'email' : 'welcome'); }}>
          <Icon name="back" size={24} color="blueText" weight="bold" />
        </Pressable>
        <ScrollView contentContainerStyle={styles.form} keyboardShouldPersistTaps="handled">
          <H1>{mode === 'code' ? t('auth.code') : t('welcome.emailTitle')}</H1>
          <P muted>{mode === 'code' ? t('auth.codeSent', { email: email.trim() }) : t('welcome.emailHint')}</P>

          {mode !== 'code' && (
            <Field value={email} onChangeText={setEmail} placeholder={t('auth.emailPlaceholder')}
              keyboardType="email-address" autoCapitalize="none" autoComplete="email" textContentType="emailAddress"
              autoFocus returnKeyType="next" onSubmitEditing={mode === 'email' ? sendCode : undefined} />
          )}
          {mode === 'code' && (
            <Field value={code} autoFocus
              onChangeText={(v) => {
                const c = v.replace(/\D/g, '').slice(0, 6);
                setCode(c);
                if (c.length === 6) verifyCode(c); // submit as soon as the code is complete
              }}
              placeholder="••••••" keyboardType="number-pad" autoComplete="one-time-code" textContentType="oneTimeCode"
              style={{ letterSpacing: 10, fontFamily: fonts.text600, fontSize: 26, textAlign: 'center' }} />
          )}
          {mode === 'password' && (
            <Field value={password} onChangeText={setPassword} placeholder={t('auth.password')}
              secureTextEntry autoComplete="password" />
          )}

          {error && <Text maxFontSizeMultiplier={1.6} style={styles.error}>{error}</Text>}

          {mode === 'email' && (
            <Button title={t('auth.sendCode')} onPress={sendCode} loading={busy === 'email'} disabled={!validEmail} />
          )}
          {mode === 'code' && (
            <>
              <Button title={t('auth.verify')} onPress={() => verifyCode()} loading={busy === 'email'} disabled={code.length < 6} />
              <Text maxFontSizeMultiplier={1.6} style={styles.link} onPress={sendCode}>{t('auth.sendCode')}</Text>
            </>
          )}
          {mode === 'password' && (
            <Button title={t('auth.verify')} onPress={signInWithPassword} loading={busy === 'email'} disabled={!password} />
          )}
          {mode !== 'code' && (
            <Text maxFontSizeMultiplier={1.6} style={styles.link} onPress={() => { setError(null); setMode(mode === 'password' ? 'email' : 'password'); }}>
              {mode === 'password' ? t('auth.useCode') : t('auth.usePassword')}
            </Text>
          )}
          {legal}
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, paddingHorizontal: space(2), paddingBottom: space(2), justifyContent: 'space-between' },
  langs: { flexDirection: 'row', justifyContent: 'flex-end', gap: space(2), paddingTop: space(1) },
  lang: { color: lightPalette.blueMist, fontFamily: fonts.text800, fontSize: 13, letterSpacing: 1, paddingVertical: 12 },
  langOn: { color: colors.white, textDecorationLine: 'underline' },
  hero: { alignItems: 'center', gap: space(1) },
  word: { fontFamily: fonts.display, fontSize: 46, lineHeight: 54, color: colors.white, letterSpacing: -1 },
  tagline: { fontFamily: fonts.displayMedium, fontSize: 18, lineHeight: 24, color: colors.gold, textAlign: 'center' },
  sub: { fontFamily: fonts.text500, fontSize: 16, lineHeight: 22, color: lightPalette.blueMist, textAlign: 'center', maxWidth: 300 },
  ridge: { position: 'absolute', left: 0, bottom: 0 },
  buttons: { gap: space(1.25) },
  appleBtn: { height: 50, width: '100%' },
  back: { paddingHorizontal: space(2), paddingTop: space(1), alignSelf: 'flex-start' },
  form: { padding: space(2), paddingTop: space(3), gap: space(2) },
  errorOnBlue: { color: colors.white, fontFamily: fonts.text600, fontSize: 14, textAlign: 'center' },
  error: { color: colors.danger, fontFamily: fonts.text500, fontSize: 15 },
  link: { color: colors.blueText, textAlign: 'center', fontFamily: fonts.text700, paddingVertical: 6 },
  legal: { color: lightPalette.blueMist, fontFamily: fonts.text500, fontSize: 12, textAlign: 'center', lineHeight: 17, marginTop: space(0.5) },
  underline: { textDecorationLine: 'underline' },
});
