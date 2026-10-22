// Onboarding: issuing your passport. Seven questions (name, birthdate, about you, city,
// sports, photos, your words) fill a passport strip at the top; creating the profile
// issues the passport with the member number and the "First step" stamp, then asks
// about notifications. Answers are saved as people go (OnboardingDraft), so closing the
// app resumes where they were. The profile is only created at the end.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var d = OnboardingDraft.fresh()
    @State private var restored = false
    @State private var forward = true
    @State private var confirmAge = false
    @State private var saving = false
    @State private var error: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pending: [PendingPhoto] = []
    @State private var armedSport: String?
    @State private var sportsHint = 0
    @AppStorage("jur.sportsHintShown") private var sportsHintShown = false
    @State private var autoAdvance: Task<Void, Never>?
    @State private var memberNo: Int?
    @FocusState private var focus: Field?
    @Namespace private var passportSpace

    enum Field { case name, challenge, bio }

    private var owner: String { preview ? "preview" : (session.userId?.uuidString ?? "signed-out") }
    private var latestBirth: Date { Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now }
    private var questions: Int { Step.questions }

    var body: some View {
        GeometryReader { geo in
            // With the keyboard up on a small phone, the strip shrinks to one line.
            let compact = geo.size.height < 560
            VStack(spacing: 0) {
                topBar
                if d.step == .issued {
                    PassportIssuedView(draft: d, memberNo: memberNo, space: passportSpace)
                        .transition(.opacity)
                } else {
                    PassportStrip(draft: d, compact: compact)
                        .matchedGeometryEffect(id: "passport", in: passportSpace)
                        .padding(.horizontal, Layout.margin)
                        .padding(.top, Sp.xs)
                    // Each step gets its own scroll view (so it always opens at the top); the ZStack
                    // lets the leaving and arriving steps overlap instead of stacking.
                    ZStack(alignment: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Sp.xl) {
                                content
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Layout.margin)
                            .padding(.top, compact ? Sp.lg : Sp.xl)
                            .padding(.bottom, Sp.xxl)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .id(d.step)
                        .transition(.qStep(forward: forward))
                    }
                    .frame(maxHeight: .infinity)
                }
                bottomBar
            }
        }
        .background(Color.q.bg)
        .task { await catalog.load() }
        .onAppear(perform: restore)
        // Save 0.3 s after the last change.
        .task(id: d) {
            guard restored else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            d.save(for: owner)
        }
        .alert(t("flow.confirmAge", ["age": d.age]), isPresented: $confirmAge) {
            Button(t("flow.confirmYes")) {
                withMotion(Motion.bouncy) { d.birthConfirmed = true }
                go(.identity)
            }
            Button(t("flow.confirmEdit"), role: .cancel) {}
        } message: {
            Text(t("flow.confirmAgeSub"))
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await add(items) }
        }
    }

    // MARK: chrome

    private var topBar: some View {
        HStack {
            Group {
                if preview && d.step == .name {
                    Button(action: onClosePreview) { Image(systemName: "xmark").font(.q(.headline)) }
                        .accessibilityLabel(t("flow.previewClose"))
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                } else if d.step == .name {
                    Button(t("settings.signOut")) {
                        OnboardingDraft.clear(for: owner)
                        Task { await session.signOut() }
                    }
                    .font(.q(.callout))
                } else if d.step != .issued {
                    Button { back() } label: { Image(systemName: "chevron.left").font(.q(.headline)) }
                        .accessibilityLabel(t("common.back"))
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
            }
            .frame(minWidth: 72, alignment: .leading)
            Spacer()
            RidgeProgress(step: d.step == .issued ? questions : d.step.rawValue + 1, total: questions)
            Spacer()
            Group {
                if d.step == .about {
                    Button(t("flow.skip")) { Task { await finish() } }.font(.q(.callout)).disabled(saving)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .frame(minWidth: 72, alignment: .trailing)
        }
        .foregroundStyle(Color.q.blueText)
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
            if d.step == .issued {
                Button(t("flow.notifyLater")) { Task { await enterApp(askPush: false) } }
                    .buttonStyle(.qGhost)
                    .transition(.qPop)
            }
        }
        .padding(.horizontal, Layout.margin)
        .padding(.vertical, Sp.sm)
        .background(Color.q.bg)
        .animation(Motion.adaptive(Motion.smooth), value: error)
    }

    private var buttonTitle: String {
        switch d.step {
        case .sports where !d.picked.isEmpty: "\(t("common.continue")) · \(d.picked.count)"
        case .about: saving ? t("flow.issuing") : t("onboarding.finish")
        case .issued: t("flow.notifyAllow")
        default: t("common.continue")
        }
    }

    private var canContinue: Bool {
        switch d.step {
        case .name: !d.name.trimmingCharacters(in: .whitespaces).isEmpty
        case .birth: d.birth <= latestBirth
        case .identity: d.gender != nil && d.interested != nil
        case .city: d.city != nil
        case .sports: !d.picked.isEmpty
        case .photos: !d.photos.isEmpty && !pending.contains { !$0.failed }
        case .about, .issued: true
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
        case .photos: photosStep
        case .about: aboutStep
        case .issued: EmptyView()
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            StepHeader(number: 1, label: t("flow.lblName"), title: t("onboarding.nameTitle"))
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
    }

    private var birthStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            StepHeader(number: 2, label: t("flow.lblBirth"), title: t("onboarding.birthTitle"),
                       hint: t("onboarding.birthHint"))
            DatePicker("", selection: $d.birth, in: ...latestBirth, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.locale, L10n.current.locale)
            VStack(spacing: Sp.xxs) {
                Text(t("flow.ageLabel")).qText(.overline).foregroundStyle(Color.q.clayDeep)
                Text(verbatim: "\(d.age)")
                    .font(.q(.display))
                    .foregroundStyle(Color.q.ink)
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: d.age)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .sensoryFeedback(.selection, trigger: d.age)
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: Sp.xl) {
            StepHeader(number: 3, label: t("flow.lblIdentity"), title: t("flow.identityTitle"))
            VStack(alignment: .leading, spacing: Sp.sm) {
                Text(t("onboarding.genderTitle")).qText(.headline).foregroundStyle(Color.q.inkSoft)
                QChoiceGroup(options: [(value: Gender.woman, label: t("onboarding.woman")),
                                       (value: Gender.man, label: t("onboarding.man"))],
                             selection: $d.gender, onChoose: { scheduleAutoAdvance(from: .identity) })
            }
            VStack(alignment: .leading, spacing: Sp.sm) {
                Text(t("onboarding.interestedTitle")).qText(.headline).foregroundStyle(Color.q.inkSoft)
                QChoiceGroup(options: [(value: InterestedIn.women, label: t("onboarding.women")),
                                       (value: InterestedIn.men, label: t("onboarding.men")),
                                       (value: InterestedIn.everyone, label: t("onboarding.everyone"))],
                             selection: $d.interested, onChoose: { scheduleAutoAdvance(from: .identity) })
            }
        }
    }

    private var cityStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            StepHeader(number: 4, label: t("flow.lblCity"), title: t("onboarding.cityTitle"),
                       hint: t(Config.eventsEnabled ? "flow.cityHint" : "flow.cityHintApp"))
            QChoiceGroup(options: Cities.all.map { (value: $0, label: Cities.label($0)) }, selection: $d.city,
                         style: .board, onChoose: { scheduleAutoAdvance(from: .city) })
        }
    }

    private var sportsStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            StepHeader(number: 5, label: t("flow.lblSports"), title: t("onboarding.sportsTitle"),
                       hint: t("onboarding.sportsHint"))
            if catalog.all.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(seasonOrder, id: \.self) { season in
                let sports = catalog.all.filter { $0.season == season }
                if !sports.isEmpty {
                    VStack(alignment: .leading, spacing: Sp.xs) {
                        Text(t(season == "summer" ? "onboarding.summer" : season == "winter" ? "onboarding.winter" : "onboarding.allYear"))
                            .qText(.overline)
                            .foregroundStyle(Color.q.clayDeep)
                        FlowLayout(spacing: Sp.xs) {
                            ForEach(sports) { s in
                                SportChip(label: "\(s.emoji) \(s.name)", level: d.picked[s.code],
                                          armed: armedSport == s.code, hintPulse: sportsHint) {
                                    cycle(s.code)
                                }
                                .contextMenu {
                                    if d.picked[s.code] != nil {
                                        Button(t("flow.removeSport"), systemImage: "minus.circle", role: .destructive) {
                                            withMotion(Motion.snappy) { d.picked[s.code] = nil; armedSport = nil }
                                        }
                                    }
                                }
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

    private var photosStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            StepHeader(number: 6, label: t("flow.lblPhotos"), title: t("onboarding.photosTitle"),
                       hint: t("onboarding.photosHint"))
            PhotoMosaic {
                ForEach(0..<6, id: \.self) { slot in photoSlot(slot) }
            }
        }
    }

    @ViewBuilder private func photoSlot(_ slot: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        if slot < d.photos.count {
            let url = d.photos[slot]
            QPhoto(url: URL(string: url))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(shape)
                .overlay(alignment: .topTrailing) {
                    Button {
                        withMotion(Motion.smooth) { _ = d.photos.remove(at: slot) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                            .font(.q(.title3))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(t("common.delete"))
                }
                .overlay(alignment: .bottomLeading) {
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
                                .background(Color.black.opacity(0.35), in: shape)
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
                    shape.stroke(Color.q.blueText, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    Image(systemName: "plus").font(.q(.title2)).foregroundStyle(Color.q.blueText)
                }
                .contentShape(shape)
            }
            .buttonStyle(.qPressCard)
            .accessibilityLabel(t("onboarding.addPhoto"))
        } else {
            shape.stroke(Color.q.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .accessibilityHidden(true)
        }
    }

    @State private var exampleIndex = 0

    private var aboutStep: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            StepHeader(number: 7, label: t("flow.lblAbout"), title: t("onboarding.challengeTitle"))
            // Drawn the way the card shows it, so what you type is what people will see.
            VStack(alignment: .leading, spacing: Sp.xs) {
                Text(t("card.nextChallenge")).qText(.label).foregroundStyle(Color.q.clayDeep)
                ZStack(alignment: .topLeading) {
                    if d.challenge.isEmpty {
                        Text(t("flow.challengeEx\(exampleIndex + 1)"))
                            .qText(.headline)
                            .foregroundStyle(Color.q.hint)
                            .id(exampleIndex)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TextField("", text: $d.challenge, axis: .vertical)
                        .qText(.headline)
                        .foregroundStyle(Color.q.ink)
                        .lineLimit(1...3)
                        .focused($focus, equals: .challenge)
                        .accessibilityLabel(t("card.nextChallenge"))
                }
            }
            .padding(Sp.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.q.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(Sp.sm)
            .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focus = .challenge }
            // Examples take turns while the field is empty and not being typed in.
            .task(id: d.challenge.isEmpty && focus != .challenge && !reduceMotion) {
                guard d.challenge.isEmpty, focus != .challenge, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.fade) { exampleIndex = (exampleIndex + 1) % 3 }
                }
            }
            Text(t("onboarding.bioTitle")).qText(.headline).foregroundStyle(Color.q.ink)
            TextField(t("onboarding.bioPlaceholder"), text: $d.bio, axis: .vertical)
                .lineLimit(3...6)
                .padding(.vertical, Sp.md)
                .focused($focus, equals: .bio)
                .qField()
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
        switch d.step {
        case .birth: confirmAge = true
        case .about: Task { await finish() }
        case .issued: Task { await enterApp(askPush: true) }
        default:
            if let n = Step(rawValue: d.step.rawValue + 1) { go(n) }
        }
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
    private func scheduleAutoAdvance(from step: OnboardingDraft.Step) {
        autoAdvance?.cancel()
        // Runs after the choice is stored, so canContinue sees it.
        guard d.step == step, !voiceOver else { return }
        autoAdvance = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, d.step == step, canContinue else { return }
            next()
        }
    }

    /// First tap picks a sport (casual), later taps step its level; after the last level the
    /// chip shows × and one more tap removes it.
    private func cycle(_ code: String) {
        let order: [Level] = [.casual, .regular, .competitive, .beginner]
        if armedSport == code {
            withMotion(Motion.snappy) { d.picked[code] = nil; armedSport = nil }
            return
        }
        armedSport = nil
        guard let current = d.picked[code] else {
            withMotion(Motion.snappy) { d.picked[code] = .casual }
            if !sportsHintShown {
                sportsHintShown = true
                Task { try? await Task.sleep(for: .milliseconds(250)); sportsHint += 1 }
            }
            return
        }
        let i = order.firstIndex(of: current) ?? 0
        withMotion(Motion.snappy) {
            if i == order.count - 1 { armedSport = code } else { d.picked[code] = order[i + 1] }
        }
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
            id: id, name: d.name.trimmingCharacters(in: .whitespaces), birthdate: f.string(from: d.birth),
            gender: gender.rawValue, interestedIn: interested.rawValue, city: city,
            bio: d.bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            nextChallenge: d.challenge.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            photos: d.photos, locale: L10n.current.rawValue)
        do {
            try await Backend.createProfile(p, sports: d.picked)
            UserDefaults.standard.removeObject(forKey: "jur.prefillName")
            OnboardingDraft.clear(for: owner)
            go(.issued)
            // The member number was assigned with the profile; it rolls in when it arrives.
            memberNo = (try? await Backend.profile(id))?.memberNo
        } catch {
            self.error = t("common.error")
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

/// The end of onboarding: the strip has become the passport page, the member number rolls
/// in and the "First step" stamp lands. Then an example notification and the ask below.
struct PassportIssuedView: View {
    let draft: OnboardingDraft
    let memberNo: Int?
    let space: Namespace.ID
    @State private var shownNo = 0
    @State private var stamped = false
    @State private var exampleShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Sp.xl) {
                passport
                    .matchedGeometryEffect(id: "passport", in: space)
                VStack(alignment: .leading, spacing: Sp.sm) {
                    Text(t("flow.issuedTitle")).qText(.title1).foregroundStyle(Color.q.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(t(Config.eventsEnabled ? "flow.notifySub" : "flow.notifySubApp"))
                        .qText(.body).foregroundStyle(Color.q.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NotificationExample()
                    .opacity(exampleShown ? 1 : 0)
                    .offset(y: exampleShown || reduceMotion ? 0 : -16)
            }
            .padding(.horizontal, Layout.margin)
            .padding(.top, Sp.sm)
            .padding(.bottom, Sp.xl)
        }
        .task(id: memberNo) {
            guard let memberNo else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(Motion.adaptive(Motion.hero)) { shownNo = memberNo }
            guard !stamped else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(Motion.adaptive(Motion.bouncy)) { stamped = true }
            try? await Task.sleep(for: .milliseconds(150))
            Haptics.thump()
            Haptics.success()
            Sounds.play(.checkin)
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(Motion.adaptive(Motion.smooth)) { exampleShown = true }
        }
    }

    private var passport: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            HStack {
                Text(t("passport.title")).qText(.overline).foregroundStyle(Color.q.feltLabel)
                Spacer()
                MarkView(size: 24, color: Color.q.feltLabel).accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: Sp.md) {
                QPhoto(url: draft.photos.first.flatMap { URL(string: $0) }, placeholder: Color.q.feltLine)
                    .frame(width: 84, height: 106)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Sp.xs) {
                    Text(verbatim: "\(draft.name.trimmingCharacters(in: .whitespaces)), \(draft.age)")
                        .qText(.title2)
                        .foregroundStyle(Color.q.feltInk)
                        .lineLimit(2)
                    Text(verbatim: memberNo == nil ? "№ …" : formatMemberNo(shownNo))
                        .qText(.display)
                        .foregroundStyle(Color.q.feltInk)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("passport.city")).qText(.label).foregroundStyle(Color.q.feltMuted)
                    Text(draft.city.map(Cities.label) ?? "").qText(.headline).foregroundStyle(Color.q.feltInk)
                    Text(t("passport.since")).qText(.label).foregroundStyle(Color.q.feltMuted).padding(.top, Sp.xs)
                    Text(Fmt.monthYear(.now)).qText(.headline).foregroundStyle(Color.q.feltInk)
                }
                Spacer()
                Stamp(data: StampData(kind: .first_step))
                    .scaleEffect(stamped || reduceMotion ? 1 : 1.4)
                    .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -12))
                    .opacity(stamped ? 1 : 0)
            }
            .padding(.top, Sp.sm)
            .overlay(alignment: .top) { Rectangle().fill(Color.q.feltLine).frame(height: 1) }
        }
        .padding(Sp.lg)
        .background(Color.q.feltGround, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
