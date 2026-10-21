// One icon component for the whole app: SF Symbols on iOS (they match the system
// font, weight and animations), Ionicons on Android. Colours are palette keys
// ("blue", "clay"…) so icons follow light and dark mode.
import Ionicons from '@expo/vector-icons/Ionicons';
import { SymbolView, type SymbolWeight } from 'expo-symbols';
import React from 'react';
import { Platform } from 'react-native';
import { useTheme, type ColorKey } from '../lib/theme';

type IonName = React.ComponentProps<typeof Ionicons>['name'];

const ICONS = {
  close: ['xmark', 'close'],
  star: ['star.fill', 'star'],
  note: ['text.bubble.fill', 'chatbubble-ellipses'],
  more: ['ellipsis', 'ellipsis-horizontal'],
  back: ['chevron.left', 'chevron-back'],
  forward: ['chevron.right', 'chevron-forward'],
  add: ['plus', 'add'],
  selfie: ['hand.thumbsup', 'thumbs-up-outline'],
  mail: ['envelope', 'mail-outline'],
  boost: ['bolt.fill', 'flash'],
  flag: ['flag.fill', 'flag'],
  check: ['checkmark.circle.fill', 'checkmark-circle'],
  circle: ['circle', 'ellipse-outline'],
  send: ['arrow.up', 'arrow-up'],
  verified: ['checkmark.seal.fill', 'checkmark-done-circle'],
  location: ['mappin.and.ellipse', 'location-outline'],
  calendar: ['calendar', 'calendar-outline'],
  people: ['person.2.fill', 'people'],
  tea: ['cup.and.saucer.fill', 'cafe-outline'],
  bell: ['bell.badge.fill', 'notifications'],
  flip: ['arrow.triangle.2.circlepath', 'sync'],
  sparkle: ['sparkles', 'sparkles'],
  moon: ['moon.stars.fill', 'moon'],
  share: ['square.and.arrow.up', 'share-outline'],
  ticket: ['ticket', 'ticket-outline'],
  undo: ['arrow.uturn.backward', 'arrow-undo'],
  plane: ['airplane', 'airplane'],
  mic: ['mic.fill', 'mic'],
  stop: ['stop.fill', 'stop'],
  play: ['play.fill', 'play'],
  pause: ['pause.fill', 'pause'],
  photo: ['photo', 'image-outline'],
  reply: ['arrowshape.turn.up.left.fill', 'arrow-undo'],
  copy: ['doc.on.doc', 'copy-outline'],
  heart: ['heart.fill', 'heart'],
  fire: ['flame.fill', 'flame'],
  clap: ['hands.clap.fill', 'hand-right'],
  laugh: ['face.smiling.inverse', 'happy'],
  thumbsup: ['hand.thumbsup.fill', 'thumbs-up'],
  duo: ['person.2.circle.fill', 'people-circle'],
  eyeoff: ['eye.slash.fill', 'eye-off'],
  coffee: ['cup.and.saucer.fill', 'cafe'],
  offline: ['wifi.exclamationmark', 'cloud-offline-outline'],
  gear: ['gearshape', 'settings-outline'],
  info: ['info.circle', 'information-circle-outline'],
  plusCircle: ['plus.circle.fill', 'add-circle'],
  tick: ['checkmark', 'checkmark'],
  warn: ['exclamationmark.circle.fill', 'alert-circle'],
  chats: ['bubble.left.and.bubble.right.fill', 'chatbubbles'],
  search: ['magnifyingglass', 'search'],
  clock: ['clock', 'time-outline'],
  edit: ['pencil', 'create-outline'],
  trash: ['trash', 'trash-outline'],
  logout: ['rectangle.portrait.and.arrow.right', 'log-out-outline'],
  lock: ['lock.fill', 'lock-closed'],
  doc: ['doc.text', 'document-text-outline'],
  help: ['questionmark.circle', 'help-circle-outline'],
  card: ['creditcard', 'card-outline'],
  paint: ['paintbrush.fill', 'color-palette'],
  sound: ['speaker.wave.2.fill', 'volume-high'],
  hide: ['moon.zzz.fill', 'moon'],
  // sports
  running: ['figure.run', 'walk-outline'],
  trail: ['mountain.2.fill', 'trail-sign-outline'],
  hiking: ['figure.hiking', 'trail-sign-outline'],
  cycling: ['figure.outdoor.cycle', 'bicycle-outline'],
  tennis: ['figure.tennis', 'tennisball-outline'],
  padel: ['tennis.racket', 'tennisball-outline'],
  football: ['soccerball', 'football-outline'],
  volleyball: ['volleyball.fill', 'basketball-outline'],
  swimming: ['figure.pool.swim', 'water-outline'],
  gym: ['dumbbell.fill', 'barbell-outline'],
  yoga: ['figure.yoga', 'body-outline'],
  climbing: ['figure.climbing', 'fitness-outline'],
  boxing: ['figure.boxing', 'fitness-outline'],
  skiing: ['figure.skiing.downhill', 'snow-outline'],
  snowboard: ['figure.snowboarding', 'snow-outline'],
  xc_skiing: ['figure.skiing.crosscountry', 'snow-outline'],
  skating: ['figure.skating', 'snow-outline'],
  hockey: ['figure.hockey', 'snow-outline'],
  sport: ['figure.mixed.cardio', 'flag-outline'],
} satisfies Record<string, [string, IonName]>;

export type IconName = keyof typeof ICONS;

/** The SF Symbol behind an icon name (for native menus). */
export function sfName(name: IconName): string {
  return ICONS[name][0];
}

export function sportIconName(code: string): IconName {
  return (code in ICONS ? code : 'sport') as IconName;
}

export function Icon({
  name, size = 24, color = 'ink', weight = 'semibold', bounce,
}: {
  name: IconName;
  size?: number;
  /** a palette key, or a literal colour string */
  color?: ColorKey | (string & {});
  weight?: SymbolWeight;
  /** play the SF Symbol bounce when this value changes (iOS) */
  bounce?: unknown;
}) {
  const { raw } = useTheme();
  const tint = color in raw ? raw[color as ColorKey] : color;
  const [sf, ion] = ICONS[name];
  const fallback = <Ionicons name={ion} size={size} color={tint} />;
  if (Platform.OS !== 'ios') return fallback;
  return (
    <SymbolView
      key={bounce === undefined ? undefined : String(bounce)}
      name={sf}
      size={size}
      tintColor={tint}
      weight={weight}
      type="hierarchical"
      animationSpec={bounce === undefined ? undefined : { effect: { type: 'bounce' } }}
      fallback={fallback}
      style={{ width: size, height: size }}
    />
  );
}
