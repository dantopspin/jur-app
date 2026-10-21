// The shared building blocks. Every screen is made of these, so spacing, radii,
// type and states stay consistent. Tokens live in src/lib/theme.ts.
import React, { useEffect, useRef, type ReactElement } from 'react';
import {
  AccessibilityInfo, ActivityIndicator, Animated, Pressable, ScrollView, StyleSheet, Switch, Text, TextInput, View,
  type ColorValue, type StyleProp, type TextInputProps, type TextProps, type TextStyle, type ViewStyle,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets, type Edge } from 'react-native-safe-area-context';
import { useI18n } from '../i18n';
import { tick } from '../lib/haptics';
import {
  border, colors, curve, fonts, iconSize, layout, radius, sp, type, typeScale, useTheme,
  type ColorKey, type TypeVariant,
} from '../lib/theme';
import { Mark, MarkLoader } from './Brand';
import { Icon, type IconName } from './Icon';

// ─── Text ────────────────────────────────────────────────────────────────────

type Tone = 'ink' | 'inkSoft' | 'muted' | 'blueText' | 'clayDeep' | 'danger' | 'white' | 'onGold' | 'good';

/** Text in one of the type-scale variants, with its Dynamic Type ceiling. */
export function T({
  variant = 'body', tone, style, children, header, ...rest
}: TextProps & { variant?: TypeVariant; tone?: Tone; header?: boolean; children: React.ReactNode }) {
  const defaultTone: Tone = variant === 'footnote' || variant === 'caption' ? 'muted'
    : variant === 'overline' ? 'inkSoft' : variant === 'callout' ? 'inkSoft' : 'ink';
  return (
    <Text
      maxFontSizeMultiplier={typeScale[variant]}
      accessibilityRole={header ? 'header' : rest.accessibilityRole}
      style={[type[variant], { color: colors[tone ?? defaultTone] }, style]}
      {...rest}
    >
      {children}
    </Text>
  );
}

export function Screen({
  children, style, edges = ['top'],
}: { children: React.ReactNode; style?: StyleProp<ViewStyle>; edges?: Edge[] }) {
  return (
    <SafeAreaView edges={edges} style={[styles.screen, style]}>
      {children}
    </SafeAreaView>
  );
}

export function H1({ children, style }: { children: React.ReactNode; style?: StyleProp<TextStyle> }) {
  return <T variant="title1" header style={style}>{children}</T>;
}

export function H2({ children, style }: { children: React.ReactNode; style?: StyleProp<TextStyle> }) {
  return <T variant="title2" header style={style}>{children}</T>;
}

export function P({
  children, style, muted, numberOfLines,
}: { children: React.ReactNode; style?: StyleProp<TextStyle>; muted?: boolean; numberOfLines?: number }) {
  return <T variant="body" tone={muted ? 'muted' : 'inkSoft'} numberOfLines={numberOfLines} style={style}>{children}</T>;
}

/** The one section-label style (uppercase overline), with the standard 8 pt gap below. */
export function SectionLabel({ children, style }: { children: React.ReactNode; style?: StyleProp<TextStyle> }) {
  return <T variant="overline" header style={[{ marginBottom: sp.sm }, style]}>{children}</T>;
}

// ─── Buttons ─────────────────────────────────────────────────────────────────

type Variant = 'primary' | 'accent' | 'secondary' | 'ghost' | 'danger';

const variants: Record<Variant, { bg: ColorValue; fg: ColorValue }> = {
  primary: { bg: colors.blue, fg: colors.white },
  accent: { bg: colors.gold, fg: colors.onGold },
  secondary: { bg: colors.blueTint, fg: colors.blueText },
  ghost: { bg: 'transparent', fg: colors.blueText },
  danger: { bg: colors.dangerTint, fg: colors.danger },
};

