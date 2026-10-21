import { useFocusEffect, useRouter } from 'expo-router';
import React, { useCallback, useState } from 'react';
import { Alert, Linking, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { Shanyrak } from '../../../src/components/Brand';
import { Felt } from '../../../src/components/Felt';
import { ProfileCardView, REGULAR_AFTER } from '../../../src/components/ProfileCard';
import * as Clipboard from 'expo-clipboard';
import { toast } from '../../../src/components/Toast';
import { Button, Field, ListItem, ListSection, Row, SectionLabel, T } from '../../../src/components/ui';
import { useI18n } from '../../../src/i18n';
import { api } from '../../../src/lib/api';
import { formatShortDate } from '../../../src/lib/dates';
import { env } from '../../../src/lib/env';
import { useSession } from '../../../src/lib/session';
import { colors, curve, felt, fonts, layout, radius, sp, type } from '../../../src/lib/theme';
import type { ProfileCard } from '../../../src/lib/types';
import { features } from '../../../src/lib/features';

export default function Me() {
  const { t, intl } = useI18n();
  const router = useRouter();
  const { profile, limits, refreshLimits, refreshProfile } = useSession();
  const [card, setCard] = useState<ProfileCard | null>(null);
  const [code, setCode] = useState('');
  const [cardFailed, setCardFailed] = useState(false);

  const load = useCallback(async () => {
    if (!profile) return;
    try {
      setCard(await api.getProfile(profile.id));
      setCardFailed(false);
    } catch {
      setCardFailed(true);
    }
    refreshLimits();
  }, [profile, refreshLimits]);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  if (!profile) return null;

  const verifyLabel =
    profile.verification_status === 'approved' ? t('me.verified')
    : profile.verification_status === 'pending' ? t('me.verifyPending')
    : profile.verification_status === 'rejected' ? t('me.verifyRejected')
    : t('me.verify');

  async function redeem() {
    const r = await api.redeemReferral(code);
    if (r.ok) {
      toast(t('me.redeemed'));
      setCode('');
      refreshProfile();
    } else {
      Alert.alert(t('common.error'), r.error);
    }
  }

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" style={{ backgroundColor: colors.bg }}
      contentContainerStyle={styles.page}>
      <View style={{ gap: sp.md }}>
        {card ? <ProfileCardView p={card} compact /> : cardFailed ? (
          <View style={styles.cardError}>
            <T variant="callout" style={{ flex: 1 }}>{t('states.errorTitle')}</T>
            <Button title={t('common.retry')} variant="secondary" compact onPress={load} />
          </View>
        ) : null}
        <Button title={t('me.editProfile')} variant="secondary" onPress={() => router.push('/edit-profile')} />
      </View>

      {card && card.events_attended >= REGULAR_AFTER ? (
        <Felt style={styles.patch}>
          <Shanyrak size={52} color={felt.label} slats={0.7} />
          <View style={{ flex: 1, gap: sp.xxs }}>
            <Text maxFontSizeMultiplier={1.35} style={styles.patchTitle}>{t('circle.regular')}</Text>
            <Text maxFontSizeMultiplier={1.6} style={styles.patchSub}>{t('card.events', { n: card.events_attended })}</Text>
          </View>
        </Felt>
      ) : null}

      <View style={styles.pro}>
        <View style={{ flex: 1, gap: sp.xxs }}>
          <Text maxFontSizeMultiplier={1.3} style={styles.proTitle}>{t('me.pro')}</Text>
          <Text maxFontSizeMultiplier={1.6} style={styles.proSub}>
            {limits?.pro && limits.pro_until
              ? t('me.proActive', { date: formatShortDate(limits.pro_until, intl) })
              : `${t('paywall.f1')} · ${t('paywall.f2')}`}
          </Text>
        </View>
        <Button title={limits?.pro ? t('me.manage') : t('me.getPro')} variant="accent" compact onPress={() => router.push('/paywall')} />
      </View>

      <View style={{ gap: sp.sm }}>
        <Row gap={sp.sm} style={{ alignItems: 'stretch' }}>
          <Stat label={t('me.boosts')} value={String((limits?.boost_credits ?? 0) + (limits?.free_boost_available ? 1 : 0))} />
          <Stat label={t('me.supers')} value={String(limits?.supers_left ?? 0)} />
          <Stat label={t('me.streak')} value={String(limits?.streak_days ?? 0)} />
        </Row>
        <T variant="footnote" style={{ paddingHorizontal: layout.margin, textAlign: 'center' }}>{t('me.streakHint')}</T>
      </View>

      <ListSection>
        <ListItem icon="duo" tint="clay" title={t('duo.title')} subtitle={t('duo.intro')} onPress={() => router.push('/duo')} />
        <ListItem icon="note" title={t('prompts.title')} subtitle={t('prompts.nudge')} onPress={() => router.push('/prompts')} />
        <ListItem icon="verified" tint="good" title={verifyLabel}
          onPress={profile.verification_status === 'approved' || profile.verification_status === 'pending' ? undefined : () => router.push('/verify')}
          right={profile.verification_status === 'approved' ? '✓' : undefined} />
        {!features.events ? null : profile.is_host ? (
          <ListItem icon="add" tint="clayDeep" title={t('events.create')} onPress={() => router.push('/event/new')} />
        ) : (
          <ListItem icon="flag" tint="clayDeep" title={t('me.becomeHost')} subtitle={t('me.becomeHostHint')}
            onPress={() => Linking.openURL(`mailto:${env.supportEmail}?subject=Qadam host`)} />
        )}
      </ListSection>

      <ListSection header={t('me.invite')} footer={t('me.inviteHint')}>
        <ListItem title={t('me.yourCode')} right={profile.referral_code}
          onPress={() => { Clipboard.setStringAsync(profile.referral_code).catch(() => {}); toast(t('states.copied'), { icon: 'copy' }); }} />
        <ListItem icon="share" title={t('me.invite')}
          onPress={() => Share.share({ message: t('me.inviteMessage', { code: profile.referral_code }) })} />
      </ListSection>

      <View>
        <SectionLabel style={{ paddingHorizontal: layout.margin }}>{t('me.redeem')}</SectionLabel>
        <Row>
          <View style={{ flex: 1 }}>
            <Field value={code} onChangeText={(v) => setCode(v.toUpperCase())} placeholder="ABC123"
              autoCapitalize="characters" maxLength={6} accessibilityLabel={t('me.redeem')} />
          </View>
          <Button title={t('me.apply')} variant="secondary" compact onPress={redeem} disabled={code.length < 6} />
        </Row>
      </View>
    </ScrollView>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.stat} accessible accessibilityLabel={`${label}: ${value}`}>
      <Text maxFontSizeMultiplier={1.3} style={styles.statValue}>{value}</Text>
      <Text maxFontSizeMultiplier={1.4} style={styles.statLabel} numberOfLines={1}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  cardError: { flexDirection: 'row', alignItems: 'center', gap: sp.md, backgroundColor: colors.card, borderRadius: radius.lg, padding: sp.lg },
  page: { padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 },
  patch: { flexDirection: 'row', alignItems: 'center', gap: sp.md, borderRadius: radius.lg, ...curve, padding: sp.lg },
  patchTitle: { ...type.title3, color: felt.ink },
  patchSub: { ...type.footnote, fontFamily: fonts.text600, color: '#5B5240' },
  pro: {
    backgroundColor: colors.blue, borderRadius: radius.lg, ...curve, padding: sp.lg, flexDirection: 'row',
    alignItems: 'center', gap: sp.md,
  },
  proTitle: { ...type.title2, color: colors.white },
  proSub: { ...type.footnote, color: colors.blueMist },
  stat: { flex: 1, backgroundColor: colors.card, borderRadius: radius.md, ...curve, paddingVertical: sp.md, paddingHorizontal: sp.sm, alignItems: 'center', gap: sp.xxs },
  statValue: { ...type.title2, color: colors.ink, fontVariant: ['tabular-nums'] },
  statLabel: { ...type.caption, color: colors.inkSoft },
});
