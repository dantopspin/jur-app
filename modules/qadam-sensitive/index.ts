// JS side of the local QadamSensitive module (iOS only; null elsewhere and in Expo Go).
import { requireOptionalNativeModule } from 'expo-modules-core';

export type SensitivePolicy = 'unavailable' | 'disabled' | 'simple' | 'descriptive';

interface QadamSensitiveNative {
  policy(): Promise<SensitivePolicy>;
  analyze(fileUri: string): Promise<boolean>;
}

export const QadamSensitive = requireOptionalNativeModule<QadamSensitiveNative>('QadamSensitive');
