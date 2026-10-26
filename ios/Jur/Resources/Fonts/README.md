Brand fonts (SIL Open Font License 1.1; licences beside them):

- Unbounded (fonts.google.com): Unbounded-Bold.ttf, Unbounded-ExtraBold.ttf
- Manrope (fonts.google.com): Manrope-Regular/Medium/SemiBold/Bold/ExtraBold.ttf
- Medeo Sans 1.0.0-rc.3 (medeo-font on npm, github.com/DNFDEVS/medeo-font): static instances of
  the variable font, used only for the Kazakh interface. MedeoSans-Medium/SemiBold/Bold/ExtraBold
  are at optical size 14; MedeoSans-DisplayBold/DisplayExtraBold at optical size 32.

Registered in Info.plist and project.yml (UIAppFonts). Unbounded and Manrope lack several Kazakh
letters (and Manrope lacks ₸), so Kazakh maps each face to Medeo Sans (Typography.swift,
`Font.brandFace`). If a font is missing, the app falls back to the system font and still builds.

Regenerating the Medeo files: `npm pack medeo-font`, unpack, then with fontTools
`instancer.instantiateVariableFont(font, {"wght": 700, "opsz": 32})` and rename the family
and PostScript name (MedeoSans-<Style>).
