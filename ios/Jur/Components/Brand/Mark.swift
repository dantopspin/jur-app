// Brand primitives: the mark (two strides curling into a heart; in Kazakhstan also
// read as ram horns, қошқар мүйіз), the horizon ridge and the lockup.
// Geometry matches the design system's SVG (a 100-unit box).
import SwiftUI

/// One horn of the mark. Both start at the heart's point, so trimming 0→1 draws them curling up.
struct HornShape: Shape {
    var right = false
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * s, oy = rect.midY - 50 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + (right ? 100 - x : x) * s, y: oy + y * s)
        }
        var path = Path()
        path.move(to: p(50, 88))
        path.addCurve(to: p(14, 38), control1: p(30, 70), control2: p(14, 56))
        path.addCurve(to: p(40, 18), control1: p(14, 22), control2: p(28, 14))
        path.addCurve(to: p(40, 38), control1: p(50, 22), control2: p(50, 36))
        path.addCurve(to: p(33, 30), control1: p(34, 39), control2: p(30, 34))
        return path
    }
}

struct MarkView: View {
    var size: CGFloat = 48
    var color: Color = Color.q.gold
    /// Draw the horns in (once, on appear).
    var animate = false
    @State private var progress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat {
        let units: CGFloat = size < 24 ? 11 : size < 48 ? 9 : 7
        return units * size / 100
    }

    var body: some View {
        ZStack {
            HornShape().trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            HornShape(right: true).trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("JÜR")
        .onAppear {
            guard animate, !reduceMotion else { return }
            progress = 0
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.6)) { progress = 1 }
        }
    }
}

/// Loading: the horns curl in and out, instead of a spinner.
struct MarkLoader: View {
    var size: CGFloat = 44
    var color: Color = Color.q.blueText
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width = 9 * size / 100
        ZStack {
            HornShape().trim(from: 0, to: on ? 1 : 0.05)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            HornShape(right: true).trim(from: 0, to: on ? 1 : 0.05)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { on = true; return }
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.7).repeatForever(autoreverses: true)) { on = true }
        }
        .accessibilityElement()
        .accessibilityLabel(t("common.loading"))
    }
}

/// The horizon: the Alatau skyline, the brand's landscape. Drawn in a 390×120 box and
/// stretched to fit. `far` is the jagged ridge, `near` the softer foothills in front.
struct RidgeShape: Shape {
    enum Layer { case far, near, line }
    var layer: Layer = .far

    private static let farRaw: [(CGFloat, CGFloat)] = [(0, 78), (28, 70), (52, 74), (80, 52), (98, 60), (122, 34), (140, 44), (156, 38),
                                 (182, 58), (210, 46), (240, 18), (258, 30), (276, 26), (300, 48), (330, 38),
                                 (356, 52), (390, 44)]
    static let far: [CGPoint] = farRaw.map { CGPoint(x: $0.0, y: $0.1) }
    private static let nearRaw: [(CGFloat, CGFloat)] = [(0, 96), (36, 86), (70, 92), (108, 76), (146, 88), (186, 80), (226, 92),
                                  (266, 74), (306, 86), (346, 80), (390, 88)]
    static let near: [CGPoint] = nearRaw.map { CGPoint(x: $0.0, y: $0.1) }

    func path(in rect: CGRect) -> Path {
        let pts = layer == .near ? Self.near : Self.far
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x / 390 * rect.width, y: rect.minY + p.y / 120 * rect.height)
        }
        var path = Path()
        if layer == .line {
            path.addLines(pts.map(map))
        } else {
            path.move(to: map(CGPoint(x: 0, y: 120)))
            for p in pts { path.addLine(to: map(p)) }
            path.addLine(to: map(CGPoint(x: 390, y: 120)))
            path.closeSubpath()
        }
        return path
    }
}

/// Snow on the two highest peaks (same 390×120 box as RidgeShape).
struct SnowCaps: Shape {
    func path(in rect: CGRect) -> Path {
        let caps: [[(CGFloat, CGFloat)]] = [
            [(229, 29), (240, 18), (251, 28), (246, 26), (241, 31), (236, 26)],
            [(113, 43), (122, 34), (131, 42), (127, 40), (122, 44), (118, 40)],
        ]
        var path = Path()
        for cap in caps {
            path.addLines(cap.map { pt in CGPoint(x: rect.minX + pt.0 / 390 * rect.width, y: rect.minY + pt.1 / 120 * rect.height) })
            path.closeSubpath()
        }
        return path
    }
}

/// The full horizon for blue surfaces: far ridge, snow, foothills. One per surface.
struct Horizon: View {
    var far: Color = Color.q.blueDeep
    var near: Color = Color.q.blueNight
    var snow = true

    var body: some View {
        ZStack {
            RidgeShape(layer: .far).fill(far)
            if snow { SnowCaps().fill(.white.opacity(0.92)) }
            RidgeShape(layer: .near).fill(near)
        }
        .accessibilityHidden(true)
    }
}

/// Mark + the Latin wordmark, used in every market and language.
struct Lockup: View {
    var size: CGFloat = 22
    var onBlue = false

    var body: some View {
        HStack(spacing: size * 0.3) {
            MarkView(size: size * 1.4, color: onBlue ? Color.q.gold : Color.q.blueText)
            Wordmark(size: size, ink: onBlue ? .white : Color.q.ink, dots: onBlue ? Color.q.gold : Color.q.blueText)
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("JÜR")
        .accessibilityAddTraits(.isHeader)
    }
}
