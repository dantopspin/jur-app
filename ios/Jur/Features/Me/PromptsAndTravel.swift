// Prompts ("My perfect Sunday…", up to three) and travel mode (Pro: look in another city).
import SwiftUI

struct PromptsEditor: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var prompts: [PromptAnswer] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var choosing = false
    @State private var original: [PromptAnswer]?
    @State private var confirmLeave = false
    @FocusState private var focus: Int?

    private var dirty: Bool { loaded && original != nil && prompts != original }

    var body: some View {
        QForm {
            Section {
                Text(t("prompts.hint")).qText(.footnote).foregroundStyle(Color.q.muted)
            }
            ForEach(prompts.indices, id: \.self) { i in
                Section {
                    TextField(t("prompts.answer"), text: Binding(
                        get: { i < prompts.count ? prompts[i].answer : "" },
                        set: { if i < prompts.count { prompts[i] = PromptAnswer(key: prompts[i].key, answer: String($0.prefix(150))) } }),
                              axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: i)
                    if i < prompts.count, prompts[i].answer.count >= 120 {
                        HStack { Spacer(); CharCounter(count: prompts[i].answer.count, limit: 150) }
                    }
                    Button(t("common.delete"), role: .destructive) { prompts.remove(at: i) }
                } header: {
                    Text(t("prompts.\(prompts[i].key)")).qText(.callout).textCase(nil)
                }
            }
            if prompts.count < 3 {
                Section {
                    Button(t("prompts.add"), systemImage: "plus") { choosing = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.q.bg)
        .navigationTitle(t("prompts.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(dirty)
        .confirmationDialog(t("edit.unsavedTitle"), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(t("common.save")) { Task { await save() } }
            Button(t("edit.discard"), role: .destructive) { original = nil; dismiss() }
            Button(t("common.cancel"), role: .cancel) {}
        }
        .toolbar {
            if dirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { confirmLeave = true } label: {
                        Image(systemName: "chevron.backward").fontWeight(.semibold)
                            .accessibilityLabel(t("common.back"))
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("common.save")) { Task { await save() } }.disabled(!loaded || saving)
            }
        }
        .confirmationDialog(t("prompts.choose"), isPresented: $choosing, titleVisibility: .visible) {
            ForEach(Backend.promptKeys.filter { k in !prompts.contains { $0.key == k } }, id: \.self) { k in
                Button(t("prompts.\(k)")) {
                    prompts.append(PromptAnswer(key: k, answer: ""))
                    // Straight into typing the answer.
                    let i = prompts.count - 1
                    Task { try? await Task.sleep(for: .milliseconds(350)); focus = i }
                }
            }
            Button(t("common.cancel"), role: .cancel) {}
        }
        .task {
            guard !loaded, let id = session.userId else { return }
            prompts = (try? await Backend.myPrompts(userId: id)) ?? []
            original = prompts
            loaded = true
        }
    }

    private func save() async {
        guard let id = session.userId else { return }
        saving = true
        defer { saving = false }
        do {
            try await Backend.savePrompts(userId: id, prompts)
            original = prompts
            toasts.show(t("edit.saved"))
            dismiss()
        } catch { toasts.show(error) }
    }
}

struct TravelView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var city = "astana"
    @State private var days = 7
    @State private var busy = false
    @State private var paywall = false

    private var activeUntil: Date? {
        session.profile?.travelUntil.flatMap { Date.iso($0) }.flatMap { $0 > .now ? $0 : nil }
    }

    var body: some View {
        QForm {
            Section { Text(t("travel.hint")).qText(.callout).foregroundStyle(Color.q.inkSoft) }
            if let until = activeUntil, let c = session.profile?.travelCity {
                Section {
                    Label(t("travel.active", ["city": Cities.label(c), "date": Fmt.dayTime(until)]), systemImage: "airplane")
                    Button(t("travel.end"), role: .destructive) { Task { await end() } }.disabled(busy)
                }
            } else {
                Section {
                    Picker(t("travel.pickCity"), selection: $city) {
                        ForEach(Cities.all.filter { $0 != session.profile?.city }, id: \.self) { Text(Cities.label($0)).tag($0) }
                    }
                    Stepper(t("travel.days", ["n": days]), value: $days, in: 1...14)
                }
                Section {
                    Button { Task { await start() } } label: { BusyLabel(title: t("common.save"), busy: busy) }
                        .buttonStyle(.qPrimary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.q.bg)
        .navigationTitle(t("travel.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $paywall) { PaywallView() }
    }

    private func start() async {
        busy = true
        defer { busy = false }
        do {
            let r = try await Backend.setTravel(city: city, days: days)
            if r.ok { await session.refreshProfile(); Haptics.tick(); dismiss() }
            else if r.error == "pro_only" { paywall = true }
            else { toasts.show(t("common.error"), error: true) }
        } catch { toasts.show(error) }
    }

    private func end() async {
        busy = true
        defer { busy = false }
        try? await Backend.clearTravel()
        await session.refreshProfile()
    }
}
