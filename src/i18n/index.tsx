import AsyncStorage from '@react-native-async-storage/async-storage';
import { getLocales } from 'expo-localization';
import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { Locale, Sport } from '../lib/types';
import en, { type Dict } from './en';
import kk from './kk';
import ru from './ru';

const dicts: Record<Locale, Dict> = { en, ru, kk };
const STORAGE_KEY = 'qadam.locale';

type Leaves<T, P extends string = ''> = {
  [K in keyof T & string]: T[K] extends string ? `${P}${K}` : Leaves<T[K], `${P}${K}.`>;
}[keyof T & string];
export type TKey = Leaves<Dict>;

function lookup(dict: Dict, key: string): string {
  let node: unknown = dict;
  for (const part of key.split('.')) {
    if (node && typeof node === 'object' && part in (node as Record<string, unknown>)) {
      node = (node as Record<string, unknown>)[part];
    } else {
      return key;
    }
  }
  return typeof node === 'string' ? node : key;
}

export function format(template: string, vars?: Record<string, string | number>): string {
  if (!vars) return template;
  return template.replace(/\{(\w+)\}/g, (_, k: string) => (k in vars ? String(vars[k]) : `{${k}}`));
}

function deviceLocale(): Locale {
  const code = getLocales()[0]?.languageCode ?? 'ru';
  if (code === 'kk') return 'kk';
  if (code === 'en') return 'en';
  return 'ru';
}

interface I18n {
  locale: Locale;
  setLocale: (l: Locale) => void;
  t: (key: TKey, vars?: Record<string, string | number>) => string;
  sportName: (s: Pick<Sport, 'name_kk' | 'name_ru' | 'name_en'>) => string;
  /** 'almaty' → 'Алматы'; unknown codes are returned as typed */
  cityName: (code: string) => string;
  /** BCP-47 tag for dates and numbers */
  intl: string;
}

const Ctx = createContext<I18n | null>(null);

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(deviceLocale());

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY).then((v) => {
      if (v === 'kk' || v === 'ru' || v === 'en') setLocaleState(v);
    });
  }, []);

  const setLocale = useCallback((l: Locale) => {
    setLocaleState(l);
    AsyncStorage.setItem(STORAGE_KEY, l).catch(() => {});
  }, []);

  const value = useMemo<I18n>(() => {
    const dict = dicts[locale];
    return {
      locale,
      setLocale,
      t: (key, vars) => format(lookup(dict, key), vars),
      sportName: (s) => (locale === 'kk' ? s.name_kk : locale === 'en' ? s.name_en : s.name_ru),
      cityName: (code) => {
        const v = lookup(dict, `cities.${code}`);
        return v === `cities.${code}` ? code : v;
      },
      intl: locale === 'kk' ? 'kk-KZ' : locale === 'en' ? 'en-GB' : 'ru-RU',
    };
  }, [locale, setLocale]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useI18n(): I18n {
  const v = useContext(Ctx);
  if (!v) throw new Error('useI18n outside I18nProvider');
  return v;
}
