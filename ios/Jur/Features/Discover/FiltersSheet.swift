// "Кого показывать": the filter sheet behind the button at the top right of Discover.
// Who and age are two-way (you only see people whose own preferences include you);
// sports, verified and "has been to events" narrow the deck; "active recently" is Pro.
// The button counts live how many people the choice would show before you save it.
import SwiftUI

struct DiscoverFilters: Equatable {
    var interested: InterestedIn = .everyone
    var ageMin = 18
    var ageMax = 60
    var sports: Set<String> = []
    var verified = false
    var attended = false
    /// 1 (today) or 7 (this week); nil = any time. Pro only.
    var activeDays: Int?

    init() {}

    init(_ p: MyProfile) {
        interested = p.interestedIn
        ageMin = p.ageMin ?? 18
        ageMax = p.ageMax ?? 60
        sports = Set(p.filterSports ?? [])
        verified = p.filterVerified ?? false
        attended = p.filterAttended ?? false
        activeDays = p.filterActiveDays
    }

    /// Anything beyond who and age: the button on Discover shows a gold dot.
    var narrowed: Bool { !sports.isEmpty || verified || attended || activeDays != nil }

    /// "Reset" keeps who you're looking for (that's identity, not a filter).
    func reset() -> DiscoverFilters {
        var f = DiscoverFilters()
        f.interested = interested
        return f
    }
}

/// The button on Discover's bar.
struct FiltersButton: View {
    let narrowed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if narrowed {
                        Circle().fill(Color.q.gold).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.q.bg, lineWidth: 1.5))
                            .offset(x: 4, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(Motion.adaptive(Motion.snappy), value: narrowed)
        }
        .accessibilityLabel(t("filters.title"))
        .accessibilityValue(narrowed ? t("filters.on") : "")
    }
}

struct FiltersSheet: View {
    /// Saved: Discover reloads.
    var onSaved: () -> Void
    @Environment(SessionStore.self) private var session
    @Environment(SportsCatalog.self) private var catalog
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var f = DiscoverFilters()
    @State private var original = DiscoverFilters()
    @State private var count: Int?
    @State private var saving = false
    @State private var paywall = false

    private var isPro: Bool { session.limits?.pro == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Sp.xl) {
                    section(t("filters.show")) {
                        Picker(t("filters.show"), selection: $f.interested) {
                            Text(t("onboarding.women")).tag(InterestedIn.women)
                            Text(t("onboarding.men")).tag(InterestedIn.men)
                            Text(t("onboarding.everyone")).tag(InterestedIn.everyone)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: Sp.md) {
                        HStack(alignment: .firstTextBaseline) {
                            label(t("filters.age"))
                            Spacer()
                            Text(verbatim: "\(f.ageMin) – \(f.ageMax)").qText(.number).foregroundStyle(Color.q.ink)
                                .contentTransition(.numericText())
                        }
                        AgeRangeSlider(low: $f.ageMin, high: $f.ageMax)
                    }

                    section(t("filters.sports")) {
                        FlowLayout(spacing: Sp.xs) {
                            SportChip(label: t("filters.anySport"), selected: f.sports.isEmpty) {
                                withMotion(Motion.snappy) { f.sports = [] }
                            }
                            ForEach(catalog.all) { s in
                                SportChip(label: "\(s.emoji) \(s.name)", selected: f.sports.contains(s.code)) {
                                    withMotion(Motion.snappy) {
                                        if f.sports.contains(s.code) { f.sports.remove(s.code) } else { f.sports.insert(s.code) }
                                    }
                                }
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        toggle(t("filters.verified"), t("filters.verifiedSub"), $f.verified)
                        Divider().overlay(Color.q.line)
                        toggle(t("filters.attended"), t("filters.attendedSub"), $f.attended)
                        Divider().overlay(Color.q.line)
                        activeRow
                    }
                    .padding(.horizontal, Sp.lg)
                    .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
                .padding(Layout.margin)
                .padding(.bottom, 120)
            }
            .background(Color.q.bg)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(t("filters.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("filters.reset")) { withMotion(Motion.smooth) { f = f.reset() } }
                        .disabled(f == f.reset())
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.done")) { Task { await save() } }.disabled(saving)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task {
            if let p = session.profile { f = DiscoverFilters(p); original = f }
        }
        // The live count, a moment after the last change.
        .task(id: f) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if let n = try? await Backend.discoverCount(f) { withAnimation(Motion.adaptive(Motion.snappy)) { count = n } }
        }
        .sheet(isPresented: $paywall) { PaywallView(context: .filters) }
    }

    // MARK: parts

    private var footer: some View {
        VStack(spacing: Sp.sm) {
            Text(t("filters.city", ["city": Cities.label(session.profile?.city ?? "")]))
                .qText(.footnote).foregroundStyle(Color.q.muted)
            Button { Task { await save() } } label: {
                BusyLabel(title: count.map { tn("filters.showN", $0) } ?? t("filters.apply"), busy: saving)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.qPrimary)
            .disabled(saving || count == 0)
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, Sp.md)
        .padding(.bottom, Sp.sm)
        .background(.bar)
    }

    private var activeRow: some View {
        HStack(spacing: Sp.md) {
            VStack(alignment: .leading, spacing: Sp.xxs) {
                HStack(spacing: Sp.xs) {
                    Text(t("filters.active")).qText(.callout).foregroundStyle(Color.q.ink)
                    if !isPro { QTag(label: "PRO", tone: .gold) }
                }
                Text(t("filters.activeSub")).qText(.footnote).foregroundStyle(Color.q.muted)
            }
            Spacer(minLength: Sp.sm)
            if isPro {
                Picker(t("filters.active"), selection: $f.activeDays) {
                    Text(t("filters.activeAny")).tag(Int?.none)
                    Text(t("filters.activeToday")).tag(Int?.some(1))
                    Text(t("filters.activeWeek")).tag(Int?.some(7))
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Button(t("filters.unlock")) { paywall = true }
                    .buttonStyle(.q(.secondary, compact: true))
                    .fixedSize()
            }
        }
        .frame(minHeight: 60)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            label(title)
            content()
        }
    }

    private func label(_ s: String) -> some View {
        Text(s.uppercased()).qText(.label).foregroundStyle(Color.q.muted)
    }

    private func toggle(_ title: String, _ sub: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: Sp.xxs) {
                Text(title).qText(.callout).foregroundStyle(Color.q.ink)
                Text(sub).qText(.footnote).foregroundStyle(Color.q.muted)
            }
        }
        .tint(Color.q.good)
        .frame(minHeight: 60)
    }

