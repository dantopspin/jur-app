import type { Session } from '@supabase/supabase-js';
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { useI18n } from '../i18n';
import { api } from './api';
import { initPurchases, resetPurchases } from './purchases';
import { forgetPushToken, syncPushToken } from './push';
import { signOutSocial } from './socialAuth';
import { clearWidget } from './widget';
import { supabase } from './supabase';
import type { Limits, MyProfile } from './types';
import { features } from './features';

interface SessionState {
  ready: boolean;
  session: Session | null;
  profile: MyProfile | null;
  /** the profile couldn't be loaded (network, server) — not the same as "no profile yet" */
  profileError: boolean;
  limits: Limits | null;
  refreshProfile: () => Promise<void>;
  refreshLimits: () => Promise<void>;
  signOut: () => Promise<void>;
}

const Ctx = createContext<SessionState | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const { setLocale, t } = useI18n();
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [profileError, setProfileError] = useState(false);
  const [limits, setLimits] = useState<Limits | null>(null);
  const activityRecordedFor = useRef<string | null>(null);

  const refreshLimits = useCallback(async () => {
    try {
      setLimits(await api.limits());
    } catch {
      // not fatal; UI shows without counters
    }
  }, []);

  const refreshProfile = useCallback(async () => {
    let p: MyProfile | null;
    try {
      p = await api.myProfile();
    } catch (e) {
      setProfileError(true);
      throw e;
    }
    setProfileError(false);
    setProfile(p);
    if (p) {
      setLocale(p.locale);
      await refreshLimits();
    }
  }, [refreshLimits, setLocale]);

  // Load the persisted session and follow auth changes.
  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return;
      setSession(data.session);
      if (!data.session) setReady(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s);
      if (!s) {
        setProfile(null);
        setProfileError(false);
        setLimits(null);
        setReady(true);
      }
    });
    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  // When a user is signed in: load their profile, connect purchases, record the streak.
  const userId = session?.user.id ?? null;
  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    (async () => {
      try {
        await refreshProfile();
        initPurchases(userId);
        syncPushToken({ matches: t('notify.matches'), chats: t('notify.chats'), activity: t(features.events ? 'notify.activity' : 'notify.activityApp') });
        if (activityRecordedFor.current !== userId) {
          activityRecordedFor.current = userId;
          api.recordActivity().then(() => refreshLimits()).catch(() => {});
        }
      } catch (e) {
        console.warn('profile load failed', e);
      } finally {
        if (!cancelled) setReady(true);
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId, refreshProfile, refreshLimits]);

  const signOut = useCallback(async () => {
    await forgetPushToken();
    await resetPurchases();
    await signOutSocial();
    clearWidget();
    await supabase.auth.signOut();
  }, []);

  return (
    <Ctx.Provider value={{ ready, session, profile, profileError, limits, refreshProfile, refreshLimits, signOut }}>
      {children}
    </Ctx.Provider>
  );
}

export function useSession(): SessionState {
  const v = useContext(Ctx);
  if (!v) throw new Error('useSession outside SessionProvider');
  return v;
}

/** For screens that only render when signed in with a profile. */
export function useMe(): { me: MyProfile; userId: string } {
  const { profile } = useSession();
  if (!profile) throw new Error('useMe without a profile');
  return { me: profile, userId: profile.id };
}