export function Button({
  title, onPress, variant = 'primary', loading, disabled, style, icon, textColor, accessibilityLabel, compact,
}: {
  title: string;
  onPress: () => void;
  variant?: Variant;
  loading?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  /** an element (usually an <Icon>) shown before the label */
  icon?: string | React.ReactNode;
  /** override the label colour, e.g. a ghost button on blue */
  textColor?: ColorValue;
  /** for icon-only buttons */
  accessibilityLabel?: string;
  /** 44 pt instead of 50 pt */
  compact?: boolean;
}) {
  const v = variants[variant];
  const off = disabled || loading;
  const fg = textColor ?? v.fg;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
      accessibilityState={{ disabled: !!off, busy: !!loading }}
      onPress={off ? undefined : onPress}
      style={({ pressed }) => [
        styles.btn, { backgroundColor: v.bg, minHeight: compact ? layout.buttonHeightCompact : layout.buttonHeight },
        compact && { paddingHorizontal: sp.lg },
        disabled && !loading && { opacity: 0.4 },
        pressed && !off && { opacity: 0.75, transform: [{ scale: 0.98 }] }, style,
      ]}
    >
      <View style={[styles.btnRow, loading && { opacity: 0.6 }]}>
        {loading ? <ActivityIndicator size="small" color={fg as string} /> : icon && typeof icon !== 'string' ? icon : null}
        {title || typeof icon === 'string' ? (
          <Text maxFontSizeMultiplier={1.35} style={[styles.btnText, compact && { fontSize: 15 }, { color: fg }]}>
            {typeof icon === 'string' ? `${icon}  ` : ''}{title}
          </Text>
        ) : null}
      </View>
    </Pressable>
  );
}

/** The close button of a full-screen modal (paywall, offer): placed from the safe area. */
export function CloseButton({ onPress, label, onDark }: { onPress: () => void; label: string; onDark?: boolean }) {
  const insets = useSafeAreaInsets();
  return (
    <Pressable onPress={onPress} hitSlop={7} accessibilityRole="button" accessibilityLabel={label}
      style={({ pressed }) => [styles.close, { top: insets.top + sp.sm, backgroundColor: onDark ? 'rgba(255,255,255,0.16)' : colors.line },
        pressed && { opacity: 0.6 }]}>
      <Icon name="close" size={15} color={onDark ? '#FFFFFF' : 'inkSoft'} weight="bold" />
    </Pressable>
  );
}

// ─── Chips and tags ──────────────────────────────────────────────────────────

/** Interactive, selectable. 36 pt high, 44 pt touch target. */
export function Chip({
  label, selected, onPress, sub, style, onCard,
}: {
  label: string; selected?: boolean; onPress?: () => void; sub?: string; style?: StyleProp<ViewStyle>;
  /** sitting on a white card rather than the page ground */
  onCard?: boolean;
}) {
  return (
    <Pressable
      onPress={onPress ? () => { tick(); onPress(); } : undefined}
      disabled={!onPress}
      hitSlop={4}
      style={({ pressed }) => [
        styles.chip, { backgroundColor: onCard ? colors.bg : colors.card },
        selected && styles.chipOn, pressed && { opacity: 0.75 }, style,
      ]}
      accessibilityRole="button"
      accessibilityState={{ selected }}
    >
      <Text maxFontSizeMultiplier={1.35} style={[styles.chipText, selected && { color: colors.white }]}>{label}</Text>
      {sub ? <Text maxFontSizeMultiplier={1.35} style={[styles.chipSub, selected && { color: colors.blueMist }]}>{sub}</Text> : null}
    </Pressable>
  );
}

type TagTone = 'blue' | 'neutral' | 'gold' | 'solid' | 'clay' | 'good' | 'onPhoto';
const tagTones: Record<TagTone, { bg: ColorValue; fg: ColorKey | '#FFFFFF' }> = {
  blue: { bg: colors.blueTint, fg: 'blueText' },
  neutral: { bg: colors.bg, fg: 'inkSoft' },
  gold: { bg: colors.gold, fg: 'onGold' },
  solid: { bg: colors.blue, fg: '#FFFFFF' },
  clay: { bg: colors.dangerTint, fg: 'clay' },
  good: { bg: colors.goodTint, fg: 'good' },
  onPhoto: { bg: 'rgba(18,58,100,0.72)', fg: '#FFFFFF' },
};

