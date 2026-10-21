// Story cards (9:16) people post to Instagram or WhatsApp: "I'm going",
// "I joined the circle", "Join my club". Each carries the person's invite code,
// so every post is also an invitation — the loop Ritmo doesn't have.
// Rendered off-screen, captured at 1080×1920 with react-native-view-shot.
import * as Sharing from 'expo-sharing';
import React, { useRef, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { captureRef } from 'react-native-view-shot';
import { useI18n } from '../i18n';
import { tick } from '../lib/haptics';
import { snowOnHorizon } from '../lib/season';
import { fonts, lightPalette as c, memberNo } from '../lib/theme';
import { Mark, Ridge, Shanyrak } from './Brand';
import { Icon } from './Icon';
import { Button } from './ui';
import { showError } from '../lib/errors';

export type ShareKind = 'going' | 'joined' | 'club';

const W = 360;
const H = 640;

function Card({ kind, title, line, code, member }: { kind: ShareKind; title: string; line: string; code: string; member?: number }) {
  const { t } = useI18n();
  const label = kind === 'going' ? t('share.going') : kind === 'joined' ? t('share.joined') : t('share.club');
  return (
    <View style={styles.card}>
      <Ridge width={W} height={150} fill={c.blueDeep} snow={snowOnHorizon()} style={styles.ridge} />
      <Mark size={64} color={c.gold} />
      <Text allowFontScaling={false} style={styles.label}>{label}</Text>
      {kind === 'joined' && member ? (
        <View style={styles.seal}>
          <Shanyrak size={180} color={c.gold} slats={0.25} style={StyleSheet.absoluteFill} />
          <Text allowFontScaling={false} style={styles.sealNo}>{memberNo(member)}</Text>
        </View>
      ) : null}
      <Text allowFontScaling={false} style={styles.title} numberOfLines={3}>{title}</Text>
      <Text allowFontScaling={false} style={styles.line} numberOfLines={2}>{line}</Text>
      {kind !== 'joined' ? <Text allowFontScaling={false} style={styles.come}>{t('share.come')}</Text> : null}
      <View style={styles.codeBox}>
        <Text allowFontScaling={false} style={styles.code}>{t('share.code', { code })}</Text>
        <Text allowFontScaling={false} style={styles.site}>qadam.app</Text>
      </View>
    </View>
  );
}

function useShareCard(props: { kind: ShareKind; title: string; line: string; code: string; member?: number }) {
  const ref = useRef<View>(null);
  const { t } = useI18n();
  const [busy, setBusy] = useState(false);
  async function share() {
    if (!ref.current) return;
    tick();
    setBusy(true);
    try {
      const uri = await captureRef(ref, { format: 'png', quality: 1, result: 'tmpfile', width: 1080, height: 1920 });
      if (await Sharing.isAvailableAsync()) {
        await Sharing.shareAsync(uri, { mimeType: 'image/png', UTI: 'public.png' });
      }
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }
  const offscreen = (
    <View style={styles.offscreen} pointerEvents="none" importantForAccessibility="no-hide-descendants" accessibilityElementsHidden>
      <View ref={ref} collapsable={false}><Card {...props} /></View>
    </View>
  );
  return { share, busy, offscreen };
}

/** A header icon button that shares the story card. */
export function ShareCardButton(props: { kind: ShareKind; title: string; line: string; code: string; member?: number }) {
  const { t } = useI18n();
  const { share, busy, offscreen } = useShareCard(props);
  return (
    <>
      {offscreen}
      <Pressable onPress={share} hitSlop={12} accessibilityRole="button" accessibilityLabel={t('share.button')} disabled={busy}>
        {busy ? <ActivityIndicator /> : <Icon name="share" size={20} color="blueText" />}
      </Pressable>
    </>
  );
}

/** A full-width "Share to stories" button. */
export function ShareCardWideButton(props: {
  kind: ShareKind; title: string; line: string; code: string; member?: number; variant?: 'secondary' | 'ghost';
}) {
  const { t } = useI18n();
  const { share, busy, offscreen } = useShareCard(props);
  return (
    <>
      {offscreen}
      <Button title={t('share.button')} variant={props.variant ?? 'secondary'} onPress={share} loading={busy}
        icon={<Icon name="share" size={18} color={props.variant === 'ghost' ? '#FFFFFF' : 'blueText'} />}
        textColor={props.variant === 'ghost' ? '#FFFFFF' : undefined} />
    </>
  );
}

const styles = StyleSheet.create({
  offscreen: { position: 'absolute', left: -4000, top: 0, width: W, height: H },
  card: {
    width: W, height: H, backgroundColor: c.blue, alignItems: 'center', paddingTop: 64, paddingHorizontal: 28,
    gap: 12, overflow: 'hidden',
  },
  ridge: { position: 'absolute', left: 0, bottom: 0 },
  label: { fontFamily: fonts.text800, fontSize: 14, letterSpacing: 3, color: c.gold, marginTop: 10 },
  seal: { width: 180, height: 180, alignItems: 'center', justifyContent: 'center', marginVertical: 4 },
  sealNo: { fontFamily: fonts.display, fontSize: 28, color: '#FFFFFF' },
  title: { fontFamily: fonts.display, fontSize: 34, lineHeight: 40, color: '#FFFFFF', textAlign: 'center', letterSpacing: -0.5 },
  line: { fontFamily: fonts.text600, fontSize: 16, lineHeight: 22, color: c.blueMist, textAlign: 'center' },
  come: { fontFamily: fonts.displayMedium, fontSize: 16, color: c.gold, marginTop: 6 },
  codeBox: {
    position: 'absolute', bottom: 34, alignSelf: 'center', backgroundColor: '#F7F4EE', borderRadius: 999,
    paddingHorizontal: 20, paddingVertical: 10, alignItems: 'center',
  },
  code: { fontFamily: fonts.text800, fontSize: 14, color: c.ink },
  site: { fontFamily: fonts.displayMedium, fontSize: 11, color: c.blue, marginTop: 1 },
});
