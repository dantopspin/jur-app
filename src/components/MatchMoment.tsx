// The match screen — the app's signature moment.
// Blue ground and horizon. The gold mark curls in, a shanyrak ring (the crown of
// the yurt: home, people gathered) draws itself around the two photos as they
// meet, then the headline. Two plucked strings and two haptic plucks, in time.
import { Image } from 'expo-image';
import React, { useEffect, useRef } from 'react';
import { AccessibilityInfo, Animated, Modal, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useI18n } from '../i18n';
import { feedback } from '../lib/feedback';
import { snowOnHorizon } from '../lib/season';
import { colors, fontScale, fonts, lightPalette, motion, space } from '../lib/theme';
import { Mark, Ridge, Shanyrak } from './Brand';
import { Button } from './ui';

const RING = 260;
const PHOTO = 104;

export function MatchMoment({
  visible, myPhoto, theirPhoto, name, onWrite, onClose, buddy,
}: {
  visible: boolean;
  /** a training-partner match (no hearts, different words) */
  buddy?: boolean;
  myPhoto?: string;
  theirPhoto?: string;
  name: string;
  onWrite: () => void;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const { width } = useWindowDimensions();
  const slide = useRef(new Animated.Value(0)).current;
  const fade = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (!visible) return;
    feedback('match');
    slide.setValue(0);
    fade.setValue(0);
    AccessibilityInfo.isReduceMotionEnabled().then((reduce) => {
      if (reduce) {
        slide.setValue(1);
        Animated.timing(fade, { toValue: 1, duration: 150, useNativeDriver: true }).start();
        return;
      }
      Animated.sequence([
        Animated.delay(motion.markDraw - 150),
        Animated.spring(slide, { toValue: 1, damping: 18, stiffness: 180, useNativeDriver: true }),
        Animated.timing(fade, { toValue: 1, duration: motion.base, useNativeDriver: true }),
      ]).start();
    });
  }, [visible, slide, fade]);

  const left = slide.interpolate({ inputRange: [0, 1], outputRange: [-width / 2, 0] });
  const right = slide.interpolate({ inputRange: [0, 1], outputRange: [width / 2, 0] });

  return (
    <Modal visible={visible} animationType="fade" onRequestClose={onClose} statusBarTranslucent>
      <View style={styles.bg} accessibilityViewIsModal>
        <Ridge width={width} height={140} snow={snowOnHorizon()} style={styles.ridge} />
        <SafeAreaView style={styles.wrap}>
          <Mark size={84} color={lightPalette.gold} animate={visible} />
          <View style={styles.circle}>
            <Shanyrak size={RING} color={lightPalette.gold} animate={visible} delay={250} style={StyleSheet.absoluteFill} />
            <View style={styles.photos}>
              <Animated.View style={[styles.photo, { transform: [{ translateX: left }] }]}>
                {myPhoto ? <Image source={{ uri: myPhoto }} style={StyleSheet.absoluteFill} contentFit="cover" /> : null}
              </Animated.View>
              <Animated.View style={[styles.photo, { marginLeft: -18, transform: [{ translateX: right }] }]}>
                {theirPhoto ? <Image source={{ uri: theirPhoto }} style={StyleSheet.absoluteFill} contentFit="cover" /> : null}
              </Animated.View>
            </View>
          </View>
          <Animated.View style={{ opacity: fade, alignItems: 'center', gap: space(1), alignSelf: 'stretch' }}>
            <Text maxFontSizeMultiplier={fontScale.display} style={styles.title} accessibilityRole="header">{buddy ? t('mode.matchTitle') : t('match.title')}</Text>
            <Text maxFontSizeMultiplier={fontScale.body} style={styles.sub}>{buddy ? t('mode.matchSub', { name }) : t('match.sub', { name })}</Text>
            <Button title={t('match.write')} variant="accent" onPress={onWrite} style={{ alignSelf: 'stretch', marginTop: space(2) }} />
            <Button title={t('match.keep')} variant="ghost" onPress={onClose} style={{ alignSelf: 'stretch' }} textColor={colors.white} />
          </Animated.View>
        </SafeAreaView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  bg: { flex: 1, backgroundColor: lightPalette.blue },
  ridge: { position: 'absolute', left: 0, bottom: 0 },
  wrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: space(3.5), gap: space(1.5) },
  circle: { width: RING, height: RING, alignItems: 'center', justifyContent: 'center' },
  photos: { flexDirection: 'row' },
  photo: {
    width: PHOTO, height: PHOTO, borderRadius: PHOTO / 2, borderWidth: 3, borderColor: lightPalette.gold,
    backgroundColor: lightPalette.blueDeep, overflow: 'hidden',
  },
  title: { fontFamily: fonts.display, fontSize: 30, lineHeight: 38, color: '#FFFFFF', textAlign: 'center' },
  sub: { fontFamily: fonts.text500, fontSize: 17, lineHeight: 25, color: lightPalette.blueMist, textAlign: 'center' },
});