/** Read-only label: "Training partner", "Liked", "Verified", sport names on cards. */
export function Tag({
  label, tone = 'blue', icon, style,
}: { label: string; tone?: TagTone; icon?: IconName; style?: StyleProp<ViewStyle> }) {
  const { raw } = useTheme();
  const t = tagTones[tone];
  const fg = t.fg === '#FFFFFF' ? '#FFFFFF' : raw[t.fg];
  return (
    <View style={[styles.tag, { backgroundColor: t.bg }, style]}>
      {icon ? <Icon name={icon} size={iconSize.inline} color={fg} /> : null}
      <Text maxFontSizeMultiplier={1.3} style={[type.caption, { color: fg }]} numberOfLines={1}>{label}</Text>
    </View>
  );
}

// ─── Inputs ──────────────────────────────────────────────────────────────────

export const Field = React.forwardRef<TextInput, TextInputProps & { label?: string; onCard?: boolean }>(
  function Field({ label, style, onCard, ...props }, ref) {
    return (
      <View style={{ gap: sp.sm }}>
        {label ? <T variant="overline">{label}</T> : null}
        <TextInput
          ref={ref}
          placeholderTextColor={colors.hint}
          maxFontSizeMultiplier={2}
          style={[
            styles.field, { backgroundColor: onCard ? colors.bg : colors.card },
            props.multiline && { minHeight: 96, textAlignVertical: 'top', paddingTop: 14 }, style,
          ]}
          {...props}
        />
      </View>
    );
  },
);

// ─── Layout ──────────────────────────────────────────────────────────────────

export function Row({
  children, style, gap = sp.sm,
}: { children: React.ReactNode; style?: StyleProp<ViewStyle>; gap?: number }) {
  return <View style={[{ flexDirection: 'row', alignItems: 'center', gap }, style]}>{children}</View>;
}

export function Card({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[styles.card, style]}>{children}</View>;
}

// ─── Grouped lists (iOS inset grouped) ───────────────────────────────────────

type ListItemProps = {
  title: string;
  subtitle?: string;
  /** trailing value text ("On", "Almaty", "✓") */
  right?: string;
  onPress?: () => void;
  danger?: boolean;
  icon?: IconName;
  /** colour of the icon tile (defaults to blue) */
  tint?: ColorKey;
  /** a trailing switch instead of a chevron */
  toggle?: { value: boolean; onChange: (v: boolean) => void; disabled?: boolean };
  /** a centred action row (Sign out, Delete account) */
  center?: boolean;
  /** shows a spinner instead of the chevron */
  busy?: boolean;
};

export function ListItem({ title, subtitle, right, onPress, danger, icon, tint = 'blue', toggle, center, busy }: ListItemProps) {
  const { raw } = useTheme();
  const tappable = !!onPress && !toggle;
  return (
    <Pressable onPress={tappable ? onPress : undefined} disabled={!tappable}
      accessibilityRole={toggle ? 'switch' : tappable ? 'button' : undefined}
      accessibilityState={toggle ? { checked: toggle.value } : undefined}
      style={({ pressed }) => [styles.item, { minHeight: subtitle ? layout.rowMinSub : layout.rowMin }, pressed && { backgroundColor: colors.line }]}>
      {icon ? (
        <View style={[styles.itemIcon, { backgroundColor: colors[tint] }]}>
          <Icon name={icon} size={iconSize.row} color="white" />
        </View>
      ) : null}
      <View style={{ flex: 1, gap: sp.xxs }}>
        <T variant="body" tone={danger ? 'danger' : center ? 'blueText' : 'ink'}
          style={[{ fontFamily: fonts.text600 }, center && { textAlign: 'center' }]}>{title}</T>
        {subtitle ? <T variant="footnote">{subtitle}</T> : null}
      </View>
      {toggle ? (
        <Switch value={toggle.value} onValueChange={(v) => { tick(); toggle.onChange(v); }} disabled={toggle.disabled}
          trackColor={{ true: raw.blue, false: raw.line }} ios_backgroundColor={raw.line} />
      ) : busy ? (
        <ActivityIndicator size="small" />
      ) : right ? (
        <View style={styles.itemRightRow}>
          <T variant="body" tone="muted" numberOfLines={1}>{right}</T>
          {tappable ? <Icon name="forward" size={iconSize.inline} color="hint" weight="semibold" /> : null}
        </View>
      ) : tappable && !center ? (
        <Icon name="forward" size={iconSize.inline} color="hint" weight="semibold" />
      ) : null}
    </Pressable>
  );
}

