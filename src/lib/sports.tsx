import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { api } from './api';
import type { Season, Sport } from './types';

interface SportsState {
  sports: Sport[];
  byCode: Record<string, Sport>;
}

const Ctx = createContext<SportsState>({ sports: [], byCode: {} });

export function SportsProvider({ children }: { children: React.ReactNode }) {
  const [sports, setSports] = useState<Sport[]>([]);
  useEffect(() => {
    api.sports().then(setSports).catch((e) => console.warn('sports load failed', e));
  }, []);
  const value = useMemo(
    () => ({ sports, byCode: Object.fromEntries(sports.map((s) => [s.code, s])) }),
    [sports],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSports(): SportsState {
  return useContext(Ctx);
}

/** Mirrors current_season() in SQL: Nov–Mar is winter. */
export function currentSeason(d = new Date()): Exclude<Season, 'all'> {
  const m = d.getMonth() + 1;
  return m >= 11 || m <= 3 ? 'winter' : 'summer';
}

export const CITIES = ['almaty', 'astana', 'shymkent', 'karaganda', 'aktobe', 'atyrau', 'oskemen'] as const;
export type City = (typeof CITIES)[number];
