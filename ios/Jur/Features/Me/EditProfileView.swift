// Your profile, two tabs: Edit (photos, words, sports, prompts, verification) and
// Preview (your card as others see it). Tap a photo to look at it; hold and drag to reorder.
import AVFoundation
import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploading = false
    /// Uploaded on this visit: removed from storage if the edit is thrown away.
    @State private var uploadedNow: [String] = []
    @State private var name = ""
    @State private var bio = ""
    @State private var challenge = ""
    @State private var city = "almaty"
    @State private var interested: InterestedIn = .everyone
    @State private var ageMin = 18
    @State private var ageMax = 60
    @State private var sports: [String: Level] = [:]
    @State private var loaded = false
    @State private var saving = false
    @FocusState private var focus: Field?
    /// What was loaded, to tell whether anything changed.
    @State private var original: Snapshot?
    @State private var confirmLeave = false
    @State private var tab: Tab = .edit
    @State private var preview: ProfileCard?
    @State private var prompts: [PromptAnswer] = []
    /// The photo open full screen.
    @State private var viewing: PhotoIndex?

    private enum Tab: Hashable { case edit, preview }
    struct PhotoIndex: Identifiable { let id: Int }

    private enum Field { case name, challenge, bio }

    private struct Snapshot: Equatable {
        var photos: [String], name: String, bio: String, challenge: String, city: String, sports: [String: Level]
    }

    private var current: Snapshot {
        Snapshot(photos: photos, name: name, bio: bio, challenge: challenge, city: city, sports: sports)
    }

    /// Unsaved edits: going back asks first (and the back swipe waits for the answer).
    private var dirty: Bool { loaded && original != nil && current != original }

    var body: some View {
        Form {
            Section {
                Picker("", selection: $tab) {
                    Text(t("edit2.tabEdit")).tag(Tab.edit)
                    Text(t("edit2.tabPreview")).tag(Tab.preview)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: tab)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if tab == .edit { editSections } else { previewSection }
        }
        .animation(Motion.adaptive(Motion.fade), value: tab)
        .fullScreenCover(item: $viewing) { v in PhotoViewer(photos: $photos, index: v.id) }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.q.bg)
        .navigationTitle(t("edit.title"))
        .navigationBarTitleDisplayMode(.inline)
        // With unsaved edits the system back button (and its swipe) gives way to one that asks.
        .navigationBarBackButtonHidden(dirty)
        .confirmationDialog(t("edit.unsavedTitle"), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(t("common.save")) { Task { await save() } }
            Button(t("edit.discard"), role: .destructive) {
                let unused = uploadedNow
                uploadedNow = []
                Task { await Media.deletePhotos(unused) }
                original = nil
                dismiss()
            }
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
                Button(t("common.save")) { Task { await save() } }
                    .disabled(!loaded || saving || uploading || photos.isEmpty || sports.isEmpty
                              || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task { await load() }
        // Also when coming back from the prompts editor.
        .onAppear { Task { await loadPrompts() } }
        .task(id: tab) { if tab == .preview { await loadPreview() } }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty, let id = session.userId else { return }
            Task {
                uploading = true
                defer { uploading = false; pickerItems = [] }
                for item in items where photos.count < 6 {
                    do {
                        let url = try await Media.uploadProfilePhoto(item, userId: id)
                        photos.append(url)
                        uploadedNow.append(url)
                    } catch {
                        toasts.show(error)
                    }
                }
            }
        }
    }

    // MARK: tabs

    @ViewBuilder private var editSections: some View {
        Section {
            PhotoGrid(photos: $photos, pickerItems: $pickerItems, uploading: uploading) { viewing = PhotoIndex(id: $0) }
                .listRowInsets(EdgeInsets(top: Sp.md, leading: Sp.md, bottom: Sp.md, trailing: Sp.md))
        } header: {
            Text(t("onboarding.photosTitle"))
        } footer: {
            Text(t("edit2.photosHint")).qText(.footnote).foregroundStyle(Color.q.muted)
        }
        Section(t("edit2.about")) {
            // Return walks name → goal → about; "about" keeps Return for new lines.
            field(count: name.count, limit: 40) {
                TextField(t("onboarding.namePlaceholder"), text: $name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .name)
                    .limited($name, to: 40)
                    .returnGoesNext($name) { focus = .challenge }
            }
            field(count: challenge.count, limit: 80) {
                TextField(t("onboarding.challengePlaceholder"), text: $challenge, axis: .vertical)
                    .lineLimit(1...2)
                    .submitLabel(.next)
                    .focused($focus, equals: .challenge)
                    .limited($challenge, to: 80)
                    .returnGoesNext($challenge) { focus = .bio }
            }
            field(count: bio.count, limit: 500) {
                TextField(t("onboarding.bioPlaceholder"), text: $bio, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focus, equals: .bio)
                    .limited($bio, to: 500)
            }
        }
        Section(t("onboarding.sportsTitle")) {
            SportPicker(picked: $sports)
                .listRowInsets(EdgeInsets(top: Sp.md, leading: Sp.md, bottom: Sp.md, trailing: Sp.md))
        }
        Section {
            ForEach(prompts, id: \.key) { p in
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("prompts.\(p.key)")).qText(.footnote).foregroundStyle(Color.q.muted)
                    Text(p.answer).qText(.body).foregroundStyle(Color.q.ink)
                }
                .padding(.vertical, Sp.xxs)
            }
            NavigationLink { PromptsEditor() } label: {
                Label(t(prompts.isEmpty ? "prompts.add" : "edit2.promptsEdit"), systemImage: prompts.isEmpty ? "plus" : "text.quote")
                    .foregroundStyle(Color.q.blueText)
            }
        } header: {
            Text(t("edit2.prompts", ["n": prompts.count]))
        }
        if let p = session.profile {
            Section(t("edit2.trust")) { verificationRow(p.verificationStatus) }
        }
    }

    @ViewBuilder private var previewSection: some View {
        Section {
            if let preview {
                ProfileCardView(card: preview)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else {
                AfterABlink {
                    ProfileCardView(card: .placeholder).redacted(reason: .placeholder).qShimmer()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } footer: {
            Text(t(dirty ? "edit2.previewUnsaved" : "me2.previewNote")).qText(.footnote).foregroundStyle(Color.q.muted)
        }
    }

    @ViewBuilder private func verificationRow(_ status: Verification) -> some View {
        switch status {
        case .approved:
            Label(t("me.verified"), systemImage: "checkmark.seal.fill").foregroundStyle(Color.q.good)
        case .pending:
            Label(t("me.verifyPending"), systemImage: "clock").foregroundStyle(Color.q.muted)
        case .rejected:
            NavigationLink { VerifyView() } label: { Label(t("me.verifyRejected"), systemImage: "exclamationmark.triangle") }
        case .unverified:
            NavigationLink { VerifyView() } label: { Label(t("me.verify"), systemImage: "checkmark.seal") }
        }
    }

    private func loadPrompts() async {
        guard let id = session.userId, let p = try? await Backend.myPrompts(userId: id) else { return }
        prompts = p
    }

    private func loadPreview() async {
        guard let id = session.userId, let c = try? await Backend.myCard(id) else { return }
        withMotion(Motion.fade) { preview = c }
    }

    private func load() async {
        guard !loaded, let p = session.profile else { return }
        photos = p.photos
        name = p.name
        bio = p.bio ?? ""
        challenge = p.nextChallenge ?? ""
        city = p.city
        interested = p.interestedIn
        ageMin = p.ageMin ?? 18
        ageMax = p.ageMax ?? 60
        sports = (try? await Backend.mySports(userId: p.id)) ?? [:]
        original = current
        loaded = true
    }

    /// A field with its counter underneath (the counter shows only near the limit).
    private func field<Content: View>(count: Int, limit: Int, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .trailing, spacing: Sp.xxs) {
            content()
            CharCounter(count: count, limit: limit)
        }
        .animation(Motion.adaptive(Motion.snappy), value: Double(count) >= Double(limit) * 0.8)
    }

    private func save() async {
        guard let id = session.userId else { return }
        saving = true
        defer { saving = false }
        let u = Backend.ProfileUpdate(
            name: name.trimmingCharacters(in: .whitespaces), interestedIn: interested.rawValue, ageMin: ageMin, ageMax: ageMax,
            city: city, bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            nextChallenge: challenge.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, photos: photos)
        do {
            try await Backend.updateProfile(userId: id, u, sports: sports)
            // Photos that were on the profile or uploaded now, and aren't kept: gone from storage.
            let dropped = Set((original?.photos ?? []) + uploadedNow).subtracting(photos)
            uploadedNow = []
            Task { await Media.deletePhotos(dropped) }
            await session.refreshProfile()
            original = current
            toasts.show(t("edit.saved"))
            dismiss()
        } catch { toasts.show(error) }
    }
}

/// Verification: a thumbs-up selfie from the camera, reviewed by a moderator, never shown.
struct VerifyView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var camera = false
    @State private var cameraOff = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: Sp.xl) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: IconSize.hero))
                .foregroundStyle(Color.q.blueText)
                .padding(.top, Sp.xxl)
                .accessibilityHidden(true)
            Text(t("verify.title")).qText(.title1).multilineTextAlignment(.center)
            Text(t("verify.body")).qText(.body).foregroundStyle(Color.q.inkSoft).multilineTextAlignment(.center)
            Spacer()
            Button { Task { await openCamera() } } label: { BusyLabel(title: t("verify.take"), systemImage: "camera", busy: busy) }
                .buttonStyle(.qPrimary)
                .disabled(busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
        }
        .padding(Layout.margin)
        .background(Color.q.bg)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in Task { await submit(image) } }.ignoresSafeArea()
        }
        .permissionAlert(isPresented: $cameraOff, title: t("perm.cameraTitle"), message: t("perm.cameraBody"))
    }

    /// iOS asks on the first tap; if the camera was turned off, say so and offer Settings
    /// instead of opening a black camera screen.
    private func openCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { camera = true } else { cameraOff = true }
        default: cameraOff = true
        }
    }

    private func submit(_ image: UIImage) async {
        guard let id = session.userId, let data = image.jpegData(compressionQuality: 0.8), let jpeg = Media.jpeg(from: data) else { return }
        busy = true
        defer { busy = false }
        do {
            let path = try await Media.uploadSelfie(jpeg, userId: id)
            try await Backend.requestVerification(selfiePath: path)
            await session.refreshProfile()
            toasts.show(t("verify.sent"))
            dismiss()
        } catch { toasts.show(error) }
    }
}

/// The front camera, for the verification selfie.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.cameraDevice = .front
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
