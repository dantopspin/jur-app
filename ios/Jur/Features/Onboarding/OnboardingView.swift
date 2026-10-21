// Profile setup: name → birthdate → gender → who to meet → city → sports → photos →
// about (optional) → notifications. One question per screen; the profile is created
// at the end, so a half-finished setup leaves nothing behind.
import PhotosUI
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case name, birth, gender, interested, city, sports, photos, about, notify }

    @Environment(SessionStore.self) private var session
    @Environment(SportsCatalog.self) private var catalog
    @State private var step: Step = .name
    @State private var name = UserDefaults.standard.string(forKey: "jur.prefillName") ?? ""
    @State private var birth = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var gender: Gender?
    @State private var interested: InterestedIn?
    @State private var city: String?
    @State private var picked: [String: Level] = [:]
    @State private var photos: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var bio = ""
    @State private var challenge = ""
    @State private var confirmAge = false
    @State private var saving = false
    @State private var error: String?

    private var latestBirth: Date { Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now }
    private var age: Int { Calendar.current.dateComponents([.year], from: birth, to: .now).year ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Sp.xl) {
                    content
                }
                .padding(.horizontal, Layout.margin)
                .padding(.top, Sp.lg)
                .padding(.bottom, Sp.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .background(Color.q.bg)
        .task { await catalog.load() }
        .alert(t("flow.confirmAge", ["age": age]), isPresented: $confirmAge) {
            Button(t("flow.confirmYes")) { go(.gender) }
            Button(t("flow.confirmEdit"), role: .cancel) {}
        } message: {
            Text(t("flow.confirmAgeSub"))
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await upload(items) }
        }
    }

    // MARK: chrome

    private var topBar: some View {
        HStack {
            if step == .name {
                Button(t("settings.signOut")) { Task { await session.signOut() } }
                    .font(.q(.callout))
            } else if step != .notify {
                Button { back() } label: { Image(systemName: "chevron.left").font(.q(.headline)) }
                    .accessibilityLabel(t("common.back"))
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            Spacer()
            progress
            Spacer()
            if step == .about {
                Button(t("flow.skip")) { Task { await finish() } }.font(.q(.callout))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Color.q.blueText)
        .padding(.horizontal, Layout.margin)
        .frame(minHeight: Layout.rowMin)
    }

    private var progress: some View {
        HStack(spacing: Sp.xs) {
            ForEach(0..<(Step.allCases.count - 1), id: \.self) { i in
                Capsule()
                    .fill(i <= step.rawValue ? Color.q.blue : Color.q.line)
                    .frame(width: i == step.rawValue ? 18 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: step)
        .accessibilityElement()
        .accessibilityLabel(t("onboarding.step", ["n": min(step.rawValue + 1, 8), "total": 8]))
    }

    private var bottomBar: some View {
        VStack(spacing: Sp.sm) {
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill").qText(.footnote).foregroundStyle(Color.q.danger)
            }
            Button(action: next) {
                BusyLabel(title: buttonTitle, busy: saving || uploading)
            }
            .buttonStyle(.qPrimary)
            .disabled(!canContinue || saving || uploading)
            if step == .notify {
                Button(t("flow.notifyLater")) { Task { await enterApp(askPush: false) } }
                    .buttonStyle(.qGhost)
            }
        }
        .padding(.horizontal, Layout.margin)
        .padding(.vertical, Sp.sm)
        .background(Color.q.bg)
    }

    private var buttonTitle: String {
        switch step {
        case .about: t("onboarding.finish")
        case .notify: t("flow.notifyAllow")
        default: t("common.continue")
        }
    }

    private var canContinue: Bool {
        switch step {
        case .name: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .birth: birth <= latestBirth
        case .gender: gender != nil
        case .interested: interested != nil
        case .city: city != nil
        case .sports: !picked.isEmpty
        case .photos: !photos.isEmpty
        case .about, .notify: true
        }
    }

    // MARK: steps

    @ViewBuilder private var content: some View {
        switch step {
        case .name:
            title("onboarding.nameTitle")
            TextField(t("onboarding.namePlaceholder"), text: $name)
                .textContentType(.givenName)
                .submitLabel(.next)
                .onSubmit(next)
                .qField()
        case .birth:
            title("onboarding.birthTitle", hint: "onboarding.birthHint")
            DatePicker("", selection: $birth, in: ...latestBirth, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.locale, L10n.current.locale)
        case .gender:
            title("onboarding.genderTitle")
            choices([(Gender.woman, "onboarding.woman"), (.man, "onboarding.man")], selection: $gender)
        case .interested:
            title("onboarding.interestedTitle")
            choices([(InterestedIn.women, "onboarding.women"), (.men, "onboarding.men"), (.everyone, "onboarding.everyone")],
                    selection: $interested)
        case .city:
            title("onboarding.cityTitle")
            VStack(spacing: Sp.sm) {
                ForEach(Cities.all, id: \.self) { code in
                    choiceRow(Cities.label(code), selected: city == code) { city = code }
                }
            }
        case .sports:
            title("onboarding.sportsTitle", hint: "onboarding.sportsHint")
            SportPicker(picked: $picked)
        case .photos:
            title("onboarding.photosTitle", hint: "onboarding.photosHint")
            PhotoGrid(photos: $photos, pickerItems: $pickerItems, uploading: uploading)
        case .about:
            title("onboarding.challengeTitle")
            TextField(t("onboarding.challengePlaceholder"), text: $challenge, axis: .vertical)
                .lineLimit(1...2)
                .qField()
            Text(t("onboarding.bioTitle")).qText(.headline).foregroundStyle(Color.q.ink)
            TextField(t("onboarding.bioPlaceholder"), text: $bio, axis: .vertical)
                .lineLimit(3...6)
                .padding(.vertical, Sp.md)
                .qField()
        case .notify:
            VStack(spacing: Sp.lg) {
                Image(systemName: "bell.badge")
                    .font(.system(size: IconSize.hero))
                    .foregroundStyle(Color.q.blueText)
                    .padding(.top, Sp.xxl)
                    .accessibilityHidden(true)
                Text(t("flow.notifyTitle")).qText(.title1).multilineTextAlignment(.center)
                Text(t(Config.eventsEnabled ? "flow.notifySub" : "flow.notifySubApp"))
                    .qText(.body).foregroundStyle(Color.q.inkSoft).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func title(_ key: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            Text(t(key)).qText(.title1).foregroundStyle(Color.q.ink).accessibilityAddTraits(.isHeader)
            if let hint { Text(t(hint)).qText(.body).foregroundStyle(Color.q.inkSoft) }
        }
    }

    private func choices<T: Hashable>(_ options: [(T, String)], selection: Binding<T?>) -> some View {
        VStack(spacing: Sp.sm) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                choiceRow(t(options[i].1), selected: selection.wrappedValue == value) {
                    selection.wrappedValue = value
                }
            }
        }
    }

    private func choiceRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            HStack {
                Text(label).qText(.headline)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.q(.headline)) }
            }
            .foregroundStyle(selected ? .white : Color.q.ink)
            .padding(.horizontal, Sp.lg)
            .frame(minHeight: Layout.buttonHeight)
            .background(selected ? Color.q.blue : Color.q.card, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: flow

    private func next() {
        error = nil
        switch step {
        case .birth: confirmAge = true
        case .about: Task { await finish() }
        case .notify: Task { await enterApp(askPush: true) }
        default:
            if let n = Step(rawValue: step.rawValue + 1) { go(n) }
        }
    }

    private func back() {
        error = nil
        if let p = Step(rawValue: step.rawValue - 1) { go(p) }
    }

    private func go(_ s: Step) {
        withAnimation(.easeInOut(duration: 0.2)) { step = s }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        guard let id = session.userId else { return }
        uploading = true
        defer { uploading = false; pickerItems = [] }
        for item in items where photos.count < 6 {
            do { photos.append(try await Media.uploadProfilePhoto(item, userId: id)) }
            catch { self.error = t("common.error") }
        }
    }

    private func finish() async {
        guard let id = session.userId, let gender, let interested, let city else { return }
        saving = true
        error = nil
        defer { saving = false }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        let p = Backend.NewProfile(
            id: id, name: name.trimmingCharacters(in: .whitespaces), birthdate: f.string(from: birth),
            gender: gender.rawValue, interestedIn: interested.rawValue, city: city,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            nextChallenge: challenge.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            photos: photos, locale: L10n.current.rawValue)
        do {
            try await Backend.createProfile(p, sports: picked)
            UserDefaults.standard.removeObject(forKey: "jur.prefillName")
            go(.notify)
        } catch {
            self.error = t("common.error")
        }
    }

    private func enterApp(askPush: Bool) async {
        if askPush { await Push.enable() }
        await session.refreshProfile()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Sports as chips. First tap picks a sport (casual); later taps step through the levels;
/// past "competitive" it's removed.
struct SportPicker: View {
    @Binding var picked: [String: Level]
    @Environment(SportsCatalog.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            if catalog.all.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            FlowLayout(spacing: Sp.xs) {
                ForEach(catalog.all) { s in
                    let level = picked[s.code]
                    QChip(label: "\(s.emoji) \(s.name)", sub: level.map { t("levels.\($0.rawValue)") }, selected: level != nil) {
                        cycle(s.code)
                    }
                }
            }
            if !picked.isEmpty {
                Text(t("flow.sportsCount", ["n": picked.count])).qText(.footnote).foregroundStyle(Color.q.muted)
            }
        }
    }

    private func cycle(_ code: String) {
        let order: [Level] = [.casual, .regular, .competitive, .beginner]
        guard let current = picked[code] else { picked[code] = .casual; return }
        let i = order.firstIndex(of: current) ?? 0
        if i == order.count - 1 { picked[code] = nil } else { picked[code] = order[i + 1] }
    }
}

/// Up to six photos in a 3-column grid; the first is the main photo.
struct PhotoGrid: View {
    @Binding var photos: [String]
    @Binding var pickerItems: [PhotosPickerItem]
    var uploading = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Sp.sm), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Sp.sm) {
            ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                Color.q.line
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: URL(string: url)) { img in img.resizable().scaledToFill() } placeholder: { ProgressView() }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            photos.remove(at: index)
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
                        if index == 0 { QTag(label: t("edit.main"), tone: .gold).padding(Sp.sm) }
                    }
            }
            if photos.count < 6 {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6 - photos.count, matching: .images) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(Color.q.blueText, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        if uploading { ProgressView() } else {
                            Label(t("onboarding.addPhoto"), systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .font(.q(.title2))
                                .foregroundStyle(Color.q.blueText)
                        }
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                }
                .accessibilityLabel(t("onboarding.addPhoto"))
                .disabled(uploading)
            }
        }
    }
}
