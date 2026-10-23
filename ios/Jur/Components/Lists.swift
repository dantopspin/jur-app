// Lists and forms in the brand: chalk ground, cards in the card colour (not the system's
// grey in dark mode), section titles as small tracked labels, one chevron.
import SwiftUI

/// `List` with the brand ground and row cards.
struct QList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List { Group { content }.listRowBackground(Color.q.card).listRowSeparatorTint(Color.q.line) }
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
    }
}

/// `Form` with the brand ground and row cards.
struct QForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { Group { content }.listRowBackground(Color.q.card).listRowSeparatorTint(Color.q.line) }
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
    }
}

/// A list section with a brand title (the small uppercase label used across the app).
struct QSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section { content } header: { QSectionHeader(title) }
    }
}

/// Section title: 11 pt tracked uppercase, muted.
struct QSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).qText(.label).foregroundStyle(Color.q.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The trailing chevron on rows that open something.
struct QChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.q(.footnote).weight(.semibold))
            .foregroundStyle(Color.q.hint)
            .accessibilityHidden(true)
    }
}
