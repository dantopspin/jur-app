// Three first-session hints on Discover, shown once each (Apple's TipKit remembers):
// how to decide, that a like can carry a note, and that a card has more photos.
import SwiftUI
import TipKit

/// "Смахните вправо — лайк, влево — пропуск." Gone after the first decision.
struct SwipeTip: Tip {
    var title: Text { Text(t("tips.swipeTitle")) }
    var message: Text? { Text(t("tips.swipeBody")) }
    var image: Image? { Image(systemName: "hand.draw") }
}

/// "Удерживайте ♥ — лайк с запиской." After the first like, until a note is sent.
struct NoteTip: Tip {
    static let liked = Event(id: "liked")
    var title: Text { Text(t("tips.noteTitle")) }
    var message: Text? { Text(t("tips.noteBody")) }
    var image: Image? { Image(systemName: "text.bubble") }
    var rules: [Rule] { #Rule(Self.liked) { $0.donations.count >= 1 } }
}

/// "Нажмите на фото справа, чтобы листать." The first card with more than one photo.
struct PhotosTip: Tip {
    @Parameter static var cardHasMore: Bool = false
    var title: Text { Text(t("tips.photosTitle")) }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] { #Rule(Self.$cardHasMore) { $0 == true } }
}

enum Hints {
    /// Once at launch. Tips appear at most one at a time.
    static func configure() {
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}
