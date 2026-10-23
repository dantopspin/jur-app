// The pieces onboarding shares: the gold segment progress, the live passport that fills
// in as people answer (photo, name and age, sport stamps, what they look for, their
// answer), the question header, the big choice tiles, the "who we show you" row, sport
// tiles, intent cards, the age check, a burst of gold dust, the photo mosaic.
import PhotosUI
import SwiftUI

// MARK: progress

/// One gold segment per question. The current one fills as you arrive on it.
struct SegmentProgress: View {
    /// 1-based step being answered; `total` when finished.
    let step: Int
    let total: Int
    @State private var fill: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(Color.q.onBlueFill)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule()
                                .fill(Color.q.gold)
                                .frame(width: g.size.width * (i < step ? 1 : i == step ? fill : 0))
                        }
                    }
                    .frame(height: 4)
            }
        }
        .task(id: step) {
            fill = 0
            withAnimation(reduceMotion ? nil : Motion.fill.delay(0.1)) { fill = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(t("onboarding.step", ["n": min(max(step, 1), total), "total": total]))
    }
}

// MARK: live passport

/// A sport stamp in miniature: the emoji in a dashed ring, tilted a little.
struct MiniStamp: View {
    let emoji: String
    let index: Int
    var size: CGFloat = 30

    private static let inks = [Color.q.stampBlue, Color.q.stampGreen, Color.q.feltLabel]
    private static let tilts: [Double] = [-8, 6, -3, 9, -6]

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.46))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Self.inks[index % Self.inks.count],
                                           style: StrokeStyle(lineWidth: 1.8, dash: [3, 2.5])))
            .rotationEffect(.degrees(Self.tilts[index % Self.tilts.count]))
            .accessibilityHidden(true)
    }
}

/// Stamps land: big and faint, then pressed onto the page.
private struct StampDrop: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 1.9 : 1)
            .opacity(active ? 0 : 1)
            .rotationEffect(.degrees(active ? -20 : 0))
    }
}

extension AnyTransition {
    /// A stamp pressed onto the passport (a plain fade under Reduce Motion).
    static var qStampDrop: AnyTransition {
        Motion.reduceMotion ? .opacity : .asymmetric(insertion: .modifier(active: StampDrop(active: true), identity: StampDrop(active: false)),
                                                     removal: .opacity)
    }
}

/// The passport being filled in, on felt, tilted like a card on a table. Every answer
/// lands on it as it's given.
struct LivePassport: View {
    let draft: OnboardingDraft
    /// Name only, when the keyboard leaves little room.
    var compact = false
    @Environment(SportsCatalog.self) private var catalog

