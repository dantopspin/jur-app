// Voice notes: record with expo-audio (AAC .m4a), max 2 minutes.
import {
  AudioModule, RecordingPresets, setAudioModeAsync, useAudioRecorder, useAudioRecorderState,
} from 'expo-audio';
import { useEffect } from 'react';

export const MAX_VOICE_MS = 120_000;

export function useVoiceRecorder() {
  const recorder = useAudioRecorder(RecordingPresets.HIGH_QUALITY);
  const state = useAudioRecorderState(recorder, 250);

  async function start(): Promise<boolean> {
    const perm = await AudioModule.requestRecordingPermissionsAsync();
    if (!perm.granted) return false;
    await setAudioModeAsync({ playsInSilentMode: true, allowsRecording: true });
    await recorder.prepareToRecordAsync();
    recorder.record();
    return true;
  }

  /** Stops and returns the file and its length (null when cancelled or too short). */
  async function stop(keep: boolean): Promise<{ uri: string; ms: number } | null> {
    const ms = state.durationMillis;
    await recorder.stop();
    await setAudioModeAsync({ playsInSilentMode: true, allowsRecording: false });
    if (!keep || !recorder.uri || ms < 600) return null;
    return { uri: recorder.uri, ms: Math.min(ms, MAX_VOICE_MS) };
  }

  // stop automatically at the limit
  useEffect(() => {
    if (state.isRecording && state.durationMillis >= MAX_VOICE_MS) recorder.stop().catch(() => {});
  }, [state.isRecording, state.durationMillis, recorder]);

  return { start, stop, recording: state.isRecording, ms: state.durationMillis };
}
