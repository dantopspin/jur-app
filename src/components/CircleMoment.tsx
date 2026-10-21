// Checking in to an event: "You've joined the circle". The shanyrak ring closes
// around the sport, with the knock-and-pluck sound and haptic.
import React, { useEffect } from 'react';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useI18n } from '../i18n';
import { feedback } from '../lib/feedback';
import { colors, fontScale, fonts, lightPalette, radius, space } from '../lib/theme';
import { Shanyrak } from './Brand';
import { Icon, sportIconName } from './Icon';
import { ShareCardWideButton } from './ShareCard';
import { Button } from './ui';

export function CircleMoment({
  visible, sportCode, onClose, share,
}: {
  visible: boolean; sportCode: string; onClose: () => void;
  /** "I joined the circle" story card */
  share?: { title: string; line: string; code: string; member?: number };
}) {
  const { t } = useI18n();
  useEffect(() => { if (visible) feedback('checkin'); }, [visible]);

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.scrim} onPress={onClose} accessibilityLabel={t('common.close')} />
      <View style={styles.center} pointerEvents="box-none">
        <View style={styles.card} accessibilityViewIsModal>
          <View style={styles.ring}>
            <Shanyrak size={180} color={lightPalette.gold} animate={visible} slats={0.25} style={StyleSheet.absoluteFill} />
            <View style={styles.core}>
              <Icon name={sportIconName(sportCode)} size={40} color="#FFFFFF" />
            </View>
          </View>
          <Text maxFontSizeMultiplier={fontScale.display} style={styles.title} accessibilityRole="header">{t('circle.joinedTitle')}</Text>
          <Text maxFontSizeMultiplier={fontScale.body} style={styles.sub}>{t('circle.joinedSub')}</Text>
          <Button title={t('common.done')} variant="accent" onPress={onClose} style={{ alignSelf: 'stretch', marginTop: space(1) }} />
          {share ? (
            <View style={{ alignSelf: 'stretch' }}>
              <ShareCardWideButton kind="joined" variant="ghost" {...share} />
            </View>
          ) : null}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  scrim: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.overlay },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: space(3) },
  card: {
    alignSelf: 'stretch', backgroundColor: lightPalette.blue, borderRadius: radius.lg, padding: space(3),
    alignItems: 'center', gap: space(1.25),
  },
  ring: { width: 180, height: 180, alignItems: 'center', justifyContent: 'center' },
  core: {
    width: 92, height: 92, borderRadius: 46, backgroundColor: lightPalette.blueDeep, alignItems: 'center',
    justifyContent: 'center',
  },
  title: { fontFamily: fonts.display, fontSize: 24, lineHeight: 30, color: '#FFFFFF', textAlign: 'center' },
  sub: { fontFamily: fonts.text500, fontSize: 15, lineHeight: 22, color: lightPalette.blueMist, textAlign: 'center' },
});
