// Photo and voice-note bubbles for the match chat.
import { useAudioPlayer, useAudioPlayerStatus } from 'expo-audio';
import { Image } from 'expo-image';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { mediaUrl } from '../../lib/chatMedia';
import { photoTreatment, type Assessment } from '../../lib/photoPolicy';
import { assessPhoto, useBlurAll } from '../../lib/photoSafety';
import { colors, fonts } from '../../lib/theme';
import { Icon } from '../Icon';

function useSigned(path: string | null) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => { if (path) mediaUrl(path).then(setUrl); }, [path]);
  return url;
}

export function PhotoBubble({ path, label, mine, hiddenLabel, warnLabel }: {
  path: string; label: string; mine: boolean;
  /** "Tap to view photo" */
  hiddenLabel: string;
  /** "May contain nudity · Tap to view" */
  warnLabel: string;
}) {
  const url = useSigned(path);
  const blurAll = useBlurAll();
  const [assessment, setAssessment] = useState<Assessment | null>(mine ? 'clear' : null);
  const [revealed, setRevealed] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!url || mine) return;
    let live = true;
    assessPhoto(path, url).then((a) => { if (live) setAssessment(a); });
    return () => { live = false; };
  }, [url, path, mine]);

  // Until the check finishes, incoming photos stay covered.
  const treat = assessment === null ? { blur: true, warn: false } : photoTreatment(assessment, blurAll, mine);
  const covered = treat.blur && !revealed;

  return (
    <>
      <Pressable
        onPress={() => { if (!url) return; if (covered) { setRevealed(true); return; } setOpen(true); }}
        accessibilityRole="imagebutton"
        accessibilityLabel={covered ? `${label}. ${treat.warn ? warnLabel : hiddenLabel}` : label}>
        {url ? (
          <View>
            <Image source={{ uri: url }} style={styles.photo} contentFit="cover" transition={150} blurRadius={covered ? 40 : 0} />
            {covered ? (
              <View style={[StyleSheet.absoluteFill, styles.cover]}>
                <Icon name={treat.warn ? 'warn' : 'eyeoff'} size={22} color="#FFFFFF" />
                <Text maxFontSizeMultiplier={1.4} style={styles.coverText}>{treat.warn ? warnLabel : hiddenLabel}</Text>
              </View>
            ) : null}
          </View>
        ) : <View style={[styles.photo, styles.center]}><ActivityIndicator /></View>}
      </Pressable>
      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        <Pressable style={styles.viewer} onPress={() => setOpen(false)} accessibilityLabel={label}>
          {url ? <Image source={{ uri: url }} style={StyleSheet.absoluteFill} contentFit="contain" /> : null}
        </Pressable>
      </Modal>
    </>
  );
}

function clock(ms: number) {
  const s = Math.max(0, Math.round(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export function VoiceBubble({ path, ms, mine, label }: { path: string; ms: number | null; mine: boolean; label: string }) {
  const url = useSigned(path);
  const player = useAudioPlayer(url ? { uri: url } : null);
  const status = useAudioPlayerStatus(player);
  const total = (status.duration || (ms ?? 0) / 1000) * 1000;
  const progress = total > 0 ? Math.min(1, (status.currentTime * 1000) / total) : 0;
  const fg = mine ? '#FFFFFF' : colors.blueText;

  function toggle() {
    if (!url) return;
    if (status.playing) player.pause();
    else {
      if (status.didJustFinish || progress >= 0.99) player.seekTo(0);
      player.play();
    }
  }

  return (
    <Pressable onPress={toggle} style={styles.voice} accessibilityRole="button" accessibilityLabel={label}>
      <View style={[styles.play, { backgroundColor: mine ? 'rgba(255,255,255,0.2)' : colors.blueTint }]}>
        {url ? <Icon name={status.playing ? 'pause' : 'play'} size={16} color={mine ? '#FFFFFF' : 'blueText'} />
          : <ActivityIndicator color={fg} />}
      </View>
      <View style={styles.wave}>
        {BARS.map((h, i) => (
          <View key={i} style={{ width: 3, height: h, borderRadius: 2, backgroundColor: fg, opacity: i / BARS.length <= progress ? 1 : 0.35 }} />
        ))}
      </View>
      <Text maxFontSizeMultiplier={1.6} style={[styles.time, { color: mine ? colors.blueMist : colors.muted }]}>
        {clock(status.playing ? status.currentTime * 1000 : total)}
      </Text>
    </Pressable>
  );
}

// a fixed, pleasant-looking waveform (the real one isn't worth the bytes)
const BARS = [6, 10, 14, 9, 18, 12, 20, 15, 8, 16, 22, 13, 9, 17, 11, 7, 14, 19, 10, 6];

const styles = StyleSheet.create({
  photo: { width: 220, height: 260, borderRadius: 15, backgroundColor: colors.line }, // concentric inside an 18 pt bubble with 3 pt padding
  center: { alignItems: 'center', justifyContent: 'center' },
  cover: { alignItems: 'center', justifyContent: 'center', gap: 8, padding: 16, borderRadius: 15, backgroundColor: 'rgba(18,58,100,0.35)' },
  coverText: { fontFamily: fonts.text700, fontSize: 13, lineHeight: 18, color: '#FFFFFF', textAlign: 'center' },
  viewer: { flex: 1, backgroundColor: '#000' },
  voice: { flexDirection: 'row', alignItems: 'center', gap: 10, minWidth: 200, paddingVertical: 2 },
  play: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  wave: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 2, height: 24 },
  time: { fontFamily: fonts.text600, fontSize: 12, minWidth: 32, textAlign: 'right' },
});
