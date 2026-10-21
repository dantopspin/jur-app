import { Image } from 'expo-image';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator, Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View,
} from 'react-native';
import { Mark, OrnamentProgress } from '../src/components/Brand';
import { Icon } from '../src/components/Icon';
import { knock, tick } from '../src/lib/haptics';
import { Button, Chip, Field, H1, P, Row, Screen, Tag } from '../src/components/ui';
import { useI18n, type TKey } from '../src/i18n';
import { api } from '../src/lib/api';
import { useSession } from '../src/lib/session';
import { CITIES, currentSeason, useSports } from '../src/lib/sports';
import { supabase } from '../src/lib/supabase';
import { colors, curve, fonts, iconSize, layout, lightPalette, radius, sp, space, type } from '../src/lib/theme';
import type { Gender, InterestedIn, Level, Mode } from '../src/lib/types';
import { pickPhoto, uploadProfilePhoto } from '../src/lib/upload';
import { ageOn, isAdult, parseBirthdate } from '../src/lib/dates';
import { pushPermission, requestPushPermission, syncPushToken } from '../src/lib/push';
import { takePrefillName } from '../src/lib/socialAuth';
import { features } from '../src/lib/features';

// One question per screen, auto-advance on single choices, nothing optional
// blocks the way. Order follows the best dating apps: identity → who you want
// to meet → what you do → photos → about you → notifications.
type StepId = 'name' | 'birth' | 'gender' | 'interested' | 'mode' | 'city' | 'sports' | 'photos' | 'about' | 'notify';
const BASE_STEPS: StepId[] = ['name', 'birth', 'gender', 'interested', 'mode', 'city', 'sports', 'photos', 'about'];
const LEVEL_CYCLE: Level[] = ['casual', 'regular', 'competitive', 'beginner'];

