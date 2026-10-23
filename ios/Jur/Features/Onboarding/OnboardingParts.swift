// The pieces every onboarding step shares: the ridge progress line, the passport strip
// that fills in as people answer, the step header (a passport-style field label over
// the title), the choice group, sport chips with level pips, and the photo mosaic.
import PhotosUI
import SwiftUI

// MARK: progress

/// Progress drawn along the horizon's ridge: blue up to the current step, a dot at the tip.
struct RidgeProgress: View {
    /// 1-based step being answered; `total` when finished.
    let step: Int
    let total: Int

    private var fraction: CGFloat { CGFloat(min(max(step, 0), total)) / CGFloat(max(total, 1)) }

    var body: some View {
        let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        ZStack {
            RidgeShape(layer: .line).stroke(Color.q.line, style: style)
            RidgeShape(layer: .line).trim(from: 0, to: fraction).stroke(Color.q.blue, style: style)
            RidgeTip(progress: fraction).fill(Color.q.blue)
        }
        .frame(width: 168, height: 24)
        .animation(Motion.adaptive(Motion.smooth), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(t("onboarding.step", ["n": min(max(step, 1), total), "total": total]))
    }
}

/// The dot riding at the end of the drawn part of the ridge.
private struct RidgeTip: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let line = RidgeShape(layer: .line).path(in: rect)
        let end = line.trimmedPath(from: 0, to: max(progress, 0.001)).currentPoint
            ?? CGPoint(x: rect.minX, y: rect.midY)
        return Path(ellipseIn: CGRect(x: end.x - 3.5, y: end.y - 3.5, width: 7, height: 7))
    }
}

// MARK: passport strip

/// The passport being filled in: photo, name and age, then city and sports. Felt, like the
/// passport page it becomes at the end.
struct PassportStrip: View {
    let draft: OnboardingDraft
    /// One line only, when the keyboard leaves little room.
    var compact = false
    @Environment(SportsCatalog.self) private var catalog

