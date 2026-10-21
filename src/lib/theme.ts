// Qadam core palette, light and dark. Values mirror the "Qadam" brand system tokens
// (token name in the comment). Change colours there first, then here.
//
// How dark mode works:
// - iOS: every themed colour is a DynamicColorIOS, so static StyleSheets switch
//   instantly when the phone switches appearance — no re-render needed.
// - Android: the scheme is read once at launch (the app follows the system the
//   next time it starts).
// - Where a plain string is required (SVG fills, SF Symbol tints, navigation
//   options), use useTheme().raw, which re-renders on appearance changes.
import { Appearance, DynamicColorIOS, Platform, StyleSheet, useColorScheme, type ColorValue, type TextStyle } from 'react-native';

export const lightPalette = {
  // grounds
  bg: '#F7F4EE',          // chalk-100 — page background (warm white)
  card: '#FFFFFF',        // white — cards, sheets, inputs
  line: '#E4DDD0',        // chalk-300 — borders, dividers
  // text
  ink: '#1B2430',         // ink-900
  inkSoft: '#474C55',     // ink-600 — secondary text
  muted: '#5B606A',       // ink-500 — labels, captions
  hint: '#676C75',        // ink-400 — placeholders, faintest readable text
  // brand
  blue: '#1F5FA0',        // blue-600 — fills: buttons, like, welcome, match (white text 6.6:1)
  blueText: '#1F5FA0',    // blue as text or icon on the page ground
  blueDeep: '#184C82',    // blue-700 — horizon, pressed
  blueNight: '#123A64',   // blue-800 — deepest horizon layer
  blueMist: '#DCE7F3',    // blue-100 — secondary text on blue
  blueTint: '#E6EEF7',    // blue-50 — info banners, quotes, selected rows
  gold: '#E2A63B',        // gold-500 — fills under dark text, the mark on blue. Never text on light grounds.
  onGold: '#1B2430',      // text and icons on gold, in both modes
  clay: '#A8452A',        // clay-600 — pass, warm accent, text ≥16px
  clayDeep: '#8A3A22',    // clay-700 — small uppercase labels
  // states
  good: '#256B42',
  danger: '#B3261E',
  dangerTint: '#FBEAE8',
  goodTint: '#E5F2EA',
  white: '#FFFFFF',
  overlay: 'rgba(18,58,100,0.55)',
  // aliases kept so older code reads clearly
  accent: '#E2A63B',
  accentText: '#8A3A22',
};

type Key = keyof typeof lightPalette;
export type Palette = Record<Key, string>;

/** Night: deep blue-black ground, gold stays gold, blue text lifts to stay readable. */
export const darkPalette: Palette = {
  bg: '#0E1724',
  card: '#172333',
  line: '#2A3A4F',
  ink: '#F3EFE7',
  inkSoft: '#C8CDD5',
  muted: '#A3AAB5',
  hint: '#8E96A2',
  blue: '#1F5FA0',
  blueText: '#8DB9EC',
  blueDeep: '#123A64',
  blueNight: '#0B2440',
  blueMist: '#DCE7F3',
  blueTint: '#1A3150',
  gold: '#E2A63B',
  onGold: '#1B2430',
  clay: '#E58A6B',
  clayDeep: '#EE9C80',
  good: '#5CC28A',
  danger: '#FF7A6E',
  dangerTint: '#3A1F22',
  goodTint: '#163325',
  white: '#FFFFFF',
  overlay: 'rgba(0,0,0,0.6)',
  accent: '#E2A63B',
  accentText: '#EE9C80',
};

/** Felt — a physical material, the same in light and dark (card backs, Pro, the patch). */
export const felt = { ground: '#EFE6D6', ink: '#1B2430', line: '#D9CBB2', label: '#8A3A22' };

const launchScheme = Appearance.getColorScheme() === 'dark' ? 'dark' : 'light';

function build(): Record<Key, ColorValue> {
  const out = {} as Record<Key, ColorValue>;
  for (const k of Object.keys(lightPalette) as Key[]) {
    const l = lightPalette[k];
    const d = darkPalette[k];
    if (Platform.OS === 'ios') out[k] = l === d ? l : DynamicColorIOS({ light: l, dark: d });
    else out[k] = launchScheme === 'dark' ? d : l;
  }
  return out;
}

/** Use in StyleSheets and style props. */
export const colors = build();
export type ColorKey = Key;

/** Plain-string colours for the current appearance (SVG, icons, navigation options). */
export function useTheme(): { dark: boolean; raw: Palette } {
  const scheme = useColorScheme();
  const dark = Platform.OS === 'ios' ? scheme === 'dark' : launchScheme === 'dark';
  return { dark, raw: dark ? darkPalette : lightPalette };
}