export default function Onboarding() {
  const { t, sportName, cityName, locale } = useI18n();
  const { session, refreshProfile, signOut } = useSession();
  const { sports } = useSports();
  const userId = session?.user.id ?? '';

  const [steps, setSteps] = useState<StepId[]>(BASE_STEPS);
  const [i, setI] = useState(0);
  const [name, setName] = useState(() => takePrefillName());
  const [dd, setDd] = useState('');
  const [mm, setMm] = useState('');
  const [yyyy, setYyyy] = useState('');
  const [gender, setGender] = useState<Gender | null>(null);
  const [interested, setInterested] = useState<InterestedIn | null>(null);
  const [mode, setMode] = useState<Mode | null>(null);
  const [city, setCity] = useState<string | null>(null);
  const [picked, setPicked] = useState<Record<string, Level>>({});
  const [challenge, setChallenge] = useState('');
  const [bio, setBio] = useState('');
  const [photos, setPhotos] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);
  const [showInvite, setShowInvite] = useState(false);
  const [referral, setReferral] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const advanceTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Ask about notifications only if the phone hasn't been asked yet.
  useEffect(() => {
    pushPermission().then((p) => { if (p === 'undetermined') setSteps([...BASE_STEPS, 'notify']); });
    return () => { if (advanceTimer.current) clearTimeout(advanceTimer.current); };
  }, []);

  const step = steps[i];
  const last = i === steps.length - 1;
  const season = currentSeason();
  const groups = useMemo(() => {
    const order: ('summer' | 'winter' | 'all')[] = season === 'winter' ? ['winter', 'all', 'summer'] : ['summer', 'all', 'winter'];
    return order.map((s) => ({ season: s, items: sports.filter((x) => x.season === s) }));
  }, [sports, season]);

  const birth = parseBirthdate(dd, mm, yyyy);
  const pickedCount = Object.keys(picked).length;

  function canContinue(): boolean {
    switch (step) {
      case 'name': return name.trim().length > 0;
      case 'birth': return birth !== null;
      case 'gender': return gender !== null;
      case 'interested': return interested !== null;
      case 'mode': return mode !== null;
      case 'city': return city !== null;
      case 'sports': return pickedCount > 0;
      case 'photos': return photos.length > 0 && !uploading;
      default: return true;
    }
  }

  function go(to: number) {
    setError(null);
    setI(Math.max(0, Math.min(steps.length - 1, to)));
  }

  function next() {
    setError(null);
    if (step === 'birth') {
      if (!birth) return setError(t('onboarding.badDate'));
      if (!isAdult(birth)) return setError(t('onboarding.tooYoung'));
      // The age can't be changed later, so confirm it (as Tinder and Hinge do).
      return Alert.alert(t('flow.confirmAge', { age: ageOn(birth) }), t('flow.confirmAgeSub'), [
        { text: t('flow.confirmEdit'), style: 'cancel' },
        { text: t('flow.confirmYes'), onPress: () => go(i + 1) },
      ]);
    }
    if (last) finish(false);
    else go(i + 1);
  }

  /** Single-choice screens move on by themselves after a short beat. */
  function chooseThenAdvance(apply: () => void) {
    apply();
    if (advanceTimer.current) clearTimeout(advanceTimer.current);
    advanceTimer.current = setTimeout(() => setI((cur) => cur + 1), 220);
  }

  function toggleSport(code: string) {
    setPicked((cur) => {
      const copy = { ...cur };
      if (!(code in copy)) copy[code] = 'casual';
      else {
        const k = LEVEL_CYCLE.indexOf(copy[code]);
        if (k === LEVEL_CYCLE.length - 1) delete copy[code];
        else copy[code] = LEVEL_CYCLE[k + 1];
      }
      return copy;
    });
  }

  async function addPhoto() {
    try {
      const img = await pickPhoto();
      if (!img) return;
      setUploading(true);
      const url = await uploadProfilePhoto(userId, img);
      setPhotos((p) => [...p, url].slice(0, 6));
    } catch (e) {
      Alert.alert(t('common.error'), e instanceof Error ? e.message : String(e));
    } finally {
      setUploading(false);
    }
  }

  const channelLabels = { matches: t('notify.matches'), chats: t('notify.chats'), activity: t(features.events ? 'notify.activity' : 'notify.activityApp') };

  async function finish(askPush: boolean) {
    if (!birth || !gender || !interested || !city) return;
    if (askPush) await requestPushPermission(channelLabels);
    setSaving(true);
    setError(null);
    try {
      const { error: e1 } = await supabase.from('profiles').insert({
        id: userId,
        name: name.trim(),
        birthdate: birth.toISOString().slice(0, 10),
        gender,
        interested_in: interested,
        city,
        bio: bio.trim() || null,
        next_challenge: challenge.trim() || null,
        photos,
        locale,
        mode: mode ?? 'dating',
      });
      if (e1) throw new Error(e1.message);
      const { error: e2 } = await supabase.from('profile_sports').insert(
        Object.entries(picked).map(([sport_code, level]) => ({ profile_id: userId, sport_code, level })),
      );
      if (e2) throw new Error(e2.message);
      if (referral.trim()) await api.redeemReferral(referral.trim()).catch(() => null);
      syncPushToken(channelLabels);
      await refreshProfile(); // the root gate moves us into the app
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setSaving(false);
    }
  }


  return (
    <Screen edges={['top', 'bottom']}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <View style={styles.top}>
          {i > 0 ? (
            <Pressable onPress={() => go(i - 1)} hitSlop={12} accessibilityRole="button" accessibilityLabel={t('common.back')}
              disabled={saving}>
              <Icon name="back" size={iconSize.toolbar} color="blueText" weight="semibold" />
            </Pressable>
          ) : (
            <Text maxFontSizeMultiplier={1.6} style={styles.topLink} onPress={signOut}>{t('settings.signOut')}</Text>
          )}
          <OrnamentProgress total={steps.length} current={i} />
          {step === 'about' ? (
            <Text maxFontSizeMultiplier={1.6} style={styles.topLink} onPress={() => (last ? finish(false) : go(i + 1))}>{t('flow.skip')}</Text>
          ) : <View style={{ width: 28 }} />}
        </View>

        <ScrollView contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
          {step === 'name' && (
            <>
              <H1>{t('onboarding.nameTitle')}</H1>
              <Field value={name} onChangeText={setName} placeholder={t('onboarding.namePlaceholder')}
                autoFocus maxLength={40} autoComplete="given-name" textContentType="givenName"
                returnKeyType="next" onSubmitEditing={() => canContinue() && next()} />
            </>
          )}

          {step === 'birth' && (
            <>
              <H1>{t('onboarding.birthTitle')}</H1>
              <P muted>{t('onboarding.birthHint')}</P>
              <Row gap={space(1)}>
                <Field value={dd} onChangeText={(v) => setDd(v.replace(/\D/g, '').slice(0, 2))}
                  placeholder={t('onboarding.day')} keyboardType="number-pad" style={{ width: 72, textAlign: 'center' }} autoFocus />
                <Field value={mm} onChangeText={(v) => setMm(v.replace(/\D/g, '').slice(0, 2))}
                  placeholder={t('onboarding.month')} keyboardType="number-pad" style={{ width: 72, textAlign: 'center' }} />
                <Field value={yyyy} onChangeText={(v) => setYyyy(v.replace(/\D/g, '').slice(0, 4))}
                  placeholder={t('onboarding.year')} keyboardType="number-pad" style={{ width: 104, textAlign: 'center' }} />
              </Row>
            </>
          )}

          {step === 'gender' && (
            <>
              <H1>{t('onboarding.genderTitle')}</H1>
              <View style={styles.stack}>
                {(['woman', 'man'] as Gender[]).map((g) => (
                  <Choice key={g} label={t(`onboarding.${g}` as TKey)} selected={gender === g}
                    onPress={() => chooseThenAdvance(() => setGender(g))} />
                ))}
              </View>
            </>
          )}

          {step === 'interested' && (
            <>
              <H1>{t('onboarding.interestedTitle')}</H1>
              <View style={styles.stack}>
                {(['women', 'men', 'everyone'] as InterestedIn[]).map((g) => (
                  <Choice key={g} label={t(`onboarding.${g}` as TKey)} selected={interested === g}
                    onPress={() => chooseThenAdvance(() => setInterested(g))} />
                ))}
              </View>
            </>
          )}

          {step === 'mode' && (
            <>
              <H1>{t('mode.title')}</H1>
              <View style={styles.stack}>
                {(['dating', 'buddy', 'both'] as Mode[]).map((m) => (
                  <Choice key={m} label={t(`mode.${m}` as TKey)} selected={mode === m}
                    onPress={() => chooseThenAdvance(() => setMode(m))} />
                ))}
              </View>
              <P muted>{t('mode.buddyHint')}</P>
            </>
          )}

          {step === 'city' && (
            <>
              <H1>{t('onboarding.cityTitle')}</H1>
              <View style={styles.stack}>
                {CITIES.map((c) => (
                  <Choice key={c} label={cityName(c)} selected={city === c}
                    onPress={() => chooseThenAdvance(() => setCity(c))} />
                ))}
              </View>
            </>
          )}

          {step === 'sports' && (
            <>
              <H1>{t('onboarding.sportsTitle')}</H1>
              <P muted>{t('onboarding.sportsHint')}</P>
              {groups.map((g) => (
                <View key={g.season} style={{ gap: space(1) }}>
                  <Text maxFontSizeMultiplier={1.6} style={styles.group}>
                    {g.season === 'all' ? t('onboarding.allYear') : t(`onboarding.${g.season}` as TKey)}
                  </Text>
                  <Row style={{ flexWrap: 'wrap' }}>
                    {g.items.map((sp) => (
                      <Chip key={sp.code} label={sportName(sp)}
                        sub={picked[sp.code] ? t(`levels.${picked[sp.code]}` as TKey) : undefined}
                        selected={sp.code in picked} onPress={() => toggleSport(sp.code)} />
                    ))}
                  </Row>
                </View>
              ))}
              {sports.length === 0 && <ActivityIndicator color={colors.ink} />}
            </>
          )}

          {step === 'photos' && (
            <>
              <H1>{t('onboarding.photosTitle')}</H1>
              <P muted>{t('onboarding.photosHint')}</P>
              <View style={styles.grid}>
                {photos.map((u, k) => (
                  <Pressable key={u} style={styles.slot} onLongPress={() => { knock(); setPhotos((p) => p.filter((_, j) => j !== k)); }}>
                    <Image source={{ uri: u }} style={StyleSheet.absoluteFill} contentFit="cover" />
                    {k === 0 && <Tag label={t('edit.main')} tone="solid" style={styles.mainTag} />}
                  </Pressable>
                ))}
                {photos.length < 6 && (
                  <Pressable style={[styles.slot, styles.addSlot]} onPress={addPhoto} disabled={uploading}
                    accessibilityRole="button" accessibilityLabel={t('onboarding.addPhoto')}>
                    {uploading ? <ActivityIndicator color={colors.blueText} /> : <Icon name="add" size={iconSize.action} color="blueText" />}
                  </Pressable>
                )}
              </View>
            </>
          )}

          {step === 'about' && (
            <>
              <H1>{t('onboarding.challengeTitle')}</H1>
              <Field value={challenge} onChangeText={setChallenge} placeholder={t('onboarding.challengePlaceholder')} maxLength={80} />
              <H1 style={{ marginTop: sp.lg }}>{t('onboarding.bioTitle')}</H1>
              <Field value={bio} onChangeText={setBio} placeholder={t('onboarding.bioPlaceholder')} multiline maxLength={500} />
              {showInvite ? (
                <Field value={referral} onChangeText={(v) => setReferral(v.toUpperCase())} autoFocus
                  placeholder={t('onboarding.referralTitle')} autoCapitalize="characters" maxLength={6} />
              ) : (
                <Text maxFontSizeMultiplier={1.6} style={styles.link} onPress={() => setShowInvite(true)}>{t('flow.inviteLink')}</Text>
              )}
            </>
          )}

          {step === 'notify' && (
            <View style={styles.notify}>
              <View style={styles.notifyIcon}><Mark size={64} color={lightPalette.gold} animate /></View>
              <H1 style={{ textAlign: 'center' }}>{t('flow.notifyTitle')}</H1>
              <P muted style={{ textAlign: 'center' }}>{t(features.events ? 'flow.notifySub' : 'flow.notifySubApp')}</P>
            </View>
          )}

          {error && <Text maxFontSizeMultiplier={1.6} style={styles.error}>{error}</Text>}
        </ScrollView>

        <View style={styles.footer}>
          {step === 'notify' ? (
            <>
              <Button title={t('flow.notifyAllow')} variant="accent" onPress={() => finish(true)} loading={saving} />
              <Button title={t('flow.notifyLater')} variant="ghost" onPress={() => finish(false)} disabled={saving} />
            </>
          ) : step === 'gender' || step === 'interested' || step === 'mode' || step === 'city' ? null : (
            <Button
              title={step === 'sports' && pickedCount > 0
                ? `${t('common.continue')} · ${t('flow.sportsCount', { n: pickedCount })}`
                : last ? t('onboarding.finish') : t('common.continue')}
              variant={last ? 'accent' : 'primary'}
              onPress={next}
              disabled={!canContinue()}
              loading={saving}
            />
          )}
        </View>
      </KeyboardAvoidingView>
    </Screen>
  );
}

