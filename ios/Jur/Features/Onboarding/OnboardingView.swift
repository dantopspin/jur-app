// Onboarding: issuing your passport. Eight questions (name, birthdate, who you are, city,
// sports, what you're here for, photos, one question about you), one per screen, on a
// cream sheet under a felt passport that fills in as people answer. Creating the profile
// issues the passport: the member number rolls in, the "First step" stamp lands with a
// thump and a burst of gold, then the notification ask. Answers are saved as people go
// (OnboardingDraft), so closing the app resumes where they were.
import PhotosUI
import SwiftUI
import UIKit

struct OnboardingView: View {
    typealias Step = OnboardingDraft.Step

    /// Debug-only walkthrough: nothing is uploaded or saved to the server.
    var preview = false
    var onClosePreview: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(SportsCatalog.self) private var catalog
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var d = OnboardingDraft.fresh()
    @State private var restored = false
    @State private var forward = true
    @State private var confirmAge = false
    @State private var saving = false
    @State private var error: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pending: [PendingPhoto] = []
    @State private var autoAdvance: Task<Void, Never>?
    @State private var memberNo: Int?
    @FocusState private var focus: Field?

    enum Field { case name, answer }

    private var owner: String { preview ? "preview" : (session.userId?.uuidString ?? "signed-out") }
    private var latestBirth: Date { Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now }
    private var questions: Int { Step.questions }

