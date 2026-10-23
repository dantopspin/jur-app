// Profile editors shared with Edit profile: sports as chips (tap again for the level) and
// the photo grid. Onboarding has its own versions (OnboardingParts.swift).
import PhotosUI
import SwiftUI

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
                    SportChip(label: "\(s.emoji) \(s.name)", selected: picked[s.code] != nil) {
                        withMotion(Motion.snappy) { picked[s.code] = picked[s.code] == nil ? .casual : nil }
                    }
                }
            }
            if !picked.isEmpty {
                Text(t("flow.sportsCount", ["n": picked.count])).qText(.footnote).foregroundStyle(Color.q.muted)
            }
        }
    }
}

/// Up to six photos in a 3-column grid; the first is the main photo.
struct PhotoGrid: View {
    @Binding var photos: [String]
    @Binding var pickerItems: [PhotosPickerItem]
    var uploading = false
    /// Tap on a photo: open it full screen (by its position).
    var onOpen: ((Int) -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Sp.sm), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Sp.sm) {
            ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                Color.q.line
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay {
                        QPhoto(url: URL(string: url), size: .thumb)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            // By value, not position: a stale index must never remove the wrong photo (or crash).
                            photos.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .font(.q(.title3))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(t("common.delete"))
                        // In a Form row, buttons without their own style all fire on any tap in
                        // the row (tapping a photo deleted every photo and crashed). Borderless
                        // makes each one answer only to its own tap.
                        .buttonStyle(.borderless)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if index == 0 { QTag(label: t("edit.main"), tone: .gold).padding(Sp.sm) }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .onTapGesture { onOpen?(index) }
                    // Hold and drag onto another photo to swap places; the first one is the main photo.
                    .draggable(url) {
                        QPhoto(url: URL(string: url), size: .thumb)
                            .frame(width: 90, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let moved = items.first, let from = photos.firstIndex(of: moved),
                              let to = photos.firstIndex(of: url), from != to else { return false }
                        withMotion(Motion.smooth) {
                            photos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                        }
                        Haptics.tick()
                        return true
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: t("edit2.makeMain")) {
                        guard index > 0 else { return }
                        photos.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
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
                .buttonStyle(.borderless)
                .disabled(uploading)
            }
        }
    }
}

/// One of your photos full screen, from Edit profile: swipe between them, pinch or
/// double-tap to zoom, drag down to close; make it the main photo or remove it.
/// Changes go into the editor's list (saved with the rest of the profile).
struct PhotoViewer: View {
    @Binding var photos: [String]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var dragY: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(abs(dragY) / 600, 0.6)).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element) { i, url in
                    LoadedZoomablePhoto(url: URL(string: url)).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .offset(y: dragY)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { g in
                        guard abs(g.translation.height) > abs(g.translation.width) * 1.5 else { return }
                        dragY = max(g.translation.height, 0)
                    }
                    .onEnded { _ in
                        if dragY > 140 { dismiss() } else { withMotion(Motion.snappy) { dragY = 0 } }
                    }
            )
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel(t("common.close"))
                Spacer()
                Text(t("viewer.of", ["i": index + 1, "n": photos.count]))
                    .qText(.callout).fontWeight(.semibold).foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, Layout.margin)
            .opacity(dragY > 0 ? 0 : 1)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: Sp.sm) {
                Button { makeMain() } label: {
                    Label(t(index == 0 ? "edit.main" : "edit2.makeMain"), systemImage: index == 0 ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.q(.secondary))
                .disabled(index == 0)
                Button(role: .destructive) { remove() } label: {
                    Label(t("common.delete"), systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.q(.secondary))
                .tint(Color.q.clay)
            }
            .padding(.horizontal, Layout.margin)
            .padding(.bottom, Sp.sm)
            .opacity(dragY > 0 ? 0 : 1)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(dragY > 0)
    }

    private func makeMain() {
        guard index > 0, index < photos.count else { return }
        photos.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        index = 0
        Haptics.success()
    }

    private func remove() {
        guard index < photos.count else { return }
        photos.remove(at: index)
        Haptics.tick()
        if photos.isEmpty { dismiss() } else { index = min(index, photos.count - 1) }
    }
}

/// A full-size photo loaded through the app's image cache, then pinch-to-zoom.
struct LoadedZoomablePhoto: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { ZoomablePhoto(image: image) } else { ProgressView().tint(.white) }
        }
        .task(id: url) {
            guard let url else { return }
            image = ImageLoader.shared.cached(url, .full)
            if image == nil { image = await ImageLoader.shared.image(url, .full) }
        }
    }
}
