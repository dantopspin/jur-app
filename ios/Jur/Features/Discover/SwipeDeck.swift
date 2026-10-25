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
    /// The top card rising off the table before a like with a note flies.
    @State private var lifted: CGFloat = 1
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
                ProfileCardView(card: card, compact: true, showsTips: top)
                    // The next card waits slightly smaller, its lower edge peeking out under the
                    // top one, and rises into place as the top one is dragged away.
                    .scaleEffect(top ? lifted : 0.95 + 0.05 * progress, anchor: .bottom)
                    .brightness(top ? 0 : -0.03 * (1 - progress))
                    .offset(x: top ? drag.width : 0, y: top ? drag.height * 0.2 + lift : 10 * (1 - progress))
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
                    fly(.like, velocity: v.velocity)
                } else if w < -line || thrown < -line * 2.5 {
                    fly(.pass, velocity: v.velocity)
                } else {
                    settle(velocity: v.velocity)
                }
            }
    }

    /// Below this a throw is topped up, so a slow drag past the line still leaves briskly.
    private let minThrowSpeed: CGFloat = 1400

    /// Let go before the line: the card returns to the middle, starting at the speed it was
    /// moving towards the middle (or away from it), instead of from a standstill.
    private func settle(velocity: CGSize) {
        let length = (drag.width * drag.width + drag.height * drag.height).squareRoot()
        // The finger's speed along the way back to the middle (positive = already heading home).
        let towardsHome = length > 0 ? -(velocity.width * drag.width + velocity.height * drag.height) / length : 0
        withAnimation(Motion.adaptive(Motion.settle(speed: towardsHome, distance: length))) { drag = .zero }
    }

    /// Sends the top card off screen in the decision's direction, then commits it.
    /// `velocity` is the finger's at release; buttons and VoiceOver pass none and get a brisk default.
    private func fly(_ kind: SwipeKind, note: String? = nil, velocity: CGSize? = nil) {
        guard !leaving, !cards.isEmpty else { return }
        if reduceMotion {
            drag = .zero
            onCommit(kind, note)
            return
        }
        leaving = true
        if kind == .like, note != nil {
            liftOff(note: note)
            return
        }
        var target = drag
        var up: CGFloat = 0
        let animation: Animation
        switch kind {
        case .like, .pass:
            let side: CGFloat = kind == .like ? 1 : -1
            target.width = 700 * side
            let distance = target.width - drag.width
            let thrown = (velocity?.width ?? 0) * side
            // Keep the throw's angle: thrown up-and-right, the card keeps going up-and-right.
            if let velocity, thrown > 0 {
                target.height = drag.height + min(max(distance * velocity.height / velocity.width, -400), 400)
            }
            animation = Motion.throwOut(speed: max(thrown, minThrowSpeed) * side, distance: distance)
        case .super:
            target = .zero
            up = -1100
            animation = Motion.throwOut(speed: -minThrowSpeed, distance: up - lift)
        }
        withAnimation(animation) {
            drag = target
            lift = up
        } completion: {
            land(kind, note: note)
        }
    }

    /// A like with a note: once the note sheet has gone, the card lifts off the table with
    /// a light tap, then flies up and away to the right, like a letter sent.
    private func liftOff(note: String?) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Motion.bouncy) {
                lifted = 1.04
                lift = -24
            }
            Haptics.tick()
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(Motion.liftOff) {
                drag = CGSize(width: 520, height: 0)
                lift = -900
            } completion: {
                land(.like, note: note)
            }
        }
    }

    /// Resets the offsets and removes the card in the same update, so the next card never
    /// sees the old offset.
    private func land(_ kind: SwipeKind, note: String?) {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            drag = .zero
            lift = 0
            lifted = 1
        }
        leaving = false
        onCommit(kind, note)
    }
}
