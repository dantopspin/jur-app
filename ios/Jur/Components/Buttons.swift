// Capsule buttons: primary (blue), accent (gold), secondary (tinted), ghost, danger (tinted red).
import SwiftUI

struct QButtonStyle: ButtonStyle {
    enum Variant { case primary, accent, secondary, ghost, danger, onBlue }
    var variant: Variant = .primary
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    private var colors: (bg: Color, fg: Color) {
        switch variant {
        case .primary: (Color.q.blue, .white)
        case .accent: (Color.q.gold, Color.q.onGold)
        case .secondary: (Color.q.blueTint, Color.q.blueText)
        case .ghost: (.clear, Color.q.blueText)
        case .danger: (Color.q.dangerTint, Color.q.danger)
        case .onBlue: (Color.white.opacity(0.16), .white)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.q(.headline))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .foregroundStyle(colors.fg)
            .frame(maxWidth: .infinity, minHeight: compact ? Layout.buttonHeightCompact : Layout.buttonHeight)
            .padding(.horizontal, compact ? Sp.lg : Sp.xl)
            .background(colors.bg, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !Motion.reduceMotion ? Motion.Press.capsule : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .animation(Motion.snappy, value: isEnabled)
    }
}

extension ButtonStyle where Self == QButtonStyle {
    static var qPrimary: QButtonStyle { QButtonStyle(variant: .primary) }
    static var qAccent: QButtonStyle { QButtonStyle(variant: .accent) }
    static var qSecondary: QButtonStyle { QButtonStyle(variant: .secondary) }
    static var qGhost: QButtonStyle { QButtonStyle(variant: .ghost) }
    static var qDanger: QButtonStyle { QButtonStyle(variant: .danger) }
    static var qOnBlue: QButtonStyle { QButtonStyle(variant: .onBlue) }
    static func q(_ variant: QButtonStyle.Variant, compact: Bool = false) -> QButtonStyle {
        QButtonStyle(variant: variant, compact: compact)
    }
}

/// A button that shows a spinner before its label while busy, without changing width.
struct BusyLabel: View {
    let title: String
    var systemImage: String?
    var busy = false
    /// spinner colour; match the button's text colour
    var spinner: Color = .white

    var body: some View {
        HStack(spacing: Sp.sm) {
            if busy {
                ProgressView().controlSize(.small).tint(spinner)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }
}
