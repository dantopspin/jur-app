// One way to present sheets: drag indicator, 28 pt corners, chalk ground.
import SwiftUI

extension View {
    /// Apply inside the sheet's content: `.sheet { Thing().qSheet(detents: [.medium]) }`.
    func qSheet(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self.presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.xl)
            .presentationBackground(Color.q.bg)
    }
}

/// The close button for full-screen covers (Pro, the Pro welcome): a round, bordered `xmark`.
struct CloseButton: View {
    let action: () -> Void
    var onBlue = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.q(.footnote).weight(.bold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(onBlue ? .white : Color.q.blueText)
        .accessibilityLabel(t("common.close"))
    }
}
