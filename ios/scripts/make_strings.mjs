// Builds Jur/Resources/Localizable.xcstrings from the shared kk/ru/en dictionaries
// (src/i18n/*.ts). Keys are dotted paths ("discover.empty"); "{name}" placeholders
// are kept as-is and filled by L10n.t(_:_:) in Swift.
// Run from ios/:  npx tsx scripts/make_strings.mjs
import { writeFileSync } from 'node:fs';
import en from '../../src/i18n/en.ts';
import ru from '../../src/i18n/ru.ts';
import kk from '../../src/i18n/kk.ts';

const flat = (o, p = '', out = {}) => {
  for (const [k, v] of Object.entries(o)) {
    const key = p ? `${p}.${k}` : k;
    if (typeof v === 'string') out[key] = v; else flat(v, key, out);
  }
  return out;
};
const langs = { en: flat(en.default ?? en), ru: flat(ru.default ?? ru), kk: flat(kk.default ?? kk) };
const strings = {};
for (const key of Object.keys(langs.en).sort()) {
  const localizations = {};
  for (const [lang, dict] of Object.entries(langs)) {
    if (dict[key] !== undefined) localizations[lang] = { stringUnit: { state: 'translated', value: dict[key] } };
  }
  strings[key] = { extractionState: 'manual', localizations };
}
writeFileSync('Jur/Resources/Localizable.xcstrings', JSON.stringify({ sourceLanguage: 'en', strings, version: '1.0' }, null, 2));
console.log(Object.keys(strings).length, 'keys');
