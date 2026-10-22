Brand fonts (SIL Open Font License 1.1, from fonts.google.com; licences beside them):

- Unbounded: Unbounded-Bold.ttf, Unbounded-ExtraBold.ttf
- Manrope: Manrope-Regular.ttf, Manrope-Medium.ttf, Manrope-SemiBold.ttf, Manrope-Bold.ttf, Manrope-ExtraBold.ttf

Registered in Info.plist (UIAppFonts). Neither family covers all Kazakh letters, so the
Kazakh interface uses the system faces (Typography.swift, qFont). If they're missing, the app
falls back to the system font and still builds.
