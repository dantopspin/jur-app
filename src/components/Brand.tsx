// Brand primitives: the mark (two strides curling into a heart — in Kazakhstan
// also read as ram horns, қошқар мүйіз), the horizon line, and the Latin
// wordmark used in every market. Geometry matches the brand system's SVG assets.
import React, { useEffect, useRef } from 'react';
import { AccessibilityInfo, Animated, Easing, StyleSheet, Text, View, type StyleProp, type ViewStyle } from 'react-native';
import Svg, { Circle, G, Path, Polygon } from 'react-native-svg';
import { colors, darkPalette, fonts, lightPalette, motion, useTheme } from '../lib/theme';

const HORN_LEFT = 'M50 88 C30 70 14 56 14 38 C14 22 28 14 40 18 C50 22 50 36 40 38 C34 39 30 34 33 30';
const HORN_RIGHT = 'M50 88 C70 70 86 56 86 38 C86 22 72 14 60 18 C50 22 50 36 60 38 C66 39 70 34 67 30';
const HORN_LENGTH = 143; // measured stroke length of each horn in the 100-unit box

const AnimatedPath = Animated.createAnimatedComponent(Path);

/** Stroke weight by rendered size, per the logo rules (thicker when small). */
function strokeFor(size: number): number {
  if (size < 24) return 11;
  if (size < 48) return 9;
  return 7;
}

export function Mark({
  size = 48, color = lightPalette.gold, animate = false, delay = 0, style,
}: { size?: number; color?: string; animate?: boolean; delay?: number; style?: StyleProp<ViewStyle> }) {
  const progress = useRef(new Animated.Value(animate ? 0 : 1)).current;

  useEffect(() => {
    if (!animate) return;
    let cancelled = false;
    AccessibilityInfo.isReduceMotionEnabled().then((reduce) => {
      if (cancelled) return;
      if (reduce) {
        progress.setValue(1);
        return;
      }
      // "Horns curl": both strokes start at the heart's point and curl up into the horns.
      Animated.timing(progress, {
        toValue: 1,
        duration: motion.markDraw,
        delay,
        easing: Easing.bezier(0.2, 0, 0, 1),
        useNativeDriver: false,
      }).start();
    });
    return () => { cancelled = true; };
  }, [animate, delay, progress]);

  const offset = progress.interpolate({ inputRange: [0, 1], outputRange: [HORN_LENGTH, 0] });
  const sw = strokeFor(size);

  return (
    <View style={style} accessibilityRole="image" accessibilityLabel="Qadam">
      <Svg width={size} height={size} viewBox="0 0 100 100" fill="none">
        {[HORN_LEFT, HORN_RIGHT].map((d) => (
          <AnimatedPath
            key={d}
            d={d}
            stroke={color}
            strokeWidth={sw}
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeDasharray={animate ? [HORN_LENGTH, HORN_LENGTH] : undefined}
            strokeDashoffset={animate ? offset : undefined}
          />
        ))}
      </Svg>
    </View>
  );
}

/** The horizon: a mountain line for the bottom edge of blue surfaces. One per surface.
 *  Snow lines appear in winter only (pass snow={season === 'winter'}). */
export function Ridge({
  width, height = 90, fill, snow = true, style,
}: { width: number; height?: number; fill?: string; snow?: boolean; style?: StyleProp<ViewStyle> }) {
  const { raw } = useTheme();
  return (
    <Svg width={width} height={height} viewBox="0 0 390 90" preserveAspectRatio="none" style={style} pointerEvents="none">
      <Polygon points="0,90 0,62 60,48 110,58 170,28 220,46 280,20 330,42 390,32 390,90" fill={fill ?? raw.blueDeep} />
      {snow ? (
        <Path d="M170 28 L182 37 L194 33 L204 40 M280 20 L292 30 L304 26 L314 34" stroke="#F7F4EE" strokeWidth={2.5}
          strokeLinejoin="round" fill="none" />
      ) : null}
    </Svg>
  );
}

/** Mark + wordmark lockup. The wordmark is Latin "Qadam" in every market and language. */
export function Lockup({
  size = 28, tone = 'light',
}: { size?: number; tone?: 'light' | 'dark' }) {
  const { raw } = useTheme();
  const markColor = tone === 'dark' ? raw.gold : raw.blueText;
  return (
    <View style={styles.lockup} accessibilityRole="header" accessibilityLabel="Qadam">
      <Mark size={size * 1.4} color={markColor} />
      <Text maxFontSizeMultiplier={1.2} style={[styles.word, { fontSize: size, lineHeight: size * 1.2, color: tone === 'dark' ? colors.white : colors.ink }]}>
        Qadam
      </Text>
    </View>
  );
}

/** Loading: the horns curl in and out, a living piece of ornament instead of a spinner. */
export function MarkLoader({ size = 44, color }: { size?: number; color?: string }) {
  const { raw } = useTheme();
  const p = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    let loop: ReturnType<typeof Animated.loop> | null = null;
    AccessibilityInfo.isReduceMotionEnabled().then((reduce) => {
      if (reduce) { p.setValue(1); return; }
      loop = Animated.loop(Animated.sequence([
        Animated.timing(p, { toValue: 1, duration: motion.markDraw, easing: Easing.bezier(0.2, 0, 0, 1), useNativeDriver: false }),
        Animated.delay(180),
        Animated.timing(p, { toValue: 0, duration: motion.markDraw, easing: Easing.bezier(0.2, 0, 0, 1), useNativeDriver: false }),
        Animated.delay(120),
      ]));
      loop.start();
    });
    return () => loop?.stop();
  }, [p]);
  const offset = p.interpolate({ inputRange: [0, 1], outputRange: [HORN_LENGTH, 0] });
  return (
    <Svg width={size} height={size} viewBox="0 0 100 100" fill="none">
      {[HORN_LEFT, HORN_RIGHT].map((d) => (
        <AnimatedPath key={d} d={d} stroke={color ?? raw.blueText} strokeWidth={strokeFor(size)} strokeLinecap="round"
          strokeLinejoin="round" strokeDasharray={[HORN_LENGTH, HORN_LENGTH]} strokeDashoffset={offset} />
      ))}
    </Svg>
  );
}

