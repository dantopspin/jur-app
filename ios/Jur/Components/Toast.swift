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
    }

    private(set) var current: Item?

    func show(_ text: String, symbol: String = "checkmark.circle.fill", error: Bool = false) {
        error ? Haptics.failure() : Haptics.success()
        let item = Item(text: text, symbol: error ? "exclamationmark.circle.fill" : symbol, isError: error)
        current = item
        UIAccessibility.post(notification: .announcement, argument: text)
        Task {
            try? await Task.sleep(for: .seconds(1.6))
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
                }
                .padding(.horizontal, Sp.lg)
                .padding(.vertical, Sp.md)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
            Spacer()
        }
        .padding(.top, Sp.sm)
        .animation(.spring(duration: 0.35), value: toasts.current)
        .allowsHitTesting(false)
    }
}
