// Decides how an incoming chat photo is shown. Pure, so it can be unit-tested.
//
// assessment: what the on-device check said ('sensitive' / 'clear'), or 'unknown'
//             when no check ran (Android, iOS < 17, or Sensitive Content Warning off).
// blurAll:    the person's "Blur photos in chats" setting (on by default).
export type Assessment = 'sensitive' | 'clear' | 'unknown';

export function photoTreatment(assessment: Assessment, blurAll: boolean, mine: boolean): { blur: boolean; warn: boolean } {
  if (mine) return { blur: false, warn: false };
  if (assessment === 'sensitive') return { blur: true, warn: true }; // always, whatever the setting
  if (assessment === 'clear') return { blur: false, warn: false };
  return { blur: blurAll, warn: false };
}
