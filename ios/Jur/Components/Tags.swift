// Tags (read-only labels) and chips (selectable).
import SwiftUI

struct QTag: View {
    enum Tone { case blue, neutral, gold, solid, clay, good }
    let label: String
    var tone: Tone = .blue
    var systemImage: String?

    private var colors: (bg: Color, fg: Color) {
        switch tone {
        case .blue: (Color.q.blueTint, Color.q.blueText)
        case .neutral: (Color.q.line, Color.q.inkSoft)
        case .gold: (Color.q.gold, Color.q.onGold)
        case .solid: (Color.q.blue, .white)
        case .clay: (Color.q.dangerTint, Color.q.clay)
        case .good: (Color.q.goodTint, Color.q.good)
        }
    }

    var body: some View {
        HStack(spacing: Sp.xs) {
            if let systemImage { Image(systemName: systemImage).font(.q(.caption)) }
            Text(label).qText(.caption).lineLimit(1)
        }
        .foregroundStyle(colors.fg)
        .padding(.horizontal, Sp.sm)
        .padding(.vertical, Sp.xs)
        .background(colors.bg, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

struct QChip: View {
    let label: String
    var sub: String?
    var selected = false
    var onCard = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            VStack(spacing: 0) {
                Text(label).qText(.callout)
                if let sub { Text(sub).font(.q(.caption)).opacity(0.8) }
            }
            .foregroundStyle(selected ? .white : Color.q.ink)
            .padding(.horizontal, Sp.md)
            .padding(.vertical, Sp.sm)
            .frame(minHeight: 36)
            .background(selected ? Color.q.blue : (onCard ? Color.q.bg : Color.q.card), in: Capsule())
            .animation(Motion.snappy, value: selected)
            // 36 pt to the eye, 44 pt to the finger.
            .padding(.vertical, Sp.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.qPressCard)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wrapping layout for chips and tags. Chips already carry 4 pt of invisible hit area
/// above and below, so chip rows use `FlowLayout(spacing: Sp.xs)`.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = Sp.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = size(of: v, maxWidth: width)
            if x > 0, x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = size(of: v, maxWidth: bounds.width)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }

    /// A chip's natural size, but never wider than the row: at the largest text sizes a long
    /// label wraps inside its chip instead of running off the screen.
    private func size(of view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, ideal.width > maxWidth else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}
