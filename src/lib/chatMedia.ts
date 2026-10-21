// Chat photos and voice notes live in the private "chat-media" bucket under
// <match_id>/<file>. Only the two people in the match can read them, through
// short-lived signed URLs (cached here for 50 minutes).
import { decode } from 'base64-arraybuffer';
import * as FileSystem from 'expo-file-system/legacy';
import { supabase } from './supabase';
import type { PickedImage } from './upload';

const BUCKET = 'chat-media';
const cache = new Map<string, { url: string; until: number }>();

function rid() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export async function uploadChatPhoto(matchId: string, img: PickedImage): Promise<string> {
  const ext = img.mimeType.includes('png') ? 'png' : 'jpg';
  const path = `${matchId}/${rid()}.${ext}`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, decode(img.base64), { contentType: img.mimeType });
  if (error) throw new Error(error.message);
  return path;
}

export async function uploadVoice(matchId: string, fileUri: string): Promise<string> {
  const b64 = await FileSystem.readAsStringAsync(fileUri, { encoding: FileSystem.EncodingType.Base64 });
  const path = `${matchId}/${rid()}.m4a`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, decode(b64), { contentType: 'audio/m4a' });
  if (error) throw new Error(error.message);
  return path;
}

export async function mediaUrl(path: string): Promise<string | null> {
  const hit = cache.get(path);
  if (hit && hit.until > Date.now()) return hit.url;
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, 3600);
  if (error || !data) return null;
  cache.set(path, { url: data.signedUrl, until: Date.now() + 50 * 60_000 });
  return data.signedUrl;
}
