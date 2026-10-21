import { Icon } from '../src/components/Icon';
import { Image } from 'expo-image';
import { Stack, useRouter } from 'expo-router';
import React, { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator, Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, View,
} from 'react-native';
import { HeaderTextButton } from '../src/components/HeaderButton';
import { Button, Chip, Field, ListItem, ListSection, Row, Screen, SectionLabel, Tag, T } from '../src/components/ui';
import { useI18n, type TKey } from '../src/i18n';
import { api } from '../src/lib/api';
import { useSession } from '../src/lib/session';
import { CITIES, currentSeason, useSports } from '../src/lib/sports';
import { supabase } from '../src/lib/supabase';
import { colors, curve, fonts, iconSize, layout, radius, sp } from '../src/lib/theme';
import type { InterestedIn, Level, Mode } from '../src/lib/types';
import { deleteProfilePhoto, pickPhoto, uploadProfilePhoto } from '../src/lib/upload';
import { showError } from '../src/lib/errors';

const LEVEL_CYCLE: Level[] = ['casual', 'regular', 'competitive', 'beginner'];

export default function EditProfile() {
  const { t, sportName, cityName } = useI18n();
  const { sports } = useSports();
  const { profile, refreshProfile } = useSession();
  const router = useRouter();

  const [name, setName] = useState(profile?.name ?? '');
  const [bio, setBio] = useState(profile?.bio ?? '');
  const [challenge, setChallenge] = useState(profile?.next_challenge ?? '');
  const [city, setCity] = useState(profile?.city ?? 'almaty');
  const [interested, setInterested] = useState<InterestedIn>(profile?.interested_in ?? 'everyone');
  const [mode, setMode] = useState<Mode>(profile?.mode ?? 'dating');
  const [buddyWith, setBuddyWith] = useState<InterestedIn>(profile?.buddy_with ?? 'everyone');
  const [ageMin, setAgeMin] = useState(String(profile?.age_min ?? 18));
  const [ageMax, setAgeMax] = useState(String(profile?.age_max ?? 60));
  const [photos, setPhotos] = useState<string[]>(profile?.photos ?? []);
  const [picked, setPicked] = useState<Record<string, Level> | null>(null);
  const [achievements, setAchievements] = useState<{ id: string; title: string; result: string | null }[]>([]);
  const [newTitle, setNewTitle] = useState('');
  const [newResult, setNewResult] = useState('');
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    api.mySports().then((rows) => setPicked(Object.fromEntries(rows.map((r) => [r.sport_code, r.level as Level]))));
    api.myAchievements().then(setAchievements);
  }, []);

  const season = currentSeason();
  const ordered = useMemo(() => [...sports].sort((a, b) =>
    Number(b.season === season || b.season === 'all') - Number(a.season === season || a.season === 'all')), [sports, season]);

  if (!profile) return null;
  const userId = profile.id;

  function toggleSport(code: string) {
    setPicked((cur) => {
      const copy = { ...(cur ?? {}) };
      if (!(code in copy)) copy[code] = 'casual';
      else {
        const i = LEVEL_CYCLE.indexOf(copy[code]);
        if (i === LEVEL_CYCLE.length - 1) delete copy[code];
        else copy[code] = LEVEL_CYCLE[i + 1];
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
      showError(t, e);
    } finally {
      setUploading(false);
    }
  }

  function removePhoto(url: string) {
    if (photos.length <= 1) return;
    Alert.alert(t('common.delete'), undefined, [
      { text: t('common.cancel'), style: 'cancel' },
      { text: t('common.delete'), style: 'destructive', onPress: () => setPhotos((p) => p.filter((x) => x !== url)) },
    ]);
  }

  async function addAchievement() {
    if (!newTitle.trim()) return;
    const { data, error } = await supabase.from('achievements')
      .insert({ profile_id: userId, title: newTitle.trim(), result: newResult.trim() || null })
      .select('id, title, result').single();
    if (error) return Alert.alert(t('common.error'), error.message);
    setAchievements((a) => [data as { id: string; title: string; result: string | null }, ...a]);
    setNewTitle('');
    setNewResult('');
  }

  async function removeAchievement(id: string) {
    await supabase.from('achievements').delete().eq('id', id);
    setAchievements((a) => a.filter((x) => x.id !== id));
  }

  async function save() {
    if (!picked || Object.keys(picked).length === 0) return Alert.alert(t('onboarding.pickOne'));
    if (photos.length === 0) return Alert.alert(t('onboarding.needPhoto'));
    const min = Math.max(18, Math.min(99, Number(ageMin) || 18));
    const max = Math.max(min, Math.min(99, Number(ageMax) || 60));
    setSaving(true);
    try {
      const removed = (profile?.photos ?? []).filter((u) => !photos.includes(u));
      const { error } = await supabase.from('profiles').update({
        name: name.trim(), bio: bio.trim() || null, next_challenge: challenge.trim() || null, city,
        interested_in: interested, age_min: min, age_max: max, photos, mode, buddy_with: buddyWith,
      }).eq('id', userId);
      if (error) throw new Error(error.message);
      // Replace sports: delete then insert (both scoped to my rows by RLS).
      const { error: dErr } = await supabase.from('profile_sports').delete().eq('profile_id', userId);
      if (dErr) throw new Error(dErr.message);
      const { error: iErr } = await supabase.from('profile_sports').insert(
        Object.entries(picked).map(([sport_code, level]) => ({ profile_id: userId, sport_code, level })));
      if (iErr) throw new Error(iErr.message);
      await Promise.all(removed.map((u) => deleteProfilePhoto(u).catch(() => {})));
      await refreshProfile();
      router.back();
    } catch (e) {
      showError(t, e);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Screen edges={['bottom']}>
      <Stack.Screen options={{
        headerRight: () => saving ? <ActivityIndicator /> : <HeaderTextButton title={t('common.save')} bold onPress={save} />,
      }} />
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 }} keyboardShouldPersistTaps="handled">
          <View style={styles.grid}>
            {photos.map((u, k) => (
              <Pressable key={u} style={styles.slot} onLongPress={() => removePhoto(u)} accessibilityHint={t('common.delete')}>
                <Image source={{ uri: u }} style={StyleSheet.absoluteFill} contentFit="cover" />
                {k === 0 ? <Tag label={t('edit.main')} tone="solid" style={styles.mainTag} /> : null}
              </Pressable>
            ))}
            {photos.length < 6 && (
              <Pressable style={[styles.slot, styles.add]} onPress={addPhoto} disabled={uploading}>
                {uploading ? <ActivityIndicator color={colors.blueText as string} /> : <Icon name="add" size={iconSize.action} color="blueText" />}
              </Pressable>
            )}
          </View>

          <Field label={t('onboarding.namePlaceholder')} value={name} onChangeText={setName} maxLength={40} />
          <Field label={t('onboarding.challengeTitle')} value={challenge} onChangeText={setChallenge} maxLength={80}
            placeholder={t('onboarding.challengePlaceholder')} />
          <Field label={t('onboarding.bioTitle')} value={bio} onChangeText={setBio} multiline maxLength={500} />

          <ListSection>
            <ListItem icon="note" title={t('prompts.title')} subtitle={t('prompts.hint')} onPress={() => router.push('/prompts')} />
          </ListSection>

          <Section title={t('mode.title')}>
            <Row style={{ flexWrap: 'wrap' }}>
              {(['dating', 'buddy', 'both'] as Mode[]).map((m) => (
                <Chip key={m} label={t(`mode.${m}` as TKey)} selected={mode === m} onPress={() => setMode(m)} />
              ))}
            </Row>
            {mode !== 'dating' ? (
              <>
                <T variant="footnote">{t('mode.buddyHint')}</T>
                <T variant="callout" tone="inkSoft" style={{ fontFamily: fonts.text700, marginTop: sp.sm }}>{t('mode.buddyWith')}</T>
                <Row style={{ flexWrap: 'wrap' }}>
                  {(['women', 'men', 'everyone'] as InterestedIn[]).map((g) => (
                    <Chip key={g} label={t(`onboarding.${g}` as TKey)} selected={buddyWith === g} onPress={() => setBuddyWith(g)} />
                  ))}
                </Row>
              </>
            ) : null}
          </Section>

          <Section title={t('onboarding.sportsTitle')}>
            {picked === null ? <ActivityIndicator /> : (
              <Row style={{ flexWrap: 'wrap' }}>
                {ordered.map((s) => (
                  <Chip key={s.code} label={sportName(s)} selected={s.code in picked}
                    sub={picked[s.code] ? t(`levels.${picked[s.code]}` as TKey) : undefined}
                    onPress={() => toggleSport(s.code)} />
                ))}
              </Row>
            )}
          </Section>

          <Section title={t('edit.achievements')}>
            {achievements.map((a) => (
              <Row key={a.id} style={styles.ach}>
                <T variant="callout" tone="ink" style={{ flex: 1 }}>{a.title}{a.result ? ` — ${a.result}` : ''}</T>
                <Pressable style={styles.remove} onPress={() => removeAchievement(a.id)} accessibilityRole="button" hitSlop={6}
                  accessibilityLabel={t('common.delete')}><Icon name="trash" size={iconSize.row} color="danger" /></Pressable>
              </Row>
            ))}
            <Field value={newTitle} onChangeText={setNewTitle} placeholder={t('edit.achievementTitle')} maxLength={60} />
            <Row>
              <View style={{ flex: 1 }}>
                <Field value={newResult} onChangeText={setNewResult} placeholder={t('edit.achievementResult')} maxLength={20} />
              </View>
              <Button title={t('edit.addAchievement')} variant="secondary" compact onPress={addAchievement} disabled={!newTitle.trim()} />
            </Row>
          </Section>

          <Section title={t('onboarding.cityTitle')}>
            <Row style={{ flexWrap: 'wrap' }}>
              {CITIES.map((c) => <Chip key={c} label={cityName(c)} selected={city === c} onPress={() => setCity(c)} />)}
            </Row>
          </Section>

          <Section title={t('onboarding.interestedTitle')}>
            <Row style={{ flexWrap: 'wrap' }}>
              {(['women', 'men', 'everyone'] as InterestedIn[]).map((g) => (
                <Chip key={g} label={t(`onboarding.${g}` as TKey)} selected={interested === g} onPress={() => setInterested(g)} />
              ))}
            </Row>
            <T variant="callout" tone="inkSoft" style={{ fontFamily: fonts.text700, marginTop: sp.sm }}>{t('edit.ageRange', { min: ageMin || '18', max: ageMax || '60' })}</T>
            <Row>
              <View style={{ flex: 1 }}><Field value={ageMin} onChangeText={(v) => setAgeMin(v.replace(/\D/g, '').slice(0, 2))} keyboardType="number-pad" /></View>
              <T variant="body" tone="muted">—</T>
              <View style={{ flex: 1 }}><Field value={ageMax} onChangeText={(v) => setAgeMax(v.replace(/\D/g, '').slice(0, 2))} keyboardType="number-pad" /></View>
            </Row>
          </Section>

          <Button title={t('common.save')} onPress={save} loading={saving} />
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={{ gap: sp.sm }}>
      <SectionLabel style={{ marginBottom: 0 }}>{title}</SectionLabel>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: sp.sm },
  slot: { width: '31.5%', aspectRatio: 4 / 5, borderRadius: radius.md, ...curve, overflow: 'hidden', backgroundColor: colors.line },
  add: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.blueTint },
  mainTag: { position: 'absolute', left: sp.sm, top: sp.sm },
  ach: { backgroundColor: colors.card, borderRadius: radius.md, ...curve, paddingLeft: sp.lg, paddingRight: sp.xs, minHeight: 48 },
  remove: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
});
