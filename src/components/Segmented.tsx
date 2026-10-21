// A two- or three-way switch in the style of iOS's segmented control.
import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { tick } from '../lib/haptics';
import { colors, curve, fonts, shadowSoft } from '../lib/theme';

export function Segmented<T extends string>({
  value, options, onChange,
}: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void }) {
  return (
    <View style={styles.wrap} accessibilityRole="tablist">
      {options.map((o) => {
        const on = o.value === value;
        return (
          <Pressable key={o.value} style={[styles.item, on && styles.on]} accessibilityRole="tab"
            accessibilityState={{ selected: on }} onPress={() => { if (!on) { tick(); onChange(o.value); } }}>
            <Text maxFontSizeMultiplier={1.3} style={[styles.label, on && styles.labelOn]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

// iOS dimensions (32 pt track, 9 pt / 7 pt radii, 13 pt label), brand colours.
const styles = StyleSheet.create({
  wrap: { flexDirection: 'row', backgroundColor: colors.line, borderRadius: 9, ...curve, padding: 2, minHeight: 32 },
  item: { flex: 1, minHeight: 28, borderRadius: 7, ...curve, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8 },
  on: { backgroundColor: colors.card, ...shadowSoft, shadowOpacity: 0.08, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  label: { fontFamily: fonts.text600, fontSize: 13, color: colors.inkSoft },
  labelOn: { fontFamily: fonts.text700, color: colors.ink },
});
