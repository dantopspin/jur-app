// Pure helpers for contact hashing (unit-tested in contactNormalize.test.ts).
/** Kazakhstan-first phone normalisation: 8 777 123 45 67 / +7 (777) 123-45-67 → 77771234567. */
export function normalisePhone(raw: string): string | null {
  let d = raw.replace(/\D/g, '');
  if (d.length === 11 && d.startsWith('8')) d = `7${d.slice(1)}`;
  if (d.length === 10) d = `7${d}`;
  return d.length >= 10 && d.length <= 15 ? d : null;
}

export function normaliseEmail(raw: string): string | null {
  const e = raw.trim().toLowerCase();
  return /^\S+@\S+\.\S+$/.test(e) ? e : null;
}

