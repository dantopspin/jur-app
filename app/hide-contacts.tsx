// Hide from my contacts (Tinder "Block Contacts"). Phone numbers and emails from
// the address book become one-way codes on the phone; only the codes are sent.
// Hiding works both ways.
import * as Contacts from 'expo-contacts';
import React, { useEffect, useState } from 'react';
import { Alert, ScrollView, StyleSheet, View } from 'react-native';
import { Icon } from '../src/components/Icon';
import { toast } from '../src/components/Toast';
import { Button, Field, SectionLabel, T, Tag } from '../src/components/ui';
import { useI18n } from '../src/i18n';
import { api } from '../src/lib/api';
import { normaliseEmail, normalisePhone, qadamHash } from '../src/lib/contactHash';
import { colors, iconSize, layout, sp } from '../src/lib/theme';
import { showError } from '../src/lib/errors';

export default function HideContacts() {
  const { t } = useI18n();
  const [count, setCount] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [phone, setPhone] = useState('');

  useEffect(() => { api.contactHidesCount().then(setCount).catch(() => setCount(0)); }, []);

  async function hideAll() {
    setBusy(true);
    try {
      const { status } = await Contacts.requestPermissionsAsync();
      if (status !== 'granted') { Alert.alert(t('contacts.denied')); return; }
      const { data } = await Contacts.getContactsAsync({ fields: [Contacts.Fields.PhoneNumbers, Contacts.Fields.Emails] });
      const values = new Set<string>();
      for (const c of data) {
        for (const p of c.phoneNumbers ?? []) { const n = normalisePhone(p.number ?? ''); if (n) values.add(n); }
        for (const e of c.emails ?? []) { const n = normaliseEmail(e.email ?? ''); if (n) values.add(n); }
      }
      const hashes = await Promise.all([...values].slice(0, 5000).map(qadamHash));
      const n = await api.setContactHides(hashes);
      setCount(n);
      toast(t('contacts.done'));
    } catch (e) {
      showError(t, e);
    } finally {
      setBusy(false);
    }
  }

  async function turnOff() {
    setBusy(true);
    try { await api.setContactHides([]); setCount(0); } finally { setBusy(false); }
  }

  async function savePhone() {
    const n = normalisePhone(phone);
    if (!n) return;
    await api.setPhoneHash(await qadamHash(n));
    setPhone('');
    toast(t('states.saved'));
  }

  return (
    <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: layout.margin, gap: sp.xl, paddingBottom: sp.xxl * 2 }}>
      <View style={styles.hero}>
        <Icon name="eyeoff" size={iconSize.hero} color="blueText" weight="regular" />
        <T variant="body" tone="inkSoft" style={{ textAlign: 'center' }}>{t('contacts.body')}</T>
        <Tag tone={count ? 'good' : 'neutral'} icon={count ? 'tick' : undefined}
          label={count ? t('contacts.on', { n: count }) : t('contacts.off')} style={{ alignSelf: 'center' }} />
      </View>
      <View style={{ gap: sp.sm }}>
        <Button title={count ? t('contacts.update') : t('contacts.choose')} onPress={hideAll} loading={busy} />
        {count ? <Button title={t('contacts.turnOff')} variant="danger" onPress={turnOff} disabled={busy} /> : null}
      </View>

      <View style={{ gap: sp.sm }}>
        <SectionLabel style={{ marginBottom: 0 }}>{t('contacts.phoneTitle')}</SectionLabel>
        <T variant="footnote">{t('contacts.phoneHint')}</T>
        <Field value={phone} onChangeText={setPhone} placeholder="+7 7__ ___ __ __" keyboardType="phone-pad"
          textContentType="telephoneNumber" autoComplete="tel" />
        <Button title={t('contacts.phoneSave')} variant="secondary" onPress={savePhone} disabled={!normalisePhone(phone)} />
      </View>
      <T variant="footnote" style={{ textAlign: 'center' }}>{t('contacts.privacy')}</T>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  hero: { alignItems: 'center', gap: sp.md, paddingTop: sp.lg },
});
