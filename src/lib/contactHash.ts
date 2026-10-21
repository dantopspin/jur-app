// Turn address-book entries into one-way codes before anything leaves the phone.
// Must match qadam_hash() in the database: SHA-256 of "qadam:" + normalised value.
import * as Crypto from 'expo-crypto';

export { normaliseEmail, normalisePhone } from './contactNormalize';

export async function qadamHash(value: string): Promise<string> {
  return Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, `qadam:${value}`);
}