    private var stamps: [Sport] { draft.pickOrder.compactMap { catalog.sport($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Sp.xs : Sp.sm) {
            HStack {
                Text(header).qText(.label).foregroundStyle(Color.q.feltLabel).lineLimit(1)
                Spacer()
                Text(verbatim: "№ ····").qText(.label).foregroundStyle(Color.q.feltLabel)
            }
            HStack(alignment: .top, spacing: Sp.md) {
                photo
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("flow.lblName").uppercased()).qText(.label).foregroundStyle(Color.q.feltLabel)
                    HStack(spacing: 0) {
                        Text(draft.trimmedName.isEmpty ? " " : draft.trimmedName)
                        if draft.birthConfirmed {
                            Text(verbatim: ", \(draft.age)").transition(.qPop)
                        }
                    }
                    .qText(.title2)
                    .foregroundStyle(Color.q.feltInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    if !compact { details }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? Sp.md : Sp.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.q.feltGround, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .rotationEffect(.degrees(-2))
        .shadow(color: Color.q.boardShade.opacity(0.5), radius: 16, y: 12)
        .animation(Motion.adaptive(Motion.bouncy), value: draft.birthConfirmed)
        .animation(Motion.adaptive(Motion.bouncy), value: draft.pickOrder)
        .animation(Motion.adaptive(Motion.bouncy), value: draft.photos.first)
        .animation(Motion.adaptive(Motion.smooth), value: draft.mode)
        .animation(Motion.adaptive(Motion.smooth), value: compact)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t("passport.title"))
    }

    private var header: String {
        let city = draft.city.map(Cities.label).map { " · " + $0 } ?? ""
        return (t("flow.passportHead") + city).uppercased()
    }

    private var photo: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        return ZStack {
            if let first = draft.photos.first, let url = URL(string: first) {
                QPhoto(url: url, size: .thumb, placeholder: Color.q.feltLine)
                    .clipShape(shape)
                    .id(first)
                    .transition(.qStampDrop)
            } else {
                shape.strokeBorder(Color.q.feltLine, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: "person.fill").font(.q(.title3)).foregroundStyle(Color.q.feltLine)
            }
        }
        .frame(width: compact ? 40 : 66, height: compact ? 50 : 84)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var details: some View {
        if !stamps.isEmpty {
            HStack(spacing: Sp.xs) {
                ForEach(Array(stamps.prefix(4).enumerated()), id: \.element.code) { i, s in
                    MiniStamp(emoji: s.emoji, index: i).transition(.qStampDrop)
                }
                if stamps.count > 4 {
                    Text(verbatim: "+\(stamps.count - 4)").qText(.footnote).foregroundStyle(Color.q.feltMuted)
                }
            }
            .padding(.top, Sp.xxs)
        }
        if let mode = draft.mode {
            HStack(spacing: Sp.xs) {
                Text(t("flow.lookingFor").uppercased()).qText(.label).foregroundStyle(Color.q.feltLabel)
                Text(t("flow.look_\(mode.rawValue)")).qText(.footnote).fontWeight(.bold)
                    .foregroundStyle(Color.q.stampBlue).lineLimit(1)
                    .id(mode)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            .padding(.top, Sp.xxs)
        }
        if !draft.trimmedAnswer.isEmpty {
            Text(verbatim: "«\(draft.trimmedAnswer)»")
                .qText(.footnote)
                .italic()
                .foregroundStyle(Color.q.feltInk)
                .lineLimit(2)
                .padding(.top, Sp.xxs)
        }
    }
}

// MARK: question header

struct QuestionHeader: View {
    let title: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            Text(title)
                .qText(.title1)
                .foregroundStyle(Color.q.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let hint {
                Text(hint).qText(.callout).foregroundStyle(Color.q.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: choices

/// The gold tick in a selected tile or card, drawn in as it appears.
struct SelectedTick: View {
    var size: CGFloat = 28
    /// When the tick starts drawing after the circle appears.
    var delay: Double = 0.08
    @State private var drawn: CGFloat = 0

    var body: some View {
        Circle()
            .fill(Color.q.gold)
            .frame(width: size, height: size)
            .overlay {
                TickShape()
                    .trim(from: 0, to: drawn)
                    .stroke(Color.q.onGold, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.28)
            }
            .onAppear { withAnimation(Motion.adaptive(Motion.draw).delay(delay)) { drawn = 1 } }
            .accessibilityHidden(true)
    }
}

private struct TickShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.05))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY - r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        return p
    }
}

/// A big square choice ("Девушка" / "Парень"). Selected: blue with a gold tick.
struct ChoiceTile: View {
    let emoji: String
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    Text(emoji).font(.system(size: 36))
                        .keyframeAnimator(initialValue: 0.0, trigger: bounce) { content, angle in
                            content.rotationEffect(.degrees(Motion.reduceMotion ? 0 : angle))
                        } keyframes: { _ in
                            KeyframeTrack {
                                SpringKeyframe(-14, duration: 0.12)
                                SpringKeyframe(10, duration: 0.14)
                                SpringKeyframe(0, duration: 0.25)
                            }
                        }
                    Spacer()
                    if selected { SelectedTick().transition(.qPop) }
                }
                Spacer(minLength: Sp.lg)
                Text(label).qText(.title3).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? .white : Color.q.ink)
            .padding(Sp.lg)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .background(selected ? Color.q.blue : Color.q.card,
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .animation(Motion.snappy, value: selected)
        }
        .buttonStyle(.qPressCard)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Покажем вам девушек · Изменить": the usual choice is made for you; «Изменить» opens
/// the three options (including «Всех»).
struct ShowMeRow: View {
    @Binding var interested: InterestedIn?
    let onChange: () -> Void
    @State private var open = false
    @Namespace private var segment

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            HStack(spacing: Sp.md) {
                Image(systemName: "heart.fill").foregroundStyle(Color.q.blueText).accessibilityHidden(true)
                Text(t("flow.show_\(interested?.rawValue ?? "men")"))
                    .qText(.headline)
                    .foregroundStyle(Color.q.blueText)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !open {
                    Button(t("flow.confirmEdit")) { withMotion(Motion.smooth) { open = true } }
                        .buttonStyle(.q(.ghost, compact: true))
                        .fixedSize()
                        .background(Color.q.card, in: Capsule())
                        .transition(.opacity)
                }
            }
            if open {
                HStack(spacing: 2) {
                    ForEach(InterestedIn.allCases, id: \.self) { option in
                        let on = interested == option
                        Button {
                            withMotion(Motion.snappy) { interested = option }
                            onChange()
                        } label: {
                            Text(t("onboarding.\(option.rawValue)"))
                                .qText(.callout)
                                .fontWeight(on ? .bold : .regular)
                                .foregroundStyle(Color.q.ink)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background {
                                    if on {
                                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .fill(Color.q.card)
                                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                                            .matchedGeometryEffect(id: "on", in: segment)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(Color.q.line, in: RoundedRectangle(cornerRadius: Radius.sm + 2, style: .continuous))
                .sensoryFeedback(.selection, trigger: interested)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Sp.md)
        .background(Color.q.blueTint, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .animation(Motion.adaptive(Motion.smooth), value: interested)
    }
}

/// A sport as a square tile: emoji over the name. Picked: blue, and the emoji hops.
struct SportTile: View {
    let sport: Sport
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Sp.xs) {
                Text(sport.emoji)
                    .font(.system(size: 30))
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: selected) { content, y in
                        content.offset(y: Motion.reduceMotion ? 0 : y)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(selected ? -10 : 0, duration: 0.15)
                            SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                        }
                    }
                Text(sport.name).qText(.footnote).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected ? .white : Color.q.ink)
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.horizontal, Sp.xs)
            .background(selected ? Color.q.blue : Color.q.card,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .animation(Motion.snappy, value: selected)
        }
        .buttonStyle(.qPressCard)
        .accessibilityLabel(sport.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// What they're here for, as a big card: emoji, title, a line under it, a tick.
struct IntentCard: View {
    let emoji: String
    let title: String
    let sub: String
    let selected: Bool
    let action: () -> Void
    @State private var wiggle = 0

    var body: some View {
        Button {
            wiggle += 1
            action()
        } label: {
            HStack(spacing: Sp.md) {
                Text(emoji)
                    .font(.system(size: 34))
                    .keyframeAnimator(initialValue: 0.0, trigger: wiggle) { content, a in
                        content
                            .rotationEffect(.degrees(Motion.reduceMotion ? 0 : a))
                            .scaleEffect(Motion.reduceMotion || a == 0 ? 1 : 1.15)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(-14, duration: 0.12)
                            SpringKeyframe(10, duration: 0.14)
                            SpringKeyframe(-4, duration: 0.12)
                            SpringKeyframe(0, duration: 0.2)
                        }
                    }
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(title).qText(.title3)
                    Text(sub).qText(.footnote).foregroundStyle(selected ? Color.q.blueMist : Color.q.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().strokeBorder(Color.q.line, lineWidth: 2).frame(width: 28, height: 28).opacity(selected ? 0 : 1)
                    if selected { SelectedTick().transition(.qPop) }
                }
            }
            .foregroundStyle(selected ? .white : Color.q.ink)
            .padding(.horizontal, Sp.lg)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(selected ? Color.q.blue : Color.q.card,
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .animation(Motion.snappy, value: selected)
        }
        .buttonStyle(.qPressCard)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: age check

/// "27 — вам 27? Потом не изменить", rising from the bottom over a scrim.
struct AgeConfirmCard: View {
    let age: Int
    let onYes: () -> Void
    let onEdit: () -> Void
    @State private var shown = 0

    var body: some View {
        VStack(spacing: Sp.sm) {
            Text(verbatim: "\(shown)")
                .font(.q(.display))
                .scaleEffect(1.6)
                .padding(.vertical, Sp.md)
                .foregroundStyle(Color.q.blueText)
                .contentTransition(.numericText(value: Double(shown)))
            Text(t("flow.confirmAge", ["age": age]) + "?").qText(.title2).foregroundStyle(Color.q.ink)
            Text(t("flow.confirmAgeSub")).qText(.callout).foregroundStyle(Color.q.muted)
                .multilineTextAlignment(.center)
            Button(t("flow.confirmYes"), action: onYes).buttonStyle(.qPrimary).padding(.top, Sp.sm)
            Button(t("flow.confirmEdit"), action: onEdit).buttonStyle(.qGhost)
        }
        .padding(.horizontal, Sp.lg)
        .padding(.top, Sp.xl)
        .padding(.bottom, Sp.sm)
        .frame(maxWidth: .infinity)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .padding(.horizontal, Sp.md)
        .padding(.bottom, Sp.sm)
        .task {
            shown = max(age - 3, 18)
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Motion.adaptive(Motion.bouncy)) { shown = age }
            Haptics.tick()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: sports chip (filters and the profile editor use it too)

extension Level {
    /// 1 (beginner) to 4 (competitive).
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

// MARK: choices on the departure board (city)

/// One-of-many choice set as JÜR's departure board (night blue, gold markers). The gold
/// selection slides from the old option to the new one; rows drop in one after another.
struct QChoiceGroup<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value?
    /// Called after a tap stores its choice (onboarding uses it to move on by itself).
    var onChoose: (() -> Void)?
    @Namespace private var selectionSpace
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = selection == option.value
                Button {
                    withMotion(Motion.snappy) { selection = option.value }
                    onChoose?()
                } label: {
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
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { appeared = true }
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

/// The next empty slot breathes, so it's clear where to tap.
struct BreathingSlot: ViewModifier {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 0.97 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.breathe) { on = true }
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
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
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