    private func save() async {
        guard !saving else { return }
        if f == original { dismiss(); return }
        saving = true
        defer { saving = false }
        do {
            let r = try await Backend.saveDiscoverFilters(f)
            guard r.ok else { toasts.show(t("common.error"), error: true); return }
            await session.refreshProfile()
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            toasts.show(t("common.error"), error: true)
        }
    }
}

/// Two handles on one track, 18–99, steps of one year. VoiceOver adjusts each handle
/// with a swipe up or down.
struct AgeRangeSlider: View {
    @Binding var low: Int
    @Binding var high: Int
    var range: ClosedRange<Int> = 18...99
    private let knob: CGFloat = 28

    var body: some View {
        GeometryReader { g in
            let width = g.size.width - knob
            let span = CGFloat(range.upperBound - range.lowerBound)
            let x = { (v: Int) in CGFloat(v - range.lowerBound) / span * width }
            let value = { (px: CGFloat) in
                range.lowerBound + Int((min(max(px, 0), width) / width * span).rounded())
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.q.line).frame(height: 4).padding(.horizontal, knob / 2)
                Capsule().fill(Color.q.blue)
                    .frame(width: max(x(high) - x(low), 0), height: 4)
                    .offset(x: x(low) + knob / 2)
                handle(at: x(low), label: t("filters.ageFrom"), value: $low, bounds: range.lowerBound...high) { px in
                    let v = value(px)
                    if v != low { low = min(v, high); Haptics.tick() }
                }
                handle(at: x(high), label: t("filters.ageTo"), value: $high, bounds: low...range.upperBound) { px in
                    let v = value(px)
                    if v != high { high = max(v, low); Haptics.tick() }
                }
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(.named("ageTrack"))
        }
        .frame(height: 44)
    }

    private func handle(at px: CGFloat, label: String, value: Binding<Int>, bounds: ClosedRange<Int>,
                        onDrag: @escaping (CGFloat) -> Void) -> some View {
        Circle()
            .fill(.white)
            .frame(width: knob, height: knob)
            .shadow(color: Color.q.blueNight.opacity(0.25), radius: 4, y: 2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .offset(x: px - 8)
            // The finger is the knob's centre, measured on the track (not the moving handle).
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("ageTrack"))
                .onChanged { g in onDrag(g.location.x - knob / 2) })
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(value.wrappedValue)")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: if value.wrappedValue < bounds.upperBound { value.wrappedValue += 1 }
                case .decrement: if value.wrappedValue > bounds.lowerBound { value.wrappedValue -= 1 }
                @unknown default: break
                }
            }
    }
}