/** A group of ListItems on one rounded card, with inset hairlines, an optional header and footer. */
export function ListSection({
  header, footer, children, style,
}: { header?: string; footer?: string; children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  const items = React.Children.toArray(children).filter(Boolean) as ReactElement<ListItemProps>[];
  const inset = items.some((c) => c.props?.icon) ? layout.rowInset : layout.margin;
  return (
    <View style={style}>
      {header ? <SectionLabel style={{ paddingHorizontal: layout.margin }}>{header}</SectionLabel> : null}
      <View style={styles.group}>
        {items.map((c, i) => (
          <React.Fragment key={c.key ?? i}>
            {i > 0 ? <View style={[styles.sep, { marginLeft: inset }]} /> : null}
            {c}
          </React.Fragment>
        ))}
      </View>
      {footer ? <T variant="footnote" style={styles.footer}>{footer}</T> : null}
    </View>
  );
}

// ─── States ──────────────────────────────────────────────────────────────────

/**
 * Nothing here yet (SwiftUI's ContentUnavailableView): a symbol, a title, one line
 * on why, and at most one next step. Without an icon it shows the static mark.
 */
export function Empty({
  title, sub, action, onAction, icon,
}: { title: string; sub?: string; action?: string; onAction?: () => void; icon?: IconName }) {
  const { raw } = useTheme();
  return (
    <View style={styles.empty}>
      {icon ? <Icon name={icon} size={iconSize.hero} color="muted" weight="regular" /> : <Mark size={56} color={raw.blueText} />}
      <T variant="title3" header style={{ textAlign: 'center', marginTop: sp.sm }}>{title}</T>
      {sub ? <T variant="callout" style={{ textAlign: 'center' }}>{sub}</T> : null}
      {action && onAction ? <Button title={action} compact onPress={onAction} style={{ marginTop: sp.md }} /> : null}
    </View>
  );
}

/** Couldn't load: says so, with Retry. Use instead of an empty state when the request failed. */
export function ErrorState({ onRetry, title, sub }: { onRetry?: () => void; title?: string; sub?: string }) {
  const { t } = useI18n();
  return (
    <Empty icon="offline" title={title ?? t('states.errorTitle')} sub={sub ?? t('states.errorSub')}
      action={onRetry ? t('common.retry') : undefined} onAction={onRetry} />
  );
}

/** Full-screen loading: cold start and full-screen moments only. Lists use SkeletonList. */
export function Loading() {
  return (
    <View style={styles.empty} accessibilityLabel="Loading" accessibilityRole="progressbar">
      <MarkLoader size={44} />
    </View>
  );
}

function usePulse() {
  const v = useRef(new Animated.Value(0.55)).current;
  useEffect(() => {
    let anim: ReturnType<typeof Animated.loop> | null = null;
    AccessibilityInfo.isReduceMotionEnabled().then((reduce) => {
      if (reduce) return;
      anim = Animated.loop(Animated.sequence([
        Animated.timing(v, { toValue: 1, duration: 700, useNativeDriver: true }),
        Animated.timing(v, { toValue: 0.55, duration: 700, useNativeDriver: true }),
      ]));
      anim.start();
    });
    return () => anim?.stop();
  }, [v]);
  return v;
}

/** Placeholder rows in a list's real shape while it loads. */
export function SkeletonList({ rows = 6, kind = 'row' }: { rows?: number; kind?: 'row' | 'card' }) {
  const opacity = usePulse();
  // In a ScrollView so it sits below a transparent large-title header, like the list it stands in for.
  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" scrollEnabled={false} style={{ backgroundColor: colors.bg }}>
    <Animated.View style={{ opacity, padding: layout.margin, gap: kind === 'card' ? sp.md : sp.lg }}
      accessibilityLabel="Loading" accessibilityRole="progressbar">
      {Array.from({ length: rows }, (_, i) => kind === 'card' ? (
        <View key={i} style={[styles.skelCard]}>
          <View style={[styles.skelBox, { width: 56, height: 56, borderRadius: radius.md }]} />
          <View style={{ flex: 1, gap: sp.sm }}>
            <View style={[styles.skelBox, { width: '40%', height: 12 }]} />
            <View style={[styles.skelBox, { width: '80%', height: 16 }]} />
            <View style={[styles.skelBox, { width: '55%', height: 12 }]} />
          </View>
        </View>
      ) : (
        <View key={i} style={styles.skelRow}>
          <View style={[styles.skelBox, { width: 56, height: 56, borderRadius: 28 }]} />
          <View style={{ flex: 1, gap: sp.sm }}>
            <View style={[styles.skelBox, { width: '45%', height: 14 }]} />
            <View style={[styles.skelBox, { width: '75%', height: 12 }]} />
          </View>
        </View>
      ))}
    </Animated.View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  btn: {
    borderRadius: radius.pill, alignItems: 'center', justifyContent: 'center', paddingHorizontal: sp.xl,
  },
  close: {
    position: 'absolute', right: layout.margin, zIndex: 2, width: 30, height: 30, borderRadius: 15,
    alignItems: 'center', justifyContent: 'center',
  },
  btnRow: { flexDirection: 'row', alignItems: 'center', gap: sp.sm },
  btnText: { fontSize: 17, fontFamily: fonts.text700 },
  chip: {
    minHeight: 36, paddingHorizontal: 14, paddingVertical: 7, borderRadius: radius.pill,
    alignItems: 'center', justifyContent: 'center',
  },
  chipOn: { backgroundColor: colors.blue },
  chipText: { ...type.callout, color: colors.ink },
  chipSub: { ...type.caption, fontFamily: fonts.text500, color: colors.muted },
  tag: {
    flexDirection: 'row', alignItems: 'center', gap: sp.xs, paddingHorizontal: sp.sm, paddingVertical: sp.xs,
    borderRadius: radius.pill, alignSelf: 'flex-start',
  },
  field: {
    borderRadius: radius.md, ...curve, minHeight: 50, paddingHorizontal: sp.lg, paddingVertical: sp.md,
    ...type.body, lineHeight: undefined, color: colors.ink,
  },
  card: { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, padding: sp.lg },
  group: { backgroundColor: colors.card, borderRadius: radius.lg, ...curve, overflow: 'hidden' },
  sep: { height: border.hair, backgroundColor: colors.line },
  footer: { paddingHorizontal: layout.margin, marginTop: sp.sm },
  item: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, paddingHorizontal: layout.margin, gap: sp.md },
  itemRightRow: { flexDirection: 'row', alignItems: 'center', gap: sp.xs, maxWidth: '50%' },
  itemIcon: {
    width: layout.tile, height: layout.tile, borderRadius: 7, ...curve, alignItems: 'center', justifyContent: 'center',
  },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: sp.xxl, gap: sp.sm },
  skelRow: { flexDirection: 'row', alignItems: 'center', gap: sp.md },
  skelCard: { flexDirection: 'row', gap: sp.md, backgroundColor: colors.card, borderRadius: radius.lg, padding: sp.lg },
  skelBox: { backgroundColor: colors.line, borderRadius: 6 },
});
