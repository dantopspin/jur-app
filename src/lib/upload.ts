import { decode } from 'base64-arraybuffer';
import * as ImagePicker from 'expo-image-picker';
import { supabase } from './supabase';

function randomId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export interface PickedImage {
  uri: string;
  base64: string;
  mimeType: string;
}

export async function pickPhoto(): Promise<PickedImage | null> {
  const res = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsEditing: true,
    aspect: [4, 5],
    quality: 0.8,
    base64: true,
  });
  if (res.canceled || !res.assets[0]?.base64) return null;
  const a = res.assets[0];
  return { uri: a.uri, base64: a.base64!, mimeType: a.mimeType ?? 'image/jpeg' };
}

export async function takeSelfie(): Promise<PickedImage | null> {
  const perm = await ImagePicker.requestCameraPermissionsAsync();
  if (!perm.granted) return null;
  const res = await ImagePicker.launchCameraAsync({
    cameraType: ImagePicker.CameraType.front,
    quality: 0.7,
    base64: true,
  });
  if (res.canceled || !res.assets[0]?.base64) return null;
  const a = res.assets[0];
  return { uri: a.uri, base64: a.base64!, mimeType: a.mimeType ?? 'image/jpeg' };
}

function ext(mime: string): string {
  if (mime.includes('png')) return 'png';
  if (mime.includes('webp')) return 'webp';
  return 'jpg';
}

/** Uploads to the public photos bucket and returns the public URL. */
export async function uploadProfilePhoto(userId: string, img: PickedImage): Promise<string> {
  const path = `${userId}/${randomId()}.${ext(img.mimeType)}`;
  const { error } = await supabase.storage.from('photos')
    .upload(path, decode(img.base64), { contentType: img.mimeType, upsert: false });
  if (error) throw new Error(error.message);
  return supabase.storage.from('photos').getPublicUrl(path).data.publicUrl;
}

/** Uploads to the private verification bucket and returns the storage path. */
export async function uploadSelfie(userId: string, img: PickedImage): Promise<string> {
  const path = `${userId}/selfie-${randomId()}.${ext(img.mimeType)}`;
  const { error } = await supabase.storage.from('verification')
    .upload(path, decode(img.base64), { contentType: img.mimeType, upsert: false });
  if (error) throw new Error(error.message);
  return path;
}

/** Removes a photo we uploaded earlier (best effort). */
export async function deleteProfilePhoto(publicUrl: string): Promise<void> {
  const marker = '/storage/v1/object/public/photos/';
  const i = publicUrl.indexOf(marker);
  if (i < 0) return;
  await supabase.storage.from('photos').remove([publicUrl.slice(i + marker.length)]);
}
