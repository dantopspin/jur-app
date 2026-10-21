// The departure board: how events appear (Tonight on Discover, the Events tab).
// Night blue in both modes, gold times in tabular figures, the mountains at its foot.
import SwiftUI

struct Departure: Identifiable, Hashable {
    enum Status: Hashable { case spots(Int), boarding, onTime, full }
    let id: UUID
    let time: String        // "19:00"
    let title: String       // "Падел · парная игра"
    let place: String
    let status: Status
}

struct DepartureBoard: View {
    let departures: [Departure]
    var header: String?
    var showsColumns = false
    var seeAll: (() -> Void)?
    /// Shown as the only row when there are no departures; nil hides the board's empty row.
    var emptyText: String?
    var onSelect: (Departure) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var timeColumn: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if header != nil || seeAll != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let header { Text(header).qText(.overline).foregroundStyle(Color.q.gold) }
                    Spacer(minLength: Sp.sm)
                    if let seeAll {
                        Button(t("board.all"), action: seeAll)
                            .font(.q(.footnote)).fontWeight(.bold)
                            .foregroundStyle(Color.q.blueMist)
                            .frame(minHeight: Layout.rowMin)
                    }
                }
            }
            if showsColumns && !typeSize.isAccessibilitySize {
                HStack(spacing: Sp.md) {
                    Text(t("board.time")).frame(width: timeColumn, alignment: .leading)
                    Text(t("board.where"))
                    Spacer()
                    Text(t("board.status"))
                }
                .qText(.label)
                .foregroundStyle(Color.q.blueMist)
                .padding(.vertical, Sp.sm)
                rule
            }
            if departures.isEmpty, let emptyText {
                HStack(spacing: Sp.md) {
                    Text(verbatim: "—:—").qText(.number).foregroundStyle(Color.q.gold)
                        .frame(width: timeColumn, alignment: .leading)
                    Text(emptyText).qText(.callout).foregroundStyle(Color.q.blueMist)
                }
                .padding(.vertical, Sp.md)
            }
            ForEach(Array(departures.enumerated()), id: \.element.id) { index, d in
                Button { onSelect(d) } label: { row(d) }
                    .buttonStyle(.plain)
                    .disabled(d.status == .full)
                if index < departures.count - 1 { rule }
            }
            // The destination: the mountains at the foot of every board.
            ZStack {
                RidgeShape(layer: .far).fill(Color.q.boardRidge)
                RidgeShape(layer: .near).fill(Color.q.boardShade.opacity(0.6))
            }
            .frame(height: 38)
            .padding(.horizontal, -Sp.lg)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Sp.lg)
        .padding(.top, Sp.sm)
        .background(Color.q.boardGround)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var rule: some View {
        Rectangle().fill(Color.q.boardRule).frame(height: 1)
    }

    private func row(_ d: Departure) -> some View {
        let full = d.status == .full
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Sp.xs))
            : AnyLayout(HStackLayout(spacing: Sp.md))
        return layout {
            if typeSize.isAccessibilitySize {
                HStack(spacing: Sp.md) {
                    time(d)
                    Spacer(minLength: 0)
                    statusView(d.status)
                }
                titles(d, full: full)
            } else {
                time(d).frame(width: timeColumn, alignment: .leading)
                titles(d, full: full)
                Spacer(minLength: Sp.sm)
                statusView(d.status)
            }
        }
        .padding(.vertical, Sp.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func time(_ d: Departure) -> some View {
        Text(d.time).qText(.number).foregroundStyle(Color.q.gold)
    }

    private func titles(_ d: Departure, full: Bool) -> some View {
        VStack(alignment: .leading, spacing: Sp.xxs) {
            Text(d.title)
                .qText(.headline)
                .strikethrough(full, color: Color.q.blueMist)
                .foregroundStyle(full ? Color.q.blueMist : .white)
                .lineLimit(2)
            Text(d.place).qText(.footnote).foregroundStyle(Color.q.blueMist).lineLimit(1)
        }
    }

    @ViewBuilder private func statusView(_ s: Departure.Status) -> some View {
        switch s {
        case .spots(let n):
            pill(t("board.spots", ["n": n]), fg: Color.q.onGold, bg: Color.q.gold)
        case .boarding:
            Text(t("board.boarding")).qText(.label)
                .foregroundStyle(.white)
                .padding(.horizontal, Sp.sm).padding(.vertical, Sp.xs)
                .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1))
                .fixedSize()
        case .onTime:
            Text(t("board.onTime")).qText(.label).foregroundStyle(Color.q.blueMist).fixedSize()
        case .full:
            Text(t("board.full")).qText(.label).foregroundStyle(Color.q.blueMist).fixedSize()
        }
    }

    private func pill(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text).qText(.label)
            .foregroundStyle(fg)
            .padding(.horizontal, Sp.sm).padding(.vertical, Sp.xs)
            .background(bg, in: Capsule())
            .fixedSize()
    }
}

/// Boarding: enter the host's 4-digit code (it changes every minute). Shown in a sheet
/// from the event's "Boarding" row.
struct BoardingCodeSheet: View {
    let eventTitle: String
    @Binding var code: String
    var busy = false
    var isError = false
    let onBoard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            VStack(alignment: .leading, spacing: Sp.sm) {
                Text(t("board.codeTitle", ["event": eventTitle])).qText(.overline).foregroundStyle(Color.q.clayDeep)
                    .accessibilityAddTraits(.isHeader)
                Text(t("board.codeHint")).qText(.callout).foregroundStyle(Color.q.inkSoft)
            }
            CodeField(length: 4, code: $code, isError: isError, accessibilityLabel: t("board.codeHint")) { _ in onBoard() }
            Button(action: onBoard) { BusyLabel(title: t("board.codeGo"), busy: busy) }
                .buttonStyle(.qPrimary)
                .disabled(code.count < 4 || busy)
        }
        .padding(Layout.margin)
        .padding(.top, Sp.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .qSheet(detents: [.height(320)])
    }
}

#Preview {
    VStack(spacing: Sp.lg) {
        DepartureBoard(departures: [
            .init(id: UUID(), time: "19:00", title: "Падел · парная игра", place: "Padel Club Esentai", status: .spots(2)),
            .init(id: UUID(), time: "20:30", title: "Пробежка 5 км", place: "Набережная Есентай", status: .boarding),
            .init(id: UUID(), time: "21:00", title: "Каток", place: "Медеу", status: .full),
        ], header: "СЕГОДНЯ · АЛМАТЫ", seeAll: {})
        DepartureBoard(departures: [], header: "СЕГОДНЯ · АЛМАТЫ", emptyText: "Сегодня отправлений нет")
    }
    .padding()
    .background(Color.q.bg)
    .sheet(isPresented: .constant(true)) {
        BoardingCodeSheet(eventTitle: "Скалодром 18:30", code: .constant("47"), onBoard: {})
    }
}
