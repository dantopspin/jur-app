// Edit profile: photos, words, sports, who you want to meet.
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

    var body: some View {
        Form {
            Section(t("onboarding.photosTitle")) {
                PhotoGrid(photos: $photos, pickerItems: $pickerItems, uploading: uploading)
                    .listRowInsets(EdgeInsets(top: Sp.md, leading: Sp.md, bottom: Sp.md, trailing: Sp.md))
            }
            Section {
                TextField(t("onboarding.namePlaceholder"), text: $name)
                TextField(t("onboarding.challengePlaceholder"), text: $challenge, axis: .vertical).lineLimit(1...2)
                TextField(t("onboarding.bioPlaceholder"), text: $bio, axis: .vertical).lineLimit(3...6)
            }
            Section(t("onboarding.sportsTitle")) {
                SportPicker(picked: $sports)
                    .listRowInsets(EdgeInsets(top: Sp.md, leading: Sp.md, bottom: Sp.md, trailing: Sp.md))
            }
            Section {
                Picker(t("onboarding.cityTitle"), selection: $city) {
                    ForEach(Cities.all, id: \.self) { Text(Cities.label($0)).tag($0) }
                }
            } footer: {
                // Who to show and their age moved to the filter button on Discover.
                Text(t("edit.filtersMoved")).qText(.footnote).foregroundStyle(Color.q.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.q.bg)
        .navigationTitle(t("edit.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(t("common.save")) { Task { await save() } }
                    .disabled(!loaded || saving || uploading || photos.isEmpty || sports.isEmpty
                              || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task { await load() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty, let id = session.userId else { return }
            Task {
                uploading = true
                defer { uploading = false; pickerItems = [] }
                for item in items where photos.count < 6 {
                    if let url = try? await Media.uploadProfilePhoto(item, userId: id) { photos.append(url) }
                }
            }
        }
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
        loaded = true
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
            await session.refreshProfile()
            toasts.show(t("edit.saved"))
            dismiss()
        } catch { toasts.show(t("common.error"), error: true) }
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
        } catch { toasts.show(t("common.error"), error: true) }
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
