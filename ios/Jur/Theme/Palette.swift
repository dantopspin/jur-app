// JÜR colours, light and dark. Values mirror the "JÜR" design system tokens
// (and the old src/lib/theme.ts). Every colour adapts to the appearance by itself.
import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

private func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
}

private func fixed(_ hex: UInt32) -> Color { Color(UIColor(hex: hex)) }

/// Use as `Color.q.ink`, `.foregroundStyle(Color.q.muted)`.
struct QColors {
    // grounds
    let bg = dynamic(0xF7F4EE, 0x0E1724)        // chalk page
    let card = dynamic(0xFFFFFF, 0x172333)      // cards, sheets, inputs
    let line = dynamic(0xE4DDD0, 0x2A3A4F)      // hairlines, tracks
    // text
    let ink = dynamic(0x1B2430, 0xF3EFE7)
    let inkSoft = dynamic(0x474C55, 0xC8CDD5)   // secondary text
    let muted = dynamic(0x5B606A, 0xA3AAB5)     // meta, timestamps
    let hint = dynamic(0x676C75, 0x8E96A2)      // placeholders, chevrons
    // brand
    let blue = fixed(0x1F5FA0)                  // fills: buttons, like, match (white text 6.6:1)
    let blueText = dynamic(0x1F5FA0, 0x8DB9EC)  // blue as text or icon
    let blueDeep = dynamic(0x184C82, 0x123A64)
    let blueNight = dynamic(0x123A64, 0x0B2440)
    let blueMist = fixed(0xDCE7F3)              // secondary text on blue
    let blueTint = dynamic(0xE6EEF7, 0x1A3150)  // banners, quotes, tinted buttons
    let gold = fixed(0xE2A63B)                  // fills under dark text, the mark on blue. Never text on light grounds.
    let onGold = fixed(0x1B2430)
    let clay = dynamic(0xA8452A, 0xE58A6B)      // pass, warm accent
    let clayDeep = dynamic(0x8A3A22, 0xEE9C80)  // small uppercase labels
    // states
    let good = dynamic(0x256B42, 0x5CC28A)
    let goodTint = dynamic(0xE5F2EA, 0x163325)
    let danger = dynamic(0xB3261E, 0xFF7A6E)
    let dangerTint = dynamic(0xFBEAE8, 0x3A1F22)
    let overlay = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.6) : UIColor(hex: 0x123A64, alpha: 0.55) })
    // felt: a physical material, the same in both modes
    let feltGround = fixed(0xEFE6D6)
    let feltInk = fixed(0x1B2430)
    let feltLine = fixed(0xD9CBB2)
    let feltLabel = fixed(0x8A3A22)
    let feltMuted = fixed(0x5B5240)             // 6.2:1 on felt
    // the departure board and the Pro cover: night-blue objects, the same in both modes
    let boardGround = fixed(0x123A64)
    let boardRidge = fixed(0x184C82)
    let boardShade = fixed(0x0B2440)
    let boardRule = fixed(0xDCE7F3).opacity(0.18)
    let coverGround = fixed(0x123A64)
    // stamp ink on felt
    let stampBlue = fixed(0x1F5FA0)
    let stampGreen = fixed(0x256B42)
}

extension Color {
    static let q = QColors()
}

extension ShapeStyle where Self == Color {
    static var qInk: Color { Color.q.ink }
    static var qMuted: Color { Color.q.muted }
    static var qBlueText: Color { Color.q.blueText }
}
