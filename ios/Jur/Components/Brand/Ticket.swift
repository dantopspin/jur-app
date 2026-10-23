// "Ticket for two": how a suggested date looks in chat. A card with a perforated
// stub and two notches, like a real ticket.
import SwiftUI

/// A rounded rectangle with two half-circle notches cut where the stub begins.
struct TicketShape: Shape {
    var stubWidth: CGFloat = 74
    var cornerRadius: CGFloat = Radius.lg
    var notchRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let x = rect.maxX - stubWidth
        p = p.subtracting(Path(ellipseIn: CGRect(x: x - notchRadius, y: rect.minY - notchRadius, width: notchRadius * 2, height: notchRadius * 2)))
        p = p.subtracting(Path(ellipseIn: CGRect(x: x - notchRadius, y: rect.maxY - notchRadius, width: notchRadius * 2, height: notchRadius * 2)))
        return p
    }
}

struct DateTicket: View {
    enum Status { case pending(canAnswer: Bool), accepted, declined }
    let title: String           // "Лыжи · Шымбулак"
    let when: String            // "Сб 25 окт · 09:30"
    let place: String
    var state: Status = .pending(canAnswer: false)
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}

    private let stub: CGFloat = 74

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Sp.md) {
                Text(t("ticket.title")).qText(.overline).foregroundStyle(Color.q.clayDeep)
                Text(title).qText(.title3).foregroundStyle(Color.q.ink)
                HStack(alignment: .top) {
                    field(t("ticket.boarding"), when, mono: true)
                    field(t("ticket.from"), place)
                }
                answer
            }
            .padding(Sp.lg)

            Line()
                .stroke(Color.q.line, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(width: 2)
                .padding(.vertical, Sp.md)
                .accessibilityHidden(true)

            VStack(spacing: Sp.xs) {
                Text(t("ticket.seat")).qText(.label).foregroundStyle(Color.q.muted)
                Text(verbatim: "1/2").qText(.title2).monospacedDigit()
                    .foregroundStyle(Color.q.ink)
            }
            .frame(width: stub)
        }
        .background(Color.q.card, in: TicketShape(stubWidth: stub))
        .qElevated()
        .accessibilityElement(children: .contain)
    }

    /// Which of the answer's states is showing (the enum carries a flag, so it isn't Equatable).
    private var stateKey: Int {
        switch state {
        case .pending(let canAnswer): canAnswer ? 0 : 1
        case .accepted: 2
        case .declined: 3
        }
    }

    /// Answering morphs the buttons into the status tag.
    private var answer: some View {
        ZStack(alignment: .leading) { answerContent }
            .animation(Motion.adaptive(Motion.bouncy), value: stateKey)
    }

    @ViewBuilder private var answerContent: some View {
        switch state {
        case .pending(let canAnswer) where canAnswer:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Sp.sm) { answerButtons }
                VStack(spacing: Sp.sm) { answerButtons }
            }
            .transition(.opacity)
        case .accepted:
            QTag(label: t("date.accepted"), tone: .good, systemImage: "checkmark").transition(.qPop)
        case .declined:
            QTag(label: t("date.declined"), tone: .neutral).transition(.qPop)
        default:
            QTag(label: t("date.waiting"), tone: .blue).transition(.qPop)
        }
    }

    @ViewBuilder private var answerButtons: some View {
        Button(t("ticket.accept"), action: onAccept).buttonStyle(.q(.primary, compact: true))
        Button(t("ticket.decline"), action: onDecline).buttonStyle(.q(.secondary, compact: true))
    }

    private func field(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Sp.xxs) {
            Text(label).qText(.label).foregroundStyle(Color.q.muted)
            Text(value)
                .qText(mono ? .number : .callout)
                .foregroundStyle(Color.q.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// "Done typing? Suggest a run": shown above the composer after a long run of messages with no date.
struct DateNudge: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(t("nudge.suggest"), systemImage: "calendar.badge.plus")
                .qText(.callout)
                .foregroundStyle(Color.q.blueText)
                .padding(.horizontal, Sp.md)
                .frame(minHeight: Layout.rowMin)
                .background(Color.q.blueTint, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: Sp.xl) {
        DateTicket(title: "Лыжи · Шымбулак", when: "Сб 25 окт · 09:30", place: "Медеу, канатка", state: .pending(canAnswer: true))
        DateNudge {}
    }
    .padding()
    .background(Color.q.bg)
}
