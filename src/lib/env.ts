// Public runtime config from .env (EXPO_PUBLIC_* are inlined at build time).
export const env = {
  supabaseUrl: process.env.EXPO_PUBLIC_SUPABASE_URL ?? '',
  supabaseAnonKey: process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '',
  revenueCatIos: process.env.EXPO_PUBLIC_REVENUECAT_IOS_KEY ?? '',
  revenueCatAndroid: process.env.EXPO_PUBLIC_REVENUECAT_ANDROID_KEY ?? '',
  // Google Cloud → Credentials: the Web client id (also pasted into Supabase → Auth → Google)
  googleWebClientId: process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID ?? '',
  googleIosClientId: process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID ?? '',
  privacyUrl: process.env.EXPO_PUBLIC_PRIVACY_URL ?? 'https://qadam.app/privacy',
  termsUrl: process.env.EXPO_PUBLIC_TERMS_URL ?? 'https://qadam.app/terms',
  supportEmail: process.env.EXPO_PUBLIC_SUPPORT_EMAIL ?? 'support@qadam.app',
};

export const isConfigured = Boolean(env.supabaseUrl && env.supabaseAnonKey);
