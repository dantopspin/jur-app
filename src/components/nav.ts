// Native header presets. iOS gets large titles that collapse into a blurred
// bar as you scroll (scroll views need contentInsetAdjustmentBehavior="automatic").
import { Platform } from 'react-native';
import { fonts, useTheme } from '../lib/theme';

export function useLargeTitleOptions() {
  const { raw } = useTheme();
  const ios = Platform.OS === 'ios';
  return {
    headerLargeTitle: true,
    headerTransparent: ios,
    headerBlurEffect: ios ? ('systemChromeMaterial' as const) : undefined,
    headerShadowVisible: false,
    headerLargeTitleShadowVisible: false,
    headerLargeStyle: { backgroundColor: ios ? 'transparent' : raw.bg },
    headerStyle: ios ? undefined : { backgroundColor: raw.bg },
    headerTintColor: raw.blueText,
    // Unbounded for the large title only; the 44 pt bar uses Manrope so it never crowds the back button.
    headerTitleStyle: { fontFamily: fonts.text700, fontSize: 17, color: raw.ink },
    headerLargeTitleStyle: { fontFamily: fonts.displayMedium, fontSize: 28, color: raw.ink },
    contentStyle: { backgroundColor: raw.bg },
    headerBackButtonDisplayMode: 'minimal' as const,
  };
}

/** Standard pushed screens: small native title, page-coloured bar. */
export function useStackOptions() {
  const { raw } = useTheme();
  return {
    headerStyle: { backgroundColor: raw.bg },
    headerShadowVisible: false,
    headerTintColor: raw.blueText,
    headerTitleStyle: { fontFamily: fonts.text700, fontSize: 17, color: raw.ink },
    headerBackButtonDisplayMode: 'minimal' as const,
    contentStyle: { backgroundColor: raw.bg },
  };
}
