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
