// The Discover deck: the top card under the finger, the next one waiting underneath.
// The drag lives here, not in DiscoverView, so a drag frame redraws only the deck.
import SwiftUI

/// A decision asked for from outside the deck (the round buttons, the note sheet,
/// VoiceOver): the deck flings its top card the same way a swipe would.
struct DeckFling: Equatable {
    let kind: SwipeKind
    var note: String?
    let id = UUID()
}

struct SwipeDeck: View {
    /// Top card first; the deck shows two.
    let cards: [ProfileCard]
    @Binding var dragging: Bool
    @Binding var fling: DeckFling?
    var returningId: UUID?
    var returningEdge: Edge = .leading
    let onCommit: (SwipeKind, String?) -> Void
    let onNote: (ProfileCard) -> Void

    @State private var drag: CGSize = .zero
    @State private var lift: CGFloat = 0
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a card must travel for the swipe to count.
    private let line: CGFloat = 120
    /// -1 past the pass line, 1 past the like line, 0 in between (drives the haptic).
    private var past: Int { drag.width > line ? 1 : drag.width < -line ? -1 : 0 }
    private var progress: CGFloat { min(abs(drag.width) / line, 1) }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(cards.prefix(2).enumerated()), id: \.element.id) { index, card in
                let top = index == 0
                ProfileCardView(card: card, compact: true)
                    // The next card waits slightly smaller and rises as the top one is dragged away.
                    .scaleEffect(top ? 1 : 0.95 + 0.05 * progress, anchor: .top)
                    .brightness(top ? 0 : -0.03 * (1 - progress))
                    .offset(x: top ? drag.width : 0, y: top ? drag.height * 0.2 + lift : 0)
                    .rotationEffect(.degrees(top ? rotation : 0), anchor: .bottom)
                    .overlay(alignment: .top) { if top { hint } }
                    .zIndex(top ? 1 : 0)
                    .allowsHitTesting(top)
                    .accessibilityHidden(!top)
                    .transition(card.id == returningId ? .qReturn(from: returningEdge) : .qCardIn)
                    .gesture(swipe, including: top ? .all : .none)
                    .accessibilityAction(named: t("discover.like")) { fly(.like) }
                    .accessibilityAction(named: t("discover.pass")) { fly(.pass) }
                    .accessibilityAction(named: t("note.add")) { onNote(card) }
            }
        }
        .sensoryFeedback(.qThreshold, trigger: past) { _, new in new != 0 }
        .onChange(of: fling) { _, request in
            guard let request else { return }
            fling = nil
            fly(request.kind, note: request.note)
        }
    }

    /// Up to 8° while dragging; the fling itself keeps turning a little.
    private var rotation: Double {
        let r = Double(drag.width / 24)
        return leaving ? r : max(-8, min(8, r))
    }

    @ViewBuilder private var hint: some View {
        if abs(drag.width) > 40 {
            Text(drag.width > 0 ? t("discover.like") : t("discover.pass"))
                .qText(.title3)
                .foregroundStyle(drag.width > 0 ? Color.q.blue : Color.q.clay)
                .padding(.horizontal, Sp.md).padding(.vertical, Sp.sm)
                .background(Color.q.card, in: Capsule())
                .scaleEffect(past != 0 && !reduceMotion ? 1.08 : 1)
                .animation(Motion.snappy, value: past)
                .padding(.top, Sp.xxl)
                .opacity(progress)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                guard !leaving else { return }
                if !dragging { dragging = true; Haptics.prepare() }
                drag = v.translation
            }
            .onEnded { v in
                dragging = false
                guard !leaving else { return }
                let w = v.translation.width
                let thrown = v.predictedEndTranslation.width
                // A quick flick counts even if the finger didn't travel the whole way.
                if w > line || thrown > line * 2.5 {
                    fly(.like)
                } else if w < -line || thrown < -line * 2.5 {
                    fly(.pass)
                } else {
                    withAnimation(Motion.adaptive(Motion.follow)) { drag = .zero }
                }
            }
    }

    /// Sends the top card off screen in the decision's direction, then commits it.
    private func fly(_ kind: SwipeKind, note: String? = nil) {
        guard !leaving, !cards.isEmpty else { return }
        if reduceMotion {
            drag = .zero
            onCommit(kind, note)
            return
        }
        leaving = true
        var target = drag
        var up: CGFloat = 0
        switch kind {
        case .like: target.width = 700
        case .pass: target.width = -700
        case .super: target = .zero; up = -1100
        }
        withAnimation(Motion.exit) {
            drag = target
            lift = up
        } completion: {
            // Reset the offset and remove the card in the same update, so the next card
            // never sees the old offset.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                drag = .zero
                lift = 0
            }
            leaving = false
            onCommit(kind, note)
        }
    }
}