    var body: some View {
        ZStack {
            Color.q.blueNight.ignoresSafeArea()
            if d.step == .issued {
                PassportIssuedView(draft: d, memberNo: memberNo,
                                   onAllow: { Task { await enterApp(askPush: true) } },
                                   onLater: { Push.remindLater(); Task { await enterApp(askPush: false) } })
                    .transition(.opacity)
            } else {
                flow
            }
            if confirmAge {
                Color.q.scrim
                    .ignoresSafeArea()
                    .onTapGesture { withMotion(Motion.smooth) { confirmAge = false } }
                    .transition(.opacity)
                VStack {
                    Spacer()
                    AgeConfirmCard(age: d.age, onYes: confirmBirth,
                                   onEdit: { withMotion(Motion.smooth) { confirmAge = false } })
                }
                .transition(.move(edge: .bottom))
            }
        }
        .task { await catalog.load() }
        .onAppear(perform: restore)
        // Save 0.3 s after the last change.
        .task(id: d) {
            guard restored else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            d.save(for: owner)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await add(items) }
        }
    }

    // MARK: layout

    private var flow: some View {
        GeometryReader { geo in
            // With the keyboard up on a small phone, the passport shrinks to its name line.
            let compact = geo.size.height < 600
            VStack(spacing: 0) {
                topBar
                LivePassport(draft: d, compact: compact)
                    .padding(.horizontal, Sp.xl)
                    .padding(.top, Sp.sm)
                    .padding(.bottom, compact ? Sp.md : Sp.xl)
                VStack(spacing: 0) {
                    // Each step gets its own scroll view (so it always opens at the top); the ZStack
                    // lets the leaving and arriving steps overlap instead of stacking.
                    ZStack(alignment: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Sp.lg) {
                                content
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Layout.margin)
                            .padding(.top, Sp.xl)
                            .padding(.bottom, Sp.xxl)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .id(d.step)
                        .transition(.qStep(forward: forward))
                    }
                    .frame(maxHeight: .infinity)
                    .clipped()
                    bottomBar
                }
                .background(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl, style: .continuous)
                        .fill(Color.q.bg)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Sp.md) {
            Group {
                if preview && d.step == .name {
                    CloseButton(action: onClosePreview)
                        .accessibilityLabel(t("flow.previewClose"))
                } else if d.step == .name {
                    Button(t("settings.signOut")) {
                        OnboardingDraft.clear(for: owner)
                        Task { await session.signOut() }
                    }
                    .qText(.footnote)
                    .foregroundStyle(Color.q.blueMist)
                    .fixedSize()
                } else {
                    Button { back() } label: {
                        Image(systemName: "chevron.left")
                            .font(.q(.callout).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.q.onBlueFill, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(t("common.back"))
                }
            }
            .frame(minHeight: 44)
            SegmentProgress(step: d.step.rawValue + 1, total: questions)
            if d.step == .prompt {
                Button(t("flow.skip")) {
                    d.promptAnswer = ""
                    Task { await finish() }
                }
                .qText(.footnote)
                .foregroundStyle(Color.q.blueMist)
                .fixedSize()
                .disabled(saving)
            }
        }
        .padding(.horizontal, Layout.margin)
        .frame(minHeight: Layout.rowMin)
    }

    private var bottomBar: some View {
        VStack(spacing: Sp.sm) {
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .qText(.footnote)
                    .foregroundStyle(Color.q.danger)
                    .transition(.qPop)
            }
            Button(action: next) {
                BusyLabel(title: buttonTitle, busy: saving)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.qPrimary)
            .disabled(!canContinue || saving)
            .animation(Motion.snappy, value: buttonTitle)
        }
        .padding(.horizontal, Layout.margin)
        .padding(.vertical, Sp.sm)
        .background(Color.q.bg)
        .animation(Motion.adaptive(Motion.smooth), value: error)
    }

    private var buttonTitle: String {
        switch d.step {
        case .sports where !d.picked.isEmpty: "\(t("common.continue")) · \(d.picked.count)"
        case .photos where !d.photos.isEmpty: "\(t("common.continue")) · " + t("flow.photosCount", ["n": d.photos.count])
        case .prompt: saving ? t("flow.issuing") : t("onboarding.finish")
        default: t("common.continue")
        }
    }

    private var canContinue: Bool {
        switch d.step {
        case .name: !d.trimmedName.isEmpty
        case .birth: d.birth <= latestBirth
        case .identity: d.gender != nil && d.interested != nil
        case .city: d.city != nil
        case .sports: !d.picked.isEmpty
        case .intent: d.mode != nil
        case .photos: d.photos.count >= OnboardingDraft.minPhotos && !pending.contains { !$0.failed }
        // An answer of one character wouldn't be saved; skipping is the button at the top.
        case .prompt: d.trimmedAnswer.count != 1
        case .issued: true
        }
    }

    // MARK: steps

    @ViewBuilder private var content: some View {
        switch d.step {
        case .name: nameStep
        case .birth: birthStep
        case .identity: identityStep
        case .city: cityStep
        case .sports: sportsStep
        case .intent: intentStep
        case .photos: photosStep
        case .prompt: promptStep
        case .issued: EmptyView()
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("onboarding.nameTitle"), hint: t("flow.nameHint"))
            VStack(alignment: .leading, spacing: Sp.sm) {
                TextField(t("onboarding.namePlaceholder"), text: $d.name)
                    .font(.q(.title2))
                    .textContentType(.givenName)
                    .submitLabel(.next)
                    .onSubmit(next)
                    .focused($focus, equals: .name)
                    .qField()
                    .onChange(of: d.name) { _, _ in d.nameFromApple = false }
                if d.nameFromApple {
                    Label(t("flow.fromApple"), systemImage: "apple.logo")
                        .qText(.footnote)
                        .foregroundStyle(Color.q.muted)
                        .transition(.opacity)
                }
            }
        }
        .onAppear { if d.name.isEmpty { focus = .name } }
    }

    private var birthStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("onboarding.birthTitle"), hint: t("onboarding.birthHint"))
            DatePicker("", selection: $d.birth, in: ...latestBirth, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .environment(\.locale, L10n.current.locale)
                .sensoryFeedback(.selection, trigger: d.age)
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("flow.identityQ"))
            HStack(spacing: Sp.sm) {
                ChoiceTile(emoji: "🙋‍♀️", label: t("onboarding.woman"), selected: d.gender == .woman) { pick(.woman) }
                ChoiceTile(emoji: "🙋‍♂️", label: t("onboarding.man"), selected: d.gender == .man) { pick(.man) }
            }
            if d.gender != nil {
                ShowMeRow(interested: $d.interested) { d.interestedChanged = true }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.adaptive(Motion.smooth), value: d.gender != nil)
    }

    private func pick(_ g: Gender) {
        withMotion(Motion.snappy) { d.choose(g) }
    }

    private var cityStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("onboarding.cityTitle"),
                           hint: t(Config.eventsEnabled ? "flow.cityHint" : "flow.cityHintApp"))
            QChoiceGroup(options: Cities.all.map { (value: $0, label: Cities.label($0)) }, selection: $d.city,
                         onChoose: { scheduleAutoAdvance(from: .city) })
        }
    }

    private var sportsStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("onboarding.sportsTitle"), hint: t("onboarding.sportsHint"))
            if catalog.all.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(seasonOrder, id: \.self) { season in
                let sports = catalog.all.filter { $0.season == season }
                if !sports.isEmpty {
                    VStack(alignment: .leading, spacing: Sp.sm) {
                        Text(t(season == "summer" ? "onboarding.summer" : season == "winter" ? "onboarding.winter" : "onboarding.allYear"))
                            .qText(.overline)
                            .foregroundStyle(Color.q.clayDeep)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Sp.sm), count: 3), spacing: Sp.sm) {
                            ForEach(sports) { s in
                                SportTile(sport: s, selected: d.picked[s.code] != nil) { toggle(s.code) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The current season's group first: summer from April to September, otherwise all-year then winter.
    private var seasonOrder: [String] {
        let month = Calendar.current.component(.month, from: .now)
        return (4...9).contains(month) ? ["summer", "all", "winter"] : ["all", "winter", "summer"]
    }

    private static let intents: [(ProfileMode, String)] = [(.dating, "💛"), (.buddy, "🤝"), (.both, "✨")]

    private var intentStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("flow.intentTitle"))
            VStack(spacing: Sp.sm) {
                ForEach(Self.intents.indices, id: \.self) { i in
                    let (mode, emoji) = Self.intents[i]
                    IntentCard(emoji: emoji, title: t("flow.intent_\(mode.rawValue)"),
                               sub: t("flow.intentSub_\(mode.rawValue)"), selected: d.mode == mode) {
                        withMotion(Motion.snappy) { d.mode = mode }
                        scheduleAutoAdvance(from: .intent, after: 650)
                    }
                }
            }
            Text(t("flow.intentNote"))
                .qText(.footnote)
                .foregroundStyle(Color.q.muted)
                .frame(maxWidth: .infinity)
        }
    }

    private var photosStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("onboarding.photosTitle"), hint: t("onboarding.photosHint"))
            PhotoMosaic {
                ForEach(0..<6, id: \.self) { slot in photoSlot(slot) }
            }
            Label(t("flow.photosTip"), systemImage: "camera.fill")
                .qText(.footnote)
                .foregroundStyle(Color.q.blueText)
                .padding(Sp.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.q.blueTint, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    @ViewBuilder private func photoSlot(_ slot: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        if slot < d.photos.count {
            let url = d.photos[slot]
            QPhoto(url: URL(string: url), size: .thumb)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(shape)
                .overlay(alignment: .topTrailing) {
                    Button {
                        withMotion(Motion.smooth) { _ = d.photos.remove(at: slot) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.q.scrim)
                            .font(.q(.title3))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(t("common.delete"))
                }
                .overlay(alignment: .topLeading) {
                    if slot == 0 { QTag(label: t("edit.main"), tone: .gold).padding(Sp.sm) }
                }
                .transition(.qPop)
                .id(url)
        } else if slot < d.photos.count + pending.count {
            let p = pending[slot - d.photos.count]
            Image(uiImage: p.image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(shape)
                .qShimmer(!p.failed)
                .overlay {
                    if p.failed {
                        Button { Task { await upload(p.id) } } label: {
                            Label(t("flow.uploadFailed"), systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                                .font(.q(.title2))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.q.scrim, in: shape)
                        }
                        .accessibilityLabel(t("flow.uploadFailed"))
                    }
                }
                .transition(.qPop)
                .id(p.id)
        } else if slot == d.photos.count + pending.count {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(6 - d.photos.count - pending.count, 1),
                         matching: .images) {
                ZStack {
                    shape.fill(Color.q.card)
                    shape.stroke(Color.q.blueText, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    Image(systemName: "plus")
                        .font(.q(.headline))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.q.blue, in: Circle())
                }
                .contentShape(shape)
                .modifier(BreathingSlot())
            }
            .buttonStyle(.qPressCard)
            .accessibilityLabel(t("onboarding.addPhoto"))
        } else {
            ZStack {
                shape.fill(Color.q.card.opacity(0.6))
                shape.stroke(Color.q.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .accessibilityHidden(true)
        }
    }

    private var promptStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            QuestionHeader(title: t("flow.promptTitle"), hint: t("flow.promptHint"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Sp.sm) {
                    ForEach(OnboardingDraft.promptChoices, id: \.self) { key in
                        let on = d.promptKey == key
                        Button {
                            withMotion(Motion.snappy) { d.promptKey = key }
                            focus = .answer
                        } label: {
                            Text(t("prompts.\(key)"))
                                .qText(.callout)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundStyle(on ? .white : Color.q.ink)
                                .padding(.horizontal, Sp.md)
                                .frame(minHeight: 40)
                                .background(on ? Color.q.blue : Color.q.card, in: Capsule())
                                .padding(.vertical, Sp.xxs)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.qPressCard)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Layout.margin)
            }
            .padding(.horizontal, -Layout.margin)
            .sensoryFeedback(.selection, trigger: d.promptKey)
            VStack(alignment: .leading, spacing: Sp.sm) {
                Text(t("prompts.\(d.promptKey)").uppercased())
                    .qText(.label)
                    .foregroundStyle(Color.q.clayDeep)
                    .contentTransition(.opacity)
                TextField(t("prompts.answer"), text: $d.promptAnswer, axis: .vertical)
                    .qText(.title3)
                    .foregroundStyle(Color.q.ink)
                    .lineLimit(2...5)
                    .focused($focus, equals: .answer)
                    .onChange(of: d.promptAnswer) { _, new in
                        if new.count > 150 { d.promptAnswer = String(new.prefix(150)) }
                    }
                HStack {
                    Text(t("flow.promptMore")).qText(.footnote).foregroundStyle(Color.q.muted)
                    Spacer()
                    Text(verbatim: "\(d.promptAnswer.count) / 150")
                        .qText(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.q.muted)
                        .contentTransition(.numericText())
                }
            }
            .padding(Sp.lg)
            .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(focus == .answer ? Color.q.blueText : Color.clear, lineWidth: 2))
            .animation(Motion.snappy, value: focus == .answer)
            .contentShape(Rectangle())
            .onTapGesture { focus = .answer }
        }
    }

    // MARK: flow

    private func restore() {
        guard !restored else { return }
        if let saved = OnboardingDraft.load(for: owner) {
            d = saved
        }
        restored = true
    }

    private func next() {
        // Return on the keyboard calls this too, so it checks the step like the button does.
        guard canContinue, !saving else { return }
        error = nil
        autoAdvance?.cancel()
        switch d.step {
        case .birth:
            focus = nil
            withMotion(Motion.hero) { confirmAge = true }
        case .prompt: Task { await finish() }
        case .issued: Task { await enterApp(askPush: true) }
        default:
            if let n = Step(rawValue: d.step.rawValue + 1) { go(n) }
        }
    }

    private func confirmBirth() {
        withMotion(Motion.smooth) { confirmAge = false }
        withMotion(Motion.bouncy) { d.birthConfirmed = true }
        Haptics.bump()
        go(.identity)
    }

    private func back() {
        error = nil
        autoAdvance?.cancel()
        if let p = Step(rawValue: d.step.rawValue - 1) { go(p) }
    }

    private func go(_ s: Step) {
        // Set the direction in its own update first, so the leaving step slides the right way.
        forward = s > d.step
        focus = nil
        DispatchQueue.main.async {
            withMotion(s == .issued ? Motion.hero : Motion.smooth) { d.step = s }
        }
    }

    /// After a single choice, move on by itself (not with VoiceOver, and only once the step is complete).
    private func scheduleAutoAdvance(from step: Step, after ms: Int = 400) {
        autoAdvance?.cancel()
        guard d.step == step, !voiceOver else { return }
        autoAdvance = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled, d.step == step, canContinue else { return }
            next()
        }
    }

    /// A tap picks a sport (its stamp lands on the passport), another removes it. Levels
    /// aren't asked for: every sport is stored as `.casual`, which the server still expects.
    private func toggle(_ code: String) {
        withMotion(Motion.bouncy) {
            if d.picked[code] == nil {
                d.picked[code] = .casual
                d.pickOrder.append(code)
            } else {
                d.picked[code] = nil
                d.pickOrder.removeAll { $0 == code }
            }
        }
        if d.picked[code] != nil, d.pickOrder.count <= 4 { Haptics.bump() }
    }

    // MARK: photos

    private func add(_ items: [PhotosPickerItem]) async {
        defer { pickerItems = [] }
        for item in items where d.photos.count + pending.count < 6 {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let jpeg = Media.jpeg(from: raw), let image = UIImage(data: jpeg) else {
                error = t("common.error")
                continue
            }
            let p = PendingPhoto(image: image, jpeg: jpeg)
            withMotion(Motion.bouncy) { pending.append(p) }
            Task { await upload(p.id) }
        }
    }

    private func upload(_ id: UUID) async {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        if pending[index].failed { withMotion(Motion.fade) { pending[index].failed = false } }
        let jpeg = pending[index].jpeg
        do {
            let url: String
            if preview {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).jpg")
                try jpeg.write(to: file)
                try? await Task.sleep(for: .milliseconds(700))
                url = file.absoluteString
            } else {
                guard let user = session.userId else { return }
                url = try await Media.uploadProfilePhoto(jpeg, userId: user)
            }
            withMotion(Motion.bouncy) {
                pending.removeAll { $0.id == id }
                d.photos.append(url)
            }
            Haptics.bump()
        } catch {
            if let i = pending.firstIndex(where: { $0.id == id }) {
                withMotion(Motion.fade) { pending[i].failed = true }
            }
        }
    }

    // MARK: finishing

    private func finish() async {
        guard let gender = d.gender, let interested = d.interested, let city = d.city else { return }
        focus = nil
        saving = true
        error = nil
        defer { saving = false }
        if preview {
            try? await Task.sleep(for: .seconds(0.8))
            OnboardingDraft.clear(for: owner)
            go(.issued)
            try? await Task.sleep(for: .seconds(0.6))
            memberNo = 42
            return
        }
        guard let id = session.userId else { return }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        let p = Backend.NewProfile(
            id: id, name: d.trimmedName, birthdate: f.string(from: d.birth),
            gender: gender.rawValue, interestedIn: interested.rawValue, city: city,
            bio: nil, nextChallenge: nil, photos: d.photos, locale: L10n.current.rawValue,
            mode: (d.mode ?? .dating).rawValue)
        do {
            try await Backend.createProfile(p, sports: d.picked)
            // The answer is a bonus: if it fails to save, the profile still exists and it can be added later.
            if d.trimmedAnswer.count >= 2 {
                try? await Backend.savePrompts(userId: id, [PromptAnswer(key: d.promptKey, answer: d.trimmedAnswer)])
            }
            UserDefaults.standard.removeObject(forKey: "jur.prefillName")
            OnboardingDraft.clear(for: owner)
            go(.issued)
            // The member number was assigned with the profile; it rolls in when it arrives.
            memberNo = (try? await Backend.profile(id))?.memberNo
        } catch {
            self.error = errorText(error)
        }
    }

    private func enterApp(askPush: Bool) async {
        if preview { onClosePreview(); return }
        if askPush { await Push.enable() }
        UserDefaults.standard.set(true, forKey: "jur.firstRun")
        await session.refreshProfile()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The end of onboarding, on night blue: "Паспорт выдан · Добро пожаловать, Айгерім". The
/// finished passport slides in, the member number rolls, the "First step" stamp slams down
/// (the card dips, gold dust bursts, a thump), then the notification ask.
struct PassportIssuedView: View {
    let draft: OnboardingDraft
    let memberNo: Int?
    let onAllow: () -> Void
    let onLater: () -> Void

    @Environment(SportsCatalog.self) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardIn = false
    @State private var shownNo = 0
    @State private var stamped = false
    @State private var dip = false
    @State private var burst = 0
    @State private var askShown = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Sp.xl) {
                    VStack(spacing: Sp.sm) {
                        Text(t("flow.issuedTitle").uppercased())
                            .qText(.overline)
                            .foregroundStyle(Color.q.gold)
                        Text(t("flow.welcome", ["name": draft.trimmedName]))
                            .qText(.title1)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .opacity(cardIn ? 1 : 0)
                    .offset(y: cardIn || reduceMotion ? 0 : -10)
                    passport
                        .padding(.horizontal, Sp.sm)
                        .opacity(cardIn ? 1 : 0)
                        .offset(y: cardIn || reduceMotion ? 0 : 60)
                        .rotationEffect(.degrees(cardIn || reduceMotion ? -2 : -7))
                        .stampDip(dip)
                    if askShown {
                        VStack(spacing: Sp.md) {
                            NotificationExample()
                            Text(t(Config.eventsEnabled ? "flow.notifySub" : "flow.notifySubApp"))
                                .qText(.callout)
                                .foregroundStyle(Color.q.blueMist)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, Layout.margin)
                .padding(.top, Sp.xxl)
                .padding(.bottom, Sp.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: Sp.xs) {
                Button(t("flow.notifyAllow"), action: onAllow).buttonStyle(.qAccent)
                Button(t("flow.notifyLater"), action: onLater).buttonStyle(.qOnBlue)
            }
            .padding(.horizontal, Layout.margin)
            .padding(.vertical, Sp.sm)
            .opacity(askShown ? 1 : 0)
            .disabled(!askShown)
        }
        .background(alignment: .bottom) {
            ZStack {
                RidgeShape(layer: .far).fill(Color.q.boardRidge.opacity(0.6))
                RidgeShape(layer: .near).fill(Color.q.boardShade)
            }
            .frame(height: 200)
            .ignoresSafeArea(edges: .bottom)
            .accessibilityHidden(true)
        }
        .onAppear {
            withAnimation(Motion.adaptive(Motion.hero)) { cardIn = true }
        }
        .task(id: memberNo) {
            guard let memberNo else { return }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(Motion.adaptive(Motion.hero)) { shownNo = memberNo }
            guard !stamped else { return }
            try? await Task.sleep(for: .milliseconds(500))
            await StampMoment.play(land: { stamped = true }, dip: { dip = $0 }, dust: { burst += 1 })
            Sounds.play(.checkin)
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(Motion.adaptive(Motion.smooth)) { askShown = true }
        }
        // If the number never arrives, still let them in.
        .task {
            try? await Task.sleep(for: .seconds(4))
            if !askShown { withAnimation(Motion.adaptive(Motion.smooth)) { askShown = true } }
        }
    }

    private var stamps: [Sport] { draft.pickOrder.compactMap { catalog.sport($0) } }

    private var passport: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            HStack {
                Text(t("passport.title").uppercased()).qText(.label).foregroundStyle(Color.q.feltLabel)
                Spacer()
                Text(verbatim: memberNo == nil ? "№ ····" : formatMemberNo(shownNo))
                    .qText(.number)
                    .foregroundStyle(Color.q.feltLabel)
                    .contentTransition(.numericText(value: Double(shownNo)))
            }
            HStack(alignment: .top, spacing: Sp.md) {
                QPhoto(url: draft.photos.first.flatMap { URL(string: $0) }, placeholder: Color.q.feltLine)
                    .frame(width: 84, height: 106)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Sp.xs) {
                    Text(verbatim: "\(draft.trimmedName), \(draft.age)")
                        .qText(.title2)
                        .foregroundStyle(Color.q.feltInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let city = draft.city {
                        Text(Cities.label(city)).qText(.callout).foregroundStyle(Color.q.feltMuted)
                    }
                    if let mode = draft.mode {
                        Text(t("flow.look_\(mode.rawValue)")).qText(.footnote).fontWeight(.bold)
                            .foregroundStyle(Color.q.stampBlue)
                    }
                    HStack(spacing: Sp.xs) {
                        ForEach(Array(stamps.prefix(4).enumerated()), id: \.element.code) { i, s in
                            MiniStamp(emoji: s.emoji, index: i, size: 28)
                        }
                    }
                    .padding(.top, Sp.xxs)
                }
            }
            if !draft.trimmedAnswer.isEmpty {
                Text(verbatim: "«\(draft.trimmedAnswer)»")
                    .qText(.callout)
                    .italic()
                    .foregroundStyle(Color.q.feltInk)
                    .lineLimit(3)
                    .padding(.trailing, 72)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("passport.since")).qText(.label).foregroundStyle(Color.q.feltMuted)
                    Text(Fmt.monthYear(.now)).qText(.headline).foregroundStyle(Color.q.feltInk)
                }
                Spacer()
                ZStack {
                    DustBurst(trigger: burst)
                    Stamp(data: StampData(kind: .first_step))
                        .stampSlam(stamped)
                }
            }
            .padding(.top, Sp.sm)
            .overlay(alignment: .top) { Rectangle().fill(Color.q.feltLine).frame(height: 1) }
        }
        .padding(Sp.lg)
        .background(Color.q.feltGround, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .shadow(color: Color.q.boardShade.opacity(0.6), radius: 24, y: 18)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }
}