    var body: some View {
        HStack(spacing: Sp.md) {
            avatar
            VStack(alignment: .leading, spacing: Sp.xxs) {
                HStack(spacing: 0) {
                    Text(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? t("flow.lblName") : draft.name)
                        .foregroundStyle(draft.name.isEmpty ? Color.q.feltMuted : Color.q.feltInk)
                    if draft.birthConfirmed {
                        Text(verbatim: ", \(draft.age)")
                            .foregroundStyle(Color.q.feltInk)
                            .contentTransition(.numericText())
                            .transition(.qPop)
                    }
                }
                .qText(.title3)
                .lineLimit(1)
                if !compact {
                    Text(meta)
                        .qText(.footnote)
                        .foregroundStyle(Color.q.feltMuted)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
            MarkView(size: 20, color: Color.q.feltLabel).accessibilityHidden(true)
        }
        .padding(.horizontal, Sp.md)
        .padding(.vertical, compact ? Sp.sm : Sp.md)
        .background(Color.q.feltGround, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .animation(Motion.adaptive(Motion.bouncy), value: draft.birthConfirmed)
        .animation(Motion.adaptive(Motion.smooth), value: meta)
        .animation(Motion.adaptive(Motion.smooth), value: draft.photos.first)
        .animation(Motion.adaptive(Motion.smooth), value: compact)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        ZStack {
            if let first = draft.photos.first, let url = URL(string: first) {
                QPhoto(url: url, size: .thumb, placeholder: Color.q.feltLine)
                    .transition(.opacity)
            } else {
                Circle().strokeBorder(Color.q.feltLine, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                Image(systemName: "person.fill").font(.q(.callout)).foregroundStyle(Color.q.feltLine)
            }
        }
        .frame(width: compact ? 32 : 44, height: compact ? 32 : 44)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var meta: String {
        let city = draft.city.map(Cities.label) ?? "—"
        let codes = catalog.all.map(\.code).filter { draft.picked[$0] != nil }
        let shown = codes.prefix(2).compactMap { catalog.sport($0)?.name }
        var sports = shown.isEmpty ? "—" : shown.joined(separator: ", ")
        if codes.count > 2 { sports += " +\(codes.count - 2)" }
        return "\(city) · \(sports)"
    }
}

// MARK: step header

/// "03 · CITY" in clay over the title, like a field on a passport.
struct StepHeader: View {
    let number: Int
    let label: String
    let title: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            Text(verbatim: String(format: "%02d", number) + " · " + label.uppercased())
                .qText(.overline)
                .foregroundStyle(Color.q.clayDeep)
            Text(title)
                .qText(.title1)
                .foregroundStyle(Color.q.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let hint {
                Text(hint).qText(.body).foregroundStyle(Color.q.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: choices

/// One-of-many choice. The blue selection slides from the old option to the new one.
/// `board` sets the options as JÜR's departure board (night blue, gold markers).
struct QChoiceGroup<Value: Hashable>: View {
    enum Style { case rows, board }
    let options: [(value: Value, label: String)]
    @Binding var selection: Value?
    var style: Style = .rows
    /// Called after a tap stores its choice (onboarding uses it to move on by itself).
    var onChoose: (() -> Void)?
    @Namespace private var selectionSpace
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch style {
            case .rows: rows
            case .board: board
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { appeared = true }
    }

    private func choose(_ value: Value) {
        withMotion(Motion.snappy) { selection = value }
        onChoose?()
    }

    private var rows: some View {
        VStack(spacing: Sp.sm) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = selection == option.value
                Button { choose(option.value) } label: {
                    HStack {
                        Text(option.label).qText(.headline)
                        Spacer()
                        if on { Image(systemName: "checkmark").font(.q(.headline)).transition(.qPop) }
                    }
                    .foregroundStyle(on ? .white : Color.q.ink)
                    .padding(.horizontal, Sp.lg)
                    .frame(minHeight: 60)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Color.q.card)
                            if on {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(Color.q.blue)
                                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.qPressCard)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = selection == option.value
                Button { choose(option.value) } label: {
                    HStack(spacing: Sp.md) {
                        Text(verbatim: String(format: "%02d", i + 1))
                            .qText(.number)
                            .foregroundStyle(on ? Color.q.onGold : Color.q.gold)
                        Text(option.label)
                            .qText(.title3)
                            .foregroundStyle(on ? Color.q.onGold : .white)
                        Spacer()
                        if on { Image(systemName: "checkmark").font(.q(.headline)).foregroundStyle(Color.q.onGold).transition(.qPop) }
                    }
                    .padding(.horizontal, Sp.md)
                    .frame(minHeight: 52)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Color.q.gold)
                                .matchedGeometryEffect(id: "selection", in: selectionSpace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.qPressCard)
                .accessibilityAddTraits(on ? .isSelected : [])
                // Rows drop in one after another, like a board updating.
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : -6)
                .animation(Motion.adaptive(Motion.smooth).delay(Double(i) * Motion.stagger), value: appeared)
                if i < options.count - 1 {
                    Rectangle().fill(Color.q.boardRule).frame(height: 1).padding(.horizontal, Sp.md)
                }
            }
            ZStack {
                RidgeShape(layer: .far).fill(Color.q.boardRidge)
                RidgeShape(layer: .near).fill(Color.q.boardShade.opacity(0.6))
            }
            .frame(height: 38)
            .padding(.horizontal, -Sp.sm)
            .padding(.top, Sp.sm)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Sp.sm)
        .padding(.top, Sp.sm)
        .background(Color.q.boardGround)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: sports

extension Level {
    /// 1 (beginner) to 4 (competitive), for the level pips.
    var pips: Int {
        switch self {
        case .beginner: 1
        case .casual: 2
        case .regular: 3
        case .competitive: 4
        }
    }
}

/// A sport chip: on or off. Both states have the same size, so picking a sport never
/// shifts the row; off chips carry a hairline so they stay visible on white and on cream.
struct SportChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .qText(.callout)
                .lineLimit(1)
                .foregroundStyle(selected ? .white : Color.q.ink)
                .padding(.horizontal, Sp.md)
                .frame(minHeight: 40)
                .background(selected ? Color.q.blue : Color.q.card, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.q.line, lineWidth: 1))
                // 40 pt to the eye, 44 pt to the finger.
                .padding(.vertical, Sp.xxs)
                .contentShape(Rectangle())
                .animation(Motion.snappy, value: selected)
        }
        .buttonStyle(.qPressCard)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: photos

/// Six photo slots: the main photo large (2×2, like the card), five small around it.
struct PhotoMosaic: SwiftUI.Layout {
    var gap: CGFloat = Sp.sm

    private func unit(_ width: CGFloat) -> (w: CGFloat, h: CGFloat) {
        let w = max((width - 2 * gap) / 3, 0)
        return (w, w * 4 / 3)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 340
        let u = unit(width)
        return CGSize(width: width, height: 3 * u.h + 2 * gap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let u = unit(bounds.width)
        let x0 = bounds.minX, y0 = bounds.minY
        let frames: [CGRect] = [
            CGRect(x: x0, y: y0, width: 2 * u.w + gap, height: 2 * u.h + gap),
            CGRect(x: x0 + 2 * (u.w + gap), y: y0, width: u.w, height: u.h),
            CGRect(x: x0 + 2 * (u.w + gap), y: y0 + u.h + gap, width: u.w, height: u.h),
            CGRect(x: x0, y: y0 + 2 * (u.h + gap), width: u.w, height: u.h),
            CGRect(x: x0 + u.w + gap, y: y0 + 2 * (u.h + gap), width: u.w, height: u.h),
            CGRect(x: x0 + 2 * (u.w + gap), y: y0 + 2 * (u.h + gap), width: u.w, height: u.h),
        ]
        for (i, view) in subviews.enumerated() where i < frames.count {
            let f = frames[i]
            view.place(at: f.origin, proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}

/// A photo picked but not uploaded yet: shown at once from the device, shimmering until
/// it's up; a failed one offers retry.
struct PendingPhoto: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    let jpeg: Data
    var failed = false
}

// MARK: notification example

/// What a JÜR notification looks like, shown once above the notification ask.
struct NotificationExample: View {
    var body: some View {
        HStack(spacing: Sp.md) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.q.blue)
                .frame(width: 38, height: 38)
                .overlay(MarkView(size: 26, color: Color.q.gold))
            VStack(alignment: .leading, spacing: Sp.xxs) {
                HStack {
                    Text(verbatim: "JÜR").qText(.footnote).fontWeight(.bold).foregroundStyle(Color.q.ink)
                    Spacer()
                    Text(t("flow.notifyNow")).qText(.caption).foregroundStyle(Color.q.muted)
                }
                Text(t("flow.notifyExample")).qText(.callout).foregroundStyle(Color.q.ink).lineLimit(2)
            }
        }
        .padding(Sp.md)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .qElevated()
        .accessibilityElement(children: .combine)
    }
}
