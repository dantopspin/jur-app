// The type scale, mapped to iOS text styles so it follows Dynamic Type.
// Unbounded for headlines and numbers (never below 13 pt, never more than two lines);
// Manrope for everything people read or tap. Falls back to the system font if the
// font files haven't been added (see Resources/Fonts/README.md).
import SwiftUI
import UIKit

enum QType: CaseIterable {
    case hero, title1, title2, title3, headline, body, callout, footnote, caption, overline
    /// Small uppercase labels: field names, column headers, pills (11 pt, tracked).
    case label
    /// Times and counts in rows: Manrope ExtraBold 17, tabular figures.
    case number
    /// Member № and codes: Unbounded ExtraBold 34, tabular figures.
    case display

    var size: CGFloat {
        switch self {
        case .hero: 34
        case .title1: 28
        case .title2: 22
        case .title3: 18
        case .headline, .body: 17
        case .callout: 15
        case .footnote: 13
        case .caption, .overline: 12
        case .label: 11
        case .number: 17
        case .display: 34
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .hero, .title1, .title2, .title3: 4
        case .body: 6
        default: 3
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .hero: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption, .overline: .caption
        case .label: .caption2
        case .number: .headline
        case .display: .largeTitle
        }
    }

    /// PostScript font name and the system weight used when the font isn't installed.
    var face: (name: String, weight: Font.Weight) {
        switch self {
        case .hero, .title1: ("Unbounded-ExtraBold", .heavy)
        case .title2, .title3: ("Unbounded-Bold", .bold)
        case .headline: ("Manrope-Bold", .semibold)
        case .body: ("Manrope-Medium", .regular)
        case .callout: ("Manrope-SemiBold", .medium)
        case .footnote: ("Manrope-Medium", .regular)
        case .caption: ("Manrope-Bold", .semibold)
        case .overline, .label: ("Manrope-ExtraBold", .bold)
        case .number: ("Manrope-ExtraBold", .heavy)
        case .display: ("Unbounded-ExtraBold", .heavy)
        }
    }

    /// Dynamic Type ceiling: body text may grow a lot, headlines and labels a little.
    var maxSize: DynamicTypeSize {
        switch self {
        case .hero, .title1, .display: .xxxLarge
        case .title2, .title3, .overline, .label: .accessibility1
        case .headline, .caption, .number: .accessibility2
        case .body, .callout, .footnote: .accessibility3
        }
    }

    var tracking: CGFloat {
        switch self {
        case .hero: -0.4
        case .title1: -0.3
        case .overline: 2
        case .label: 1.5
        case .display: -0.5
        default: 0
        }
    }
}

extension Font {
    static func q(_ type: QType) -> Font {
        let f = qFont(type.face.name, size: type.size, relativeTo: type.textStyle, weight: type.face.weight)
        return type == .number || type == .display ? f.monospacedDigit() : f
    }

    /// A specific brand face at a size, scaling with Dynamic Type like `relativeTo`.
    /// Unbounded and Manrope lack several Kazakh letters (ә ғ қ ң ұ, and ө ү һ in Unbounded),
    /// so the Kazakh interface uses the system faces instead of mixing two fonts in one word.
    /// `latinOnly` text (the wordmark, "PRO") keeps the brand face in every language.
    static func qFont(_ name: String, size: CGFloat, relativeTo style: Font.TextStyle = .body,
                      weight: Font.Weight = .regular, latinOnly: Bool = false) -> Font {
        if latinOnly || L10n.current != .kk, UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: style)
        }
        let design: Font.Design = name.hasPrefix("Unbounded") ? .rounded : .default
        return .system(style, design: design).weight(weight)
    }
}

private struct QTextModifier: ViewModifier {
    let type: QType
    func body(content: Content) -> some View {
        content
            .font(.q(type))
            .tracking(type.tracking)
            .lineSpacing(type.lineSpacing)
            .textCase(type == .overline || type == .label ? .uppercase : nil)
            .dynamicTypeSize(...type.maxSize)
    }
}

extension View {
    /// `Text("…").qText(.title2)`: font, tracking, line spacing and Dynamic Type ceiling together.
    func qText(_ type: QType) -> some View { modifier(QTextModifier(type: type)) }
}

/// The parts UIKit draws need the brand faces set separately: navigation titles (Unbounded
/// ExtraBold large, Manrope ExtraBold inline), bar buttons, segmented controls, tab labels.
/// Kazakh uses the system faces, as in `Font.qFont`. Bars created after a language change
/// pick up the new style (the root view is rebuilt on a change).
@MainActor
enum QNavBar {
    static func apply() {
        let bar = UINavigationBar.appearance()
        let brand = L10n.current != .kk
        if brand, let large = UIFont(name: "Unbounded-ExtraBold", size: 30),
           let inline = UIFont(name: "Manrope-ExtraBold", size: 17) {
            bar.largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large, maximumPointSize: 40),
                .kern: -0.3,
            ]
            bar.titleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline, maximumPointSize: 24),
            ]
        } else {
            bar.largeTitleTextAttributes = nil
            bar.titleTextAttributes = nil
        }

        let face = { (name: String, size: CGFloat, style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont in
            if brand, let f = UIFont(name: name, size: size) {
                return UIFontMetrics(forTextStyle: style).scaledFont(for: f, maximumPointSize: size * 1.4)
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
        // Toolbar buttons ("Готово", "Сохранить").
        let button = UIBarButtonItem.appearance()
        for state: UIControl.State in [.normal, .highlighted, .disabled] {
            button.setTitleTextAttributes([.font: face("Manrope-SemiBold", 17, .body, .medium)], for: state)
        }
        // Segmented pickers (Today / Tomorrow / Weekend, Edit / Preview, filters).
        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: face("Manrope-SemiBold", 13, .footnote, .medium)], for: .normal)
        segmented.setTitleTextAttributes([.font: face("Manrope-ExtraBold", 13, .footnote, .bold)], for: .selected)
        // Tab bar labels.
        let tab = UITabBarItem.appearance()
        tab.setTitleTextAttributes([.font: face("Manrope-Bold", 10, .caption2, .semibold)], for: .normal)
    }
}
