// A short confirmation that needs no decision ("Copied", "Boost on").
// Alerts are only for decisions and blocking errors.
import Observation
import SwiftUI

@MainActor
@Observable
final class ToastCenter {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let symbol: String
        let isError: Bool
        /// One quiet action at the end ("Вернуть"), and the toast stays a little longer.
        var actionTitle: String?
        var action: (() -> Void)?
        static func == (a: Item, b: Item) -> Bool { a.id == b.id }
    }

    private(set) var current: Item?

    /// Haptics: an error buzzes, a confirmation taps lightly. The big "success" buzz is kept
    /// for moments (a match, a check-in, a purchase), which call it themselves.
    func show(_ text: String, symbol: String = "checkmark.circle.fill", error: Bool = false) {
        error ? Haptics.failure() : Haptics.tick()
        present(Item(text: text, symbol: error ? "exclamationmark.circle.fill" : symbol, isError: error), for: 1.6)
    }

    /// A toast with one action, e.g. "Анкета пропущена · Вернуть". No haptic: it follows a gesture.
    func show(_ text: String, symbol: String, action title: String, _ action: @escaping () -> Void) {
        present(Item(text: text, symbol: symbol, isError: false, actionTitle: title, action: action), for: 4)
    }

    func dismiss() { current = nil }

    private func present(_ item: Item, for seconds: Double) {
        current = item
        UIAccessibility.post(notification: .announcement, argument: item.text)
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if current?.id == item.id { current = nil }
        }
    }
}

struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack {
            if let item = toasts.current {
                HStack(spacing: Sp.sm) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(item.isError ? Color.q.danger : Color.q.good)
                    Text(item.text).qText(.callout).foregroundStyle(Color.q.ink).lineLimit(2)
                    if let title = item.actionTitle, let action = item.action {
                        Button {
                            toasts.dismiss()
                            action()
                        } label: {
                            Text(title).qText(.callout).fontWeight(.bold).foregroundStyle(Color.q.blueText)
                                .frame(minHeight: Layout.rowMin - 12)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, Sp.xs)
                    }
                }
                .padding(.horizontal, Sp.lg)
                .padding(.vertical, Sp.md)
                .background(.regularMaterial, in: Capsule())
                .qElevated()
                .transition(Motion.reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
            Spacer()
        }
        .padding(.top, Sp.sm)
        .animation(Motion.adaptive(Motion.smooth), value: toasts.current)
        // Only a toast with an action takes touches; plain ones never block what's under them.
        .allowsHitTesting(toasts.current?.action != nil)
    }
}
