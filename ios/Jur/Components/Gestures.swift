// Small gestures used across the app: swipe a message to reply, and a photo you can pinch.
import SwiftUI
import UIKit

extension View {
    /// Drag a message to the right to reply to it (as in WhatsApp). The bubble follows the
    /// finger up to a point, an arrow fades in, and a tick says "let go to reply".
    /// Only clearly sideways drags count, so scrolling the chat is never caught.
    func swipeToReply(_ reply: @escaping () -> Void) -> some View {
        modifier(SwipeToReply(reply: reply))
    }
}

private struct SwipeToReply: ViewModifier {
    let reply: () -> Void
    @State private var dx: CGFloat = 0
    @State private var armed = false
    private let trigger: CGFloat = 56

    func body(content: Content) -> some View {
        content
            .offset(x: dx)
            .background(alignment: .leading) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.q(.callout))
                    .foregroundStyle(Color.q.blueText)
                    .frame(width: 32, height: 32)
                    .background(Color.q.blueTint, in: Circle())
                    .scaleEffect(armed ? 1 : 0.7)
                    .opacity(Double(min(dx / trigger, 1)))
                    .offset(x: -36 + min(dx, trigger) * 0.6)
                    .accessibilityHidden(true)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { g in
                        let x = g.translation.width, y = g.translation.height
                        guard x > 0, abs(x) > abs(y) * 1.6 else { return }
                        // Resistance past the trigger point.
                        dx = x < trigger ? x : trigger + (x - trigger) * 0.25
                        let now = x >= trigger
                        if now != armed { armed = now; if now { Haptics.tick() } }
                    }
                    .onEnded { _ in
                        if armed { reply() }
                        armed = false
                        withAnimation(Motion.adaptive(Motion.snappy)) { dx = 0 }
                    }
            )
    }
}

/// A full-screen photo: pinch or double-tap to zoom, drag around while zoomed.
struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        view.accessibilityIgnoresInvertColors = true
        scroll.addSubview(view)
        context.coordinator.imageView = view
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        DispatchQueue.main.async {
            guard let view = context.coordinator.imageView, scroll.zoomScale == 1 else { return }
            view.frame = scroll.bounds
            scroll.contentSize = scroll.bounds.size
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = g.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
            Haptics.tick()
        }
    }
}