export const fonts = {
  // Unbounded: headlines, names, numbers — never paragraphs or buttons
  display: 'Unbounded_800ExtraBold',
  displayMedium: 'Unbounded_700Bold',
  // Manrope: everything people read or tap (one family per weight, Android needs it)
  text400: 'Manrope_400Regular',
  text500: 'Manrope_500Medium',
  text600: 'Manrope_600SemiBold',
  text700: 'Manrope_700Bold',
  text800: 'Manrope_800ExtraBold',
};

/**
 * Dynamic Type: text follows the phone's text size. Caps keep layouts intact:
 * body text may grow a lot, headlines and controls a little.
 */
export const fontScale = { display: 1.25, control: 1.35, body: 1.8 };

export const space = (n: number) => n * 8;

/**
 * Spacing on a 4 pt grid. Screen margin and card padding are `lg` (16) everywhere.
 * Raw numbers in screen styles are a bug: pick the nearest step.
 */
export const sp = { xxs: 2, xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32 } as const;

/** Layout constants shared across screens. */
export const layout = {
  margin: 16,          // screen side margin
  rowMin: 44,          // minimum list row / touch target
  rowMinSub: 52,       // list row with a subtitle
  tile: 29,            // settings-style icon tile
  rowInset: 16 + 29 + 12, // separator inset after a tile
  buttonHeight: 50,
  buttonHeightCompact: 44,
} as const;

/**
 * Corner radii. Concentric rule: inner = outer − padding (min 8).
 * lg for content cards, xl only for sheets and full-bleed modals.
 */
export const radius = { sm: 8, md: 12, lg: 20, xl: 28, pill: 999 };

/** Continuous (squircle) corners on iOS; ignored elsewhere. */
export const curve = { borderCurve: 'continuous' as const };

/** Borders: hairlines inside grouped lists, 1 pt only where there is no fill contrast. */
export const border = { hair: StyleSheet.hairlineWidth, thin: 1 } as const;

/** SF Symbol / icon sizes. */
export const iconSize = { inline: 13, row: 17, toolbar: 22, action: 28, hero: 44 } as const;

/**
 * Type scale, mapped to iOS text styles. Use through <T variant="…"> so the font,
 * size, line height and Dynamic Type ceiling always travel together.
 * Unbounded never below 13 pt and never more than two lines.
 */
export const type = {
  hero: { fontFamily: fonts.display, fontSize: 34, lineHeight: 40, letterSpacing: -0.4 },
  title1: { fontFamily: fonts.display, fontSize: 28, lineHeight: 34, letterSpacing: -0.3 },
  title2: { fontFamily: fonts.displayMedium, fontSize: 22, lineHeight: 28 },
  title3: { fontFamily: fonts.displayMedium, fontSize: 18, lineHeight: 24 },
  headline: { fontFamily: fonts.text700, fontSize: 17, lineHeight: 22 },
  body: { fontFamily: fonts.text500, fontSize: 17, lineHeight: 24 },
  callout: { fontFamily: fonts.text600, fontSize: 15, lineHeight: 20 },
  footnote: { fontFamily: fonts.text500, fontSize: 13, lineHeight: 18 },
  caption: { fontFamily: fonts.text700, fontSize: 12, lineHeight: 16 },
  overline: { fontFamily: fonts.text800, fontSize: 12, lineHeight: 16, letterSpacing: 0.8, textTransform: 'uppercase' },
} satisfies Record<string, TextStyle>;
export type TypeVariant = keyof typeof type;

/** Dynamic Type ceilings per variant (maxFontSizeMultiplier). */
export const typeScale: Record<TypeVariant, number> = {
  hero: 1.2, title1: 1.25, title2: 1.3, title3: 1.35, headline: 1.6, body: 2, callout: 1.8, footnote: 1.8, caption: 1.6, overline: 1.4,
};

/** shadow-card — the Discover card and floating menus only */
export const shadow = {
  shadowColor: '#123A64',
  shadowOpacity: 0.1,
  shadowRadius: 24,
  shadowOffset: { width: 0, height: 8 },
  elevation: 5,
};

/** Motion tokens (Sound and motion section of the brand system) */
/** Floating elements over content (reaction capsule, round buttons over photos). */
export const shadowSoft = {
  shadowColor: '#000',
  shadowOpacity: 0.12,
  shadowRadius: 12,
  shadowOffset: { width: 0, height: 4 },
  elevation: 4,
};

export const motion = {
  fast: 120,
  base: 240,
  slow: 400,
  markDraw: 600,
};

export function bibNumber(n: number): string {
  return n.toString().padStart(4, '0');
}

/** "№0042" */
export function memberNo(n: number): string {
  return `№${bibNumber(n)}`;
}
