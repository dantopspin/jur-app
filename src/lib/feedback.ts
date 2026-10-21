// Sound + haptics for key moments (brand system › Sound and motion).
// Sounds are short, optional (Settings), and silent when the phone is on silent.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createAudioPlayer, type AudioPlayer } from 'expo-audio';
import * as Haptics from 'expo-haptics';

export type Moment = 'match' | 'like' | 'super' | 'message' | 'checkin';

const SOURCES: Record<Moment, number> = {
  match: require('../../assets/sounds/match.wav'),
  like: require('../../assets/sounds/like.wav'),
  super: require('../../assets/sounds/super.wav'),
  message: require('../../assets/sounds/message.wav'),
  checkin: require('../../assets/sounds/checkin.wav'),
};

// Haptics follow the sounds note for note (brand system › Sound and motion):
// the match is two plucks 90 ms apart, the super like a down-up strum, the
// check-in a wooden knock and then a pluck. Times in ms from the start.
type Hit = [number, () => Promise<void>];
const light = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
const medium = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
const heavy = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
const soft = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Soft);
const rigid = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Rigid);
const success = () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);

const HAPTIC: Record<Moment, Hit[]> = {
  match: [[0, medium], [90, heavy], [420, soft]],          // low string, high string, the ring
  like: [[0, light]],                                       // one muted pluck
  super: [[0, light], [25, light], [150, medium], [170, light]], // қағыс: down and up
  message: [[0, soft]],                                     // a single harmonic
  checkin: [[0, rigid], [50, medium], [320, success]],     // knock on the dombra body, pluck, done
};

function play(hits: Hit[]) {
  for (const [at, fn] of hits) {
    if (at === 0) fn().catch(() => {});
    else setTimeout(() => { fn().catch(() => {}); }, at);
  }
}

const KEY = 'qadam.sounds';
let soundsOn = true;
AsyncStorage.getItem(KEY).then((v) => { if (v === 'off') soundsOn = false; }).catch(() => {});

const players: Partial<Record<Moment, AudioPlayer>> = {};

export function setSoundsEnabled(on: boolean) {
  soundsOn = on;
  AsyncStorage.setItem(KEY, on ? 'on' : 'off').catch(() => {});
}

export async function soundsEnabled(): Promise<boolean> {
  const v = await AsyncStorage.getItem(KEY).catch(() => null);
  return v !== 'off';
}

/** Plays the moment's sound (if enabled) and its haptic. Never throws. */
export function feedback(moment: Moment) {
  play(HAPTIC[moment]);
  if (!soundsOn) return;
  try {
    let p = players[moment];
    if (!p) {
      p = createAudioPlayer(SOURCES[moment]);
      players[moment] = p;
    }
    p.seekTo(0);
    p.play();
  } catch {
    // audio is decoration; ignore failures
  }
}