/** Onboarding progress as a short ornament band: each finished step curls into place. */
export function OrnamentProgress({ total, current }: { total: number; current: number }) {
  const { raw } = useTheme();
  return (
    <View style={styles.band} accessibilityRole="progressbar" accessibilityValue={{ min: 0, max: total, now: current + 1 }}>
      {Array.from({ length: total }).map((_, i) => {
        const on = i <= current;
        return (
          <React.Fragment key={i}>
            {i > 0 ? <View style={[styles.bandLine, { backgroundColor: i <= current ? raw.blueText : raw.line }]} /> : null}
            <Mark key={`${i}-${on}`} size={18} color={on ? raw.blueText : raw.line} animate={i === current} />
          </React.Fragment>
        );
      })}
    </View>
  );
}

const SHANYRAK_R = 44;
const SHANYRAK_LEN = 2 * Math.PI * SHANYRAK_R;
const AnimatedCircle = Animated.createAnimatedComponent(Circle);
const AnimatedG = Animated.createAnimatedComponent(G);

function bars(): string[] {
  // Two sets of three bowed slats crossing inside the ring (the kuldireush).
  const out: string[] = [];
  for (const o of [-13, 0, 13]) {
    const half = Math.sqrt(38 * 38 - o * o);
    out.push(`M${50 - half} ${50 + o} Q50 ${50 + o - 7} ${50 + half} ${50 + o}`);
    out.push(`M${50 + o} ${50 - half} Q${50 + o + 7} 50 ${50 + o} ${50 + half}`);
  }
  return out;
}
const BARS = bars();
const SPOKES = Array.from({ length: 24 }, (_, i) => {
  const a = (i / 24) * Math.PI * 2;
  const x1 = 50 + Math.cos(a) * 46.5, y1 = 50 + Math.sin(a) * 46.5;
  const x2 = 50 + Math.cos(a) * 50, y2 = 50 + Math.sin(a) * 50;
  return `M${x1.toFixed(2)} ${y1.toFixed(2)} L${x2.toFixed(2)} ${y2.toFixed(2)}`;
}).join(' ');

/**
 * Shanyrak — the crown of the yurt, the circle of home and of people gathered.
 * Used for the match moment, checking in to an event ("you joined the circle")
 * and the Regular badge. The ring draws itself, then the slats and roof poles appear.
 */
export function Shanyrak({
  size = 280, color, animate = false, delay = 0, slats = 0.35, style,
}: { size?: number; color?: string; animate?: boolean; delay?: number; slats?: number; style?: StyleProp<ViewStyle> }) {
  const tint = color ?? lightPalette.gold;
  const p = useRef(new Animated.Value(animate ? 0 : 1)).current;
  useEffect(() => {
    if (!animate) return;
    let cancelled = false;
    AccessibilityInfo.isReduceMotionEnabled().then((reduce) => {
      if (cancelled) return;
      if (reduce) { p.setValue(1); return; }
      Animated.timing(p, { toValue: 1, duration: 900, delay, easing: Easing.bezier(0.2, 0, 0, 1), useNativeDriver: false }).start();
    });
    return () => { cancelled = true; };
  }, [animate, delay, p]);
  const ring = p.interpolate({ inputRange: [0, 0.7, 1], outputRange: [SHANYRAK_LEN, 0, 0] });
  const inner = p.interpolate({ inputRange: [0, 0.6, 1], outputRange: [0, 0, 1] });
  const sw = size < 60 ? 6 : size < 140 ? 3.5 : 2.2;
  return (
    <View style={style} pointerEvents="none">
      <Svg width={size} height={size} viewBox="0 0 100 100" fill="none">
        <AnimatedCircle cx={50} cy={50} r={SHANYRAK_R} stroke={tint} strokeWidth={sw} rotation={-90} origin="50, 50"
          strokeDasharray={[SHANYRAK_LEN, SHANYRAK_LEN]} strokeDashoffset={ring} strokeLinecap="round" />
        <AnimatedG opacity={inner}>
          <Circle cx={50} cy={50} r={38.5} stroke={tint} strokeWidth={sw * 0.6} opacity={0.8} />
          <Path d={SPOKES} stroke={tint} strokeWidth={sw * 0.8} strokeLinecap="round" />
          <G opacity={slats}>
            {BARS.map((d) => <Path key={d} d={d} stroke={tint} strokeWidth={sw * 0.8} strokeLinecap="round" />)}
          </G>
        </AnimatedG>
      </Svg>
    </View>
  );
}

/** Re-exported so screens can pick plain colours for SVG without importing both palettes. */
export const brandPalettes = { light: lightPalette, dark: darkPalette };

const styles = StyleSheet.create({
  lockup: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  word: { fontFamily: fonts.display, letterSpacing: -0.5 },
  band: { flex: 1, flexDirection: 'row', alignItems: 'center' },
  bandLine: { flex: 1, height: 2, borderRadius: 1, marginHorizontal: 2 },
});