/** A large single-choice row (gender, who to meet, city). */
function Choice({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={() => { tick(); onPress(); }} accessibilityRole="radio" accessibilityState={{ selected }}
      style={({ pressed }) => [styles.choice, selected && styles.choiceOn, pressed && { transform: [{ scale: 0.99 }] }]}>
      <Text maxFontSizeMultiplier={1.6} style={[styles.choiceText, selected && { color: colors.white }]}>{label}</Text>
      {selected ? <Icon name="tick" size={iconSize.row} color="white" weight="bold" /> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  top: { flexDirection: 'row', alignItems: 'center', gap: sp.lg, paddingHorizontal: layout.margin, paddingTop: sp.sm, minHeight: 44 },
  topLink: { ...type.body, fontFamily: fonts.text600, color: colors.blueText },
  body: { padding: layout.margin, paddingTop: sp.xl, gap: sp.lg },
  stack: { gap: sp.sm },
  choice: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', minHeight: 56, paddingHorizontal: sp.lg,
    borderRadius: radius.md, ...curve, backgroundColor: colors.card,
  },
  choiceOn: { backgroundColor: colors.blue },
  choiceText: { ...type.headline, color: colors.ink },
  group: { ...type.overline, color: colors.inkSoft },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: sp.sm },
  slot: { width: '31.5%', aspectRatio: 4 / 5, borderRadius: radius.md, ...curve, overflow: 'hidden', backgroundColor: colors.line },
  addSlot: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.blueTint },
  mainTag: { position: 'absolute', left: sp.sm, top: sp.sm },
  link: { ...type.callout, fontFamily: fonts.text700, color: colors.blueText, paddingVertical: sp.sm },
  notify: { alignItems: 'center', gap: sp.lg, paddingTop: sp.xxl * 1.5 },
  notifyIcon: {
    width: 120, height: 120, borderRadius: 60, backgroundColor: colors.blue, alignItems: 'center', justifyContent: 'center',
  },
  error: { ...type.callout, color: colors.danger },
  footer: { gap: sp.sm, paddingHorizontal: layout.margin, paddingVertical: sp.md },
});
