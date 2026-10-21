// Remote photos that fade in once loaded, and the loading shimmer for skeletons.
import SwiftUI

/// A remote image, scaled to fill, that fades in when it arrives instead of popping.
struct QPhoto<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: Motion.fade)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill().transition(.opacity)
            } else {
                placeholder()
            }
        }
    }
}

extension QPhoto where Placeholder == Color {
    init(url: URL?, placeholder: Color = Color.q.line) {
        self.url = url
        self.placeholder = { placeholder }
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
