// Shareable images: a boarding pass people post to Stories or send in a chat.
// Two kinds: the invite (your code, "from you to them") and an event you're going to.
// Drawn at 360×640 points and rendered at 3× = 1080×1920, the Stories size.
// Always light, always the same text size, so the picture looks the same for everyone.
import SwiftUI

struct SharePass: View {
    struct Field: Identifiable {
        let label: String
        let value: String
        var mono = false
        var id: String { label }
    }

    /// Small label above the title: "ПРИГЛАШЕНИЕ" / "ПОСАДОЧНЫЙ".
    let kind: String
    let title: String
    let fields: [Field]
    /// The stub: a big code (invite) or seats left (event).
    let stubLabel: String
    let stubValue: String
    let cta: String

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.q.blueNight
            Horizon(far: Color.q.blueDeep, near: Color.q.boardShade)
                .frame(height: 150)

            VStack(spacing: 0) {
                Lockup(size: 26, onBlue: true)
                    .padding(.top, Sp.xxl + Sp.xl)
                Spacer(minLength: 24)
                ticket
                    .padding(.horizontal, Sp.xl)
                Spacer(minLength: 24)
                Text(cta)
                    .font(.qFont("Manrope-ExtraBold", size: 15, relativeTo: .callout, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, Sp.xxl)
                    .padding(.bottom, Sp.xxl * 2)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Sp.md) {
                HStack(spacing: Sp.xs) {
                    MarkView(size: 16, color: Color.q.clayDeep)
                    Text(kind.uppercased()).qText(.overline).foregroundStyle(Color.q.clayDeep)
                        .lineLimit(1)
                }
                Text(title).qText(.title2).foregroundStyle(Color.q.ink)
                    .lineLimit(3).minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: Sp.md) {
                        ForEach(rows[i]) { field($0) }
                    }
                }
            }
            .padding(Sp.lg)

            Perforation()
                .stroke(Color.q.line, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(height: 2)
                .padding(.horizontal, Sp.md)

            HStack(alignment: .firstTextBaseline) {
                Text(stubLabel.uppercased()).qText(.label).foregroundStyle(Color.q.muted).lineLimit(1)
                Spacer(minLength: Sp.sm)
                Text(stubValue)
                    .font(.qFont("Unbounded-ExtraBold", size: 28, relativeTo: .title, weight: .heavy, latinOnly: true))
                    .monospacedDigit()
                    .foregroundStyle(Color.q.blue)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            .padding(Sp.lg)
        }
        .background(Color.q.card, in: PassShape())
    }

    /// Fields two per row.
    private var rows: [[Field]] {
        stride(from: 0, to: fields.count, by: 2).map { Array(fields[$0..<min($0 + 2, fields.count)]) }
    }

    private func field(_ f: Field) -> some View {
        VStack(alignment: .leading, spacing: Sp.xxs) {
            Text(f.label.uppercased()).qText(.label).foregroundStyle(Color.q.muted).lineLimit(1)
            Text(f.value).qText(f.mono ? .number : .callout).foregroundStyle(Color.q.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The finished picture (nil only if rendering fails).
    @MainActor
    func render() -> UIImage? {
        let r = ImageRenderer(content: self)
        r.scale = 3
        r.proposedSize = ProposedViewSize(Self.size)
        return r.uiImage
    }
}

/// A card with a notch on each side where the stub tears off (the stub sits at the bottom).
private struct PassShape: Shape {
    var stubHeight: CGFloat = 66
    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: Radius.lg, style: .continuous)
        let y = rect.maxY - stubHeight
        let r: CGFloat = 10
        p = p.subtracting(Path(ellipseIn: CGRect(x: rect.minX - r, y: y - r, width: r * 2, height: r * 2)))
        p = p.subtracting(Path(ellipseIn: CGRect(x: rect.maxX - r, y: y - r, width: r * 2, height: r * 2)))
        return p
    }
}

private struct Perforation: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: the two passes

extension SharePass {
    /// "From Daniyal to you": your invite code on a pass.
    static func invite(from name: String, code: String) -> SharePass {
        SharePass(
            kind: t("pass.invite"),
            title: t("pass.inviteTitle"),
            fields: [
                Field(label: t("pass.from"), value: name),
                Field(label: t("pass.to"), value: t("pass.you")),
            ],
            stubLabel: t("pass.code"), stubValue: code,
            cta: t("pass.cta"))
    }

    static func event(_ e: EventItem, sport: String) -> SharePass {
        SharePass(
            kind: t("pass.departure"),
            title: e.title,
            fields: [
                Field(label: t("pass.when"), value: Fmt.dayTime(e.start), mono: true),
                Field(label: t("pass.sport"), value: sport),
                Field(label: t("pass.gate"), value: e.meetingPoint),
                Field(label: t("pass.going"), value: "\(e.goingCount)/\(e.capacity)", mono: true),
            ],
            stubLabel: t("pass.seatsLeft"), stubValue: "\(e.spotsLeft)",
            cta: t("pass.cta"))
    }
}

/// A share button that renders the pass once, then offers picture + text together.
/// Falls back to text only if the picture can't be made.
struct SharePassButton<Content: View>: View {
    let pass: SharePass
    let text: String
    @ViewBuilder let label: () -> Content
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: Image(uiImage: image), message: Text(text),
                          preview: SharePreview(pass.title, image: Image(uiImage: image))) { label() }
            } else {
                ShareLink(item: text) { label() }
            }
        }
        .task(id: pass.title + pass.stubValue) { image = pass.render() }
    }
}
