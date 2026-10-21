// Small touch feedback for everyday interactions. The big moments (match, like,
// super like, check-in) use feedback.ts, where haptics follow the dombra sounds.
import * as Haptics from 'expo-haptics';

/** A selection tick: chips, choices, tabs inside screens, toggles. */
export function tick() {
  Haptics.selectionAsync().catch(() => {});
}

/** A soft bump: a swipe crosses its threshold, a sheet snaps, a card flips. */
export function bump() {
  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Soft).catch(() => {});
}

/** A firm knock: long-press menus, removing a photo. */
export function knock() {
  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Rigid).catch(() => {});
}

/** Something worked (sent, saved, turned on). */
export function success() {
  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
}

/** Something failed. */
export function failure() {
  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error).catch(() => {});
}
