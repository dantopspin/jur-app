// Felt — the brand's one physical material: a warm wool tile used on the back
// of profile cards, the Pro card and the Regular patch. Same in light and dark.
import React from 'react';
import { ImageBackground, StyleSheet, type StyleProp, type ViewStyle } from 'react-native';
import { felt } from '../lib/theme';

const TILE = require('../../assets/felt.png');

export function Felt({ children, style }: { children?: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  return (
    <ImageBackground source={TILE} resizeMode="repeat" style={[styles.felt, style]} imageStyle={styles.image}>
      {children}
    </ImageBackground>
  );
}

const styles = StyleSheet.create({
  felt: { backgroundColor: felt.ground, overflow: 'hidden' },
  image: { resizeMode: 'repeat' },
});
