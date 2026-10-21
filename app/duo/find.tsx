// Browse other pairs in your city. Either friend can like for the duo; it's a
// double date when both sides like each other.
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Mark } from '../../src/components/Brand';
import { Icon, sportIconName } from '../../src/components/Icon';
import { toast } from '../../src/components/Toast';
import { Button, Empty, ErrorState, Row, SkeletonList, T } from '../../src/components/ui';
import { useI18n } from '../../src/i18n';
import { api } from '../../src/lib/api';
import { feedback } from '../../src/lib/feedback';
import { colors, curve, fonts, iconSize, layout, lightPalette, memberNo, radius, sp, type } from '../../src/lib/theme';
import type { ProfileCard } from '../../src/lib/types';

export default function FindDuos() {
  const { t, cityName } = useI18n();
  const router = useRouter();
  const [list, setList] = useState<{ duo_id: string; members: ProfileCard[] }[] | null>(null);
  const [failed, setFailed] = useState(false);
  const load = () => { setFailed(false); api.duoDiscover().then(setList).catch(() => setFailed(true)); };
  useEffect(load, []);

  async function swipe(id: string, kind: 'like' | 'pass') {
    try {
      const r = await api.duoSwipe(id, kind);
      setList((cur) => (cur ?? []).filter((d) => d.duo_id !== id));
      if (r.match_id) {
        feedback('match');
        Alert.alert(t('duo.matched'), undefined, [{ text: 'OK', onPress: () => router.replace(`/duo/chat/${r.match_id}`) }]);
      } else if (kind === 'like') feedback('like');
    } catch {
      toast(t('common.error'), { error: true });
    }
  }

  if (failed && list === null) return <ErrorState onRetry={load} />;
  if (list === null) return <SkeletonList kind="card" rows={3} />;
  if (list.length === 0) return <Empty icon="duo" title={t('duo.none')} sub={t('duo.noneSub')} />;

  return (
    <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 }}>
      {list.map((d) => (
        <View key={d.duo_id} style={styles.card}>
          <View style={styles.photos}>
            {d.members.map((p) => (
              <View key={p.id} style={styles.half}>
                <Image source={{ uri: p.photos[0] }} style={StyleSheet.absoluteFill} contentFit="cover" />
                <View style={styles.nameTag}>
                  <Text maxFontSizeMultiplier={1.3} style={styles.name} numberOfLines={1}>{p.name}, {p.age}</Text>
                  <Text maxFontSizeMultiplier={1.3} style={styles.no}>{memberNo(p.member_no)}</Text>
                </View>
              </View>
            ))}
          </View>
          <View style={styles.body}>
            <T variant="footnote" style={{ fontFamily: fonts.text600 }}>{cityName(d.members[0].city)}</T>
            <View style={styles.sports}>
              {[...new Set(d.members.flatMap((p) => p.sports.map((s) => s.code)))].slice(0, 6).map((c) => (
                <Icon key={c} name={sportIconName(c)} size={iconSize.toolbar} color="blueText" />
              ))}
            </View>
            <Row>
              <Button title="" accessibilityLabel="pass" variant="secondary" onPress={() => swipe(d.duo_id, 'pass')} style={{ flex: 1 }}
                icon={<Icon name="close" size={iconSize.toolbar} color="clay" weight="bold" />} />
              <Button title="" accessibilityLabel="like" onPress={() => swipe(d.duo_id, 'like')} style={{ flex: 2 }}
                icon={<Mark size={30} color={lightPalette.gold} />} />
            </Row>
          </View>
        </View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, overflow: 'hidden' },
  photos: { flexDirection: 'row', height: 260, gap: 2 },
  half: { flex: 1, backgroundColor: colors.blue },
  nameTag: { position: 'absolute', left: sp.md, bottom: sp.md, right: sp.md },
  name: { ...type.headline, color: '#FFFFFF', textShadowColor: 'rgba(0,0,0,0.5)', textShadowRadius: 6 },
  no: { ...type.caption, color: '#FFFFFF', opacity: 0.9, fontVariant: ['tabular-nums'] },
  body: { padding: sp.lg, gap: sp.md },
  sports: { flexDirection: 'row', gap: sp.md },
});
