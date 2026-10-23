// The passport page: the back of a profile. Felt ground, member №, and stamps
// for things you did (badges). Stamps are earned by showing up, never bought.
import SwiftUI

enum StampKind: String, CaseIterable, Identifiable, Hashable {
    case founding, verified, first_step, showed_up, regular, host, winter, summer
    var id: String { rawValue }
    var label: String { t("stamp.\(rawValue)") }
}

struct StampData: Identifiable, Hashable {
    let kind: StampKind
    /// A small second line: "0042", "19:00", "Шымбулак"…
    var detail: String?
    var id: StampKind { kind }
}

struct Stamp: View {
    let data: StampData
    var city: String?
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 92

    private var tilt: Double {
        // Stable per kind, so stamps don't wobble between renders.
        let tilts: [StampKind: Double] = [.founding: -8, .verified: 5, .first_step: -3, .showed_up: 7,
                                          .regular: -6, .host: 4, .winter: -4, .summer: 3]
        return tilts[data.kind] ?? 0
    }

    private var ink: Color {
        switch data.kind {
        case .verified: Color.q.stampGreen
        case .first_step, .regular, .host: Color.q.feltLabel
        default: Color.q.stampBlue
        }
    }

    var body: some View {
        content
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .rotationEffect(.degrees(tilt))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([data.kind.label, data.detail].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder private var content: some View {
        switch data.kind {
        case .founding:
            circle(double: true) {
                small(data.kind.label)
                big(data.detail ?? "")
                if let city { small(city) }
            }
        case .first_step, .host:
            circle(double: false) {
                big(data.kind.label.uppercased(), size: 13)
                if let d = data.detail { detail(d) }
            }
        case .regular:
            circle(double: false) {
                small(data.kind.label)
                if let d = data.detail { big(d, size: 14) }
            }
        case .verified:
            rect(style: .solid) {
                Image(systemName: "checkmark").font(.q(.headline).weight(.heavy))
                small(data.kind.label)
            }
        case .showed_up:
            rect(style: .dashed) {
                small(data.kind.label)
                if let d = data.detail { big(d, size: 14) }
            }
        case .winter, .summer:
            rect(style: .double) {
                if data.kind == .winter {
                    Peaks().stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        .frame(width: size * 0.44, height: size * 0.13)
                }
                big(data.kind.label.uppercased(), size: 14)
                if let d = data.detail { detail(d) }
            }
        }
    }

    // MARK: shapes

    private func circle<C: View>(double: Bool, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: Sp.xxs) { c() }
            .padding(Sp.sm)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(ink, lineWidth: 2))
            .overlay { if double { Circle().inset(by: 4).stroke(ink, lineWidth: 1) } }
    }

    private enum Border { case solid, dashed, double }

    private func rect<C: View>(style: Border, @ViewBuilder _ c: () -> C) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)   // stamp exception, see Radius
        return VStack(spacing: Sp.xxs) { c() }
            .padding(Sp.sm)
            .frame(width: size, height: size * 0.76)
            .overlay(shape.stroke(ink, style: StrokeStyle(lineWidth: 2, dash: style == .dashed ? [5, 3] : [])))
            .overlay { if style == .double { shape.inset(by: 4).stroke(ink, lineWidth: 1) } }
    }

    /// Uppercase stamp lettering: the label face at 11 pt, tracked tighter so words fit the ring.
    private func small(_ s: String) -> some View {
        Text(s.uppercased()).font(.q(.label)).tracking(0.5)
            .lineLimit(2).minimumScaleFactor(0.85)
    }
    private func detail(_ s: String) -> some View {
        Text(s).font(.q(.label)).lineLimit(1).minimumScaleFactor(0.85)
    }
    private func big(_ s: String, size: CGFloat = 15) -> some View {
        Text(s).font(.qFont("Unbounded-ExtraBold", size: size, relativeTo: .headline, weight: .heavy))
            .monospacedDigit().lineLimit(2).minimumScaleFactor(0.7)
    }
}

/// An empty stamp slot: a dashed ring waiting to be filled.
private struct StampSlot: View {
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 92
    var body: some View {
        Circle()
            .stroke(Color.q.feltLine, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small two-peak mountain for the winter stamp.
private struct Peaks: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(0, 1), (0.25, 0.25), (0.4, 0.65), (0.58, 0), (0.77, 0.6), (1, 1)]
        var p = Path()
        p.addLines(pts.map { CGPoint(x: r.minX + $0.0 * r.width, y: r.minY + $0.1 * r.height) })
        return p
    }
}

struct PassportPage: View {
    let name: String
    let memberNo: String          // "№0042"
    let city: String
    let since: String             // "окт 2026"
    let departures: Int
    let stamps: [StampData]
    var photo: URL?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Sp.md), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            HStack {
                Text(t("passport.title")).qText(.overline).foregroundStyle(Color.q.feltLabel)
                Spacer()
                MarkView(size: 24, color: Color.q.feltLabel)
            }
            HStack(spacing: Sp.md) {
                QPhoto(url: photo, size: .thumb, placeholder: Color.q.blueDeep)
                    .frame(width: 88, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Sp.sm) {
                    Text(name).qText(.title2).lineLimit(2)
                    // Labelled, so it reads as the passport's serial number, not a rank.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t("passport.number")).qText(.overline).foregroundStyle(Color.q.feltLabel)
                        Text(memberNo).qText(.display).minimumScaleFactor(0.6).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(alignment: .top) {
                field(t("passport.city"), city)
                field(t("passport.since"), since)
                field(t("passport.departures"), "\(departures)")
            }
            .padding(.vertical, Sp.md)
            .overlay(alignment: .top) { Rectangle().fill(Color.q.feltLine).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.q.feltLine).frame(height: 1) }

            Text(t("passport.stamps")).qText(.overline).foregroundStyle(Color.q.feltLabel)
            if stamps.isEmpty {
                LazyVGrid(columns: columns, spacing: Sp.md) {
                    ForEach(0..<3, id: \.self) { _ in StampSlot() }
                }
                Text(t("passport.empty")).qText(.callout).foregroundStyle(Color.q.feltMuted)
            } else {
                LazyVGrid(columns: columns, spacing: Sp.md) {
                    ForEach(stamps) { s in Stamp(data: s, city: city) }
                }
                Text(t("passport.note")).qText(.caption).foregroundStyle(Color.q.feltMuted)
            }
        }
        .foregroundStyle(Color.q.feltInk)
        .padding(Sp.lg)
        .background(Color.q.feltGround, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Sp.xxs) {
            Text(label).qText(.label).foregroundStyle(Color.q.feltMuted)
            Text(value).qText(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        PassportPage(name: "Айгерім", memberNo: "№0042", city: "Алматы", since: "окт 2026", departures: 6, stamps: [
            .init(kind: .founding, detail: "0042"), .init(kind: .verified), .init(kind: .first_step),
            .init(kind: .showed_up, detail: "19:00"), .init(kind: .regular, detail: "×5"), .init(kind: .winter, detail: "Шымбулак"),
        ])
        .padding()
    }
    .background(Color.q.bg)
}
