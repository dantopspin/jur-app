// Spacing (4 pt grid), corner radii and layout constants. Raw numbers in views
// are a bug: pick the nearest token.
import SwiftUI

enum Sp {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16   // screen margin, card padding
    static let xl: CGFloat = 24   // between sections
    static let xxl: CGFloat = 32
}

/// Concentric rule: inner radius = outer radius − padding (minimum 8).
/// Documented exceptions: the 7 pt Settings-style icon tile (system size) and stamps (10, physical objects).
enum Radius {
    static let sm: CGFloat = 8    // icon tiles, thumbnails
    static let md: CGFloat = 12   // inputs, inner cards, photos in cards
    static let lg: CGFloat = 20   // content cards
    static let xl: CGFloat = 28   // sheets, full-bleed modals
    /// Chat bubbles (and media in them): rounder than cards, like every messenger.
    static let bubble: CGFloat = 18
}

enum Layout {
    static let margin: CGFloat = 16
    static let rowMin: CGFloat = 44
    static let buttonHeight: CGFloat = 50
    static let buttonHeightCompact: CGFloat = 44
    /// Room under scrolling content for a bar that floats over it (Discover's actions, a sheet's footer).
    static let floatingBarClearance: CGFloat = 120
}

/// Fixed artwork sizes only (mark, tiles). SF Symbols next to text take the text's font instead.
enum IconSize {
    static let inline: CGFloat = 13
    static let row: CGFloat = 17
    static let toolbar: CGFloat = 22
    static let action: CGFloat = 28
    static let hero: CGFloat = 44
}

extension View {
    /// A card surface: white (or night) on the chalk ground, continuous corners, no border.
    func qCard(padding: CGFloat = Sp.lg, radius: CGFloat = Radius.lg) -> some View {
        self.padding(padding)
            .background(Color.q.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    /// The one elevation, for things that float over content: the swipe card, floating
    /// action buttons, the date ticket. Cards sitting on the chalk ground get no shadow.
    func qElevated() -> some View {
        shadow(color: Color.q.blueNight.opacity(0.12), radius: 16, y: 6)
    }
}
