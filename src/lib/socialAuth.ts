// Sign in with Apple (iOS) and Google, exchanged for a Supabase session with
// signInWithIdToken. Email codes remain the fallback (and Android without Google).
import { GoogleSignin, isErrorWithCode, isSuccessResponse, statusCodes } from '@react-native-google-signin/google-signin';
import * as AppleAuthentication from 'expo-apple-authentication';
import { Platform } from 'react-native';
import { env } from './env';
import { supabase } from './supabase';

export type SocialResult = 'ok' | 'cancelled' | 'error';

/** First name from Apple/Google, offered as the default on the name step. */
let prefillName: string | null = null;
export function takePrefillName(): string {
  const n = prefillName ?? '';
  prefillName = null;
  return n;
}

export const googleEnabled = Boolean(env.googleWebClientId);
if (googleEnabled) {
  GoogleSignin.configure({
    webClientId: env.googleWebClientId,
    iosClientId: env.googleIosClientId || undefined,
  });
}

export async function appleAvailable(): Promise<boolean> {
  if (Platform.OS !== 'ios') return false;
  try {
    return await AppleAuthentication.isAvailableAsync();
  } catch {
    return false;
  }
}

export async function signInWithApple(): Promise<SocialResult> {
  try {
    const cred = await AppleAuthentication.signInAsync({
      requestedScopes: [
        AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
        AppleAuthentication.AppleAuthenticationScope.EMAIL,
      ],
    });
    if (!cred.identityToken) return 'error';
    // Apple only shares the name on the very first sign-in.
    if (cred.fullName?.givenName) prefillName = cred.fullName.givenName;
    const { error } = await supabase.auth.signInWithIdToken({ provider: 'apple', token: cred.identityToken });
    return error ? 'error' : 'ok';
  } catch (e) {
    if (e && typeof e === 'object' && 'code' in e && (e as { code: string }).code === 'ERR_REQUEST_CANCELED') return 'cancelled';
    return 'error';
  }
}

export async function signInWithGoogle(): Promise<SocialResult> {
  if (!googleEnabled) return 'error';
  try {
    await GoogleSignin.hasPlayServices({ showPlayServicesUpdateDialog: true });
    const res = await GoogleSignin.signIn();
    if (!isSuccessResponse(res)) return 'cancelled';
    const token = res.data.idToken;
    if (!token) return 'error';
    if (res.data.user.givenName) prefillName = res.data.user.givenName;
    const { error } = await supabase.auth.signInWithIdToken({ provider: 'google', token });
    return error ? 'error' : 'ok';
  } catch (e) {
    if (isErrorWithCode(e) && (e.code === statusCodes.SIGN_IN_CANCELLED || e.code === statusCodes.IN_PROGRESS)) return 'cancelled';
    return 'error';
  }
}

/** Also forget the Google account on sign-out, so the picker shows next time. */
export async function signOutSocial() {
  if (!googleEnabled) return;
  await GoogleSignin.signOut().catch(() => {});
}
