// Small touch feedback. The big moments (match, super like, check-in) add sound.
import UIKit

@MainActor
enum Haptics {
    /// Chips, choices, toggles.
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    /// A swipe crosses its threshold, a card flips.
    static func bump() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    /// Long-press menus.
    static func knock() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
