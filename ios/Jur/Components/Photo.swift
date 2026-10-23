// Remote photos that fade in once loaded, and the loading shimmer for skeletons.
import SwiftUI

/// A remote photo, scaled to fill. Drawn in the first frame when it's already in memory;
/// otherwise it fades in once loaded (from disk or the network) instead of popping.
/// `.thumb` for small places (avatars, grids, lists), `.full` for cards and full screen.
struct QPhoto<Placeholder: View>: View {
    let url: URL?
    var size: ImageLoader.Size = .full
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?
    @State private var shown: URL?

    init(url: URL?, size: ImageLoader.Size = .full, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.size = size
        self.placeholder = placeholder
        let hit = url.flatMap { ImageLoader.shared.cached($0, size) }
        _image = State(initialValue: hit)
        _shown = State(initialValue: hit == nil ? nil : url)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; shown = nil; return }
            if shown == url, image != nil { return }
            if let hit = ImageLoader.shared.cached(url, size) { image = hit; shown = url; return }
            if shown != url { image = nil }
            let loaded = await ImageLoader.shared.image(url, size)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.adaptive(Motion.fade)) { image = loaded; shown = url }
        }
    }
}

extension QPhoto where Placeholder == Color {
    init(url: URL?, size: ImageLoader.Size = .full, placeholder: Color = Color.q.line) {
        self.init(url: url, size: size) { placeholder }
    }
}

extension View {
    /// One slow light sweep across a skeleton while it loads. Stops when `active` turns
    /// false and never runs under Reduce Motion.
    func qShimmer(_ active: Bool = true) -> some View {
        modifier(Shimmer(active: active))
    }
}

private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.6)
                            .offset(x: phase * g.size.width * 1.3)
                            .blendMode(.plusLighter)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = -1
                        withAnimation(Motion.shimmer.repeatForever(autoreverses: false)) { phase = 1 }
                    }
                }
            }
    }
}
