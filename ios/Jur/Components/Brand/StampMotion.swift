// The moment a stamp lands, shared by every place one does (passport issued, check-in,
// a match, a new stamp in Me): it comes down big and turned, hits with a little rebound,
// the card under it gives and springs back, and gold dust flies off. Under Reduce Motion
// it simply fades in; the haptics stay.
import SwiftUI

extension View {
    /// Big and turned until `landed`, then pressed onto the page (use with `Motion.slam`).
    func stampSlam(_ landed: Bool, from scale: CGFloat = 2.4, turn: Double = -28) -> some View {
        modifier(StampSlam(landed: landed, scale: scale, turn: turn))
    }

    /// The card giving a little under a landing stamp.
    func stampDip(_ dipping: Bool) -> some View {
        modifier(StampDip(dipping: dipping))
    }
}

private struct StampSlam: ViewModifier {
    let landed: Bool
    let scale: CGFloat
    let turn: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(landed || reduceMotion ? 1 : scale)
            .rotationEffect(.degrees(landed || reduceMotion ? 0 : turn))
            .opacity(landed ? 1 : 0)
    }
}

private struct StampDip: ViewModifier {
    let dipping: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(dipping ? 0.985 : 1)
            .offset(y: dipping ? 4 : 0)
    }
}

enum StampMoment {
    /// Lands a stamp: `land` flips the stamp's state, `dip` the card's, `dust` fires the
    /// burst. Thump on impact, then success.
    @MainActor
    static func play(land: @escaping () -> Void, dip: @escaping (Bool) -> Void, dust: @escaping () -> Void,
                     success: Bool = true) async {
        withAnimation(Motion.adaptive(Motion.slam)) { land() }
        try? await Task.sleep(for: .milliseconds(140))
        Haptics.thump()
        dust()
        if !Motion.reduceMotion {
            withAnimation(Motion.dip) { dip(true) }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(Motion.dipBack) { dip(false) }
        }
        if success { Haptics.success() }
    }
}

/// A small burst of gold specks, fired each time `trigger` changes. Nothing under Reduce Motion.
struct DustBurst: View {
    let trigger: Int
    @State private var progress: CGFloat = 0
    @State private var fired = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let specks: [(dx: CGFloat, dy: CGFloat, size: CGFloat, color: Color)] = (0..<16).map { i in
        let angle = Double(i) / 16 * 2 * .pi + (i.isMultiple(of: 2) ? 0.2 : -0.1)
        let r = CGFloat(60 + (i * 37) % 70)
        let colors = [Color.q.gold, Color(red: 0.96, green: 0.82, blue: 0.54), .white]
        return (CGFloat(cos(angle)) * r, CGFloat(sin(angle)) * r - 20, CGFloat(4 + (i * 3) % 5), colors[i % 3])
    }

    var body: some View {
        ZStack {
            ForEach(Self.specks.indices, id: \.self) { i in
                let s = Self.specks[i]
                Circle()
                    .fill(s.color)
                    .frame(width: s.size, height: s.size)
                    .offset(x: s.dx * progress, y: s.dy * progress + 30 * progress * progress)
                    .opacity(fired ? Double(1 - progress) : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            progress = 0
            fired = true
            withAnimation(Motion.burst) { progress = 1 }
        }
    }
}

