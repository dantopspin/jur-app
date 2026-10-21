// Motion tokens: every animation in the app comes from here. A raw duration or spring
// in a view is a bug, like a raw spacing number. Under Reduce Motion, movement, scale
// and rotation become a fade and nothing loops; haptics and sounds stay.
import SwiftUI
import UIKit

enum Motion {
    /// Press states, selection, toggles, swapped icons, small state changes.
    static let snappy = Animation.spring(duration: 0.25, bounce: 0)
    /// Content inserted or removed, layout changes, list rows, step changes.
    static let smooth = Animation.spring(duration: 0.35, bounce: 0)
    /// Confirmations with character: a reaction landing, a tag appearing, super like.
    static let bouncy = Animation.spring(duration: 0.45, bounce: 0.2)
    /// Once-per-moment entrances: match, Pro cover, passport flip.
    static let hero = Animation.spring(duration: 0.6, bounce: 0.25)
    /// Anything under the finger: card drag, snap-back after release.
    static let follow = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.8)
    /// Things leaving for good: a card flung off screen.
    static let exit = Animation.easeIn(duration: 0.18)
    /// Opacity-only changes, and the Reduce Motion fallback for everything else.
    static let fade = Animation.easeOut(duration: 0.2)
    /// The brand mark drawing its horns in (an ease-out-expo, the mark's own curve).
    static let draw = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.6)
    /// A skeleton's light sweep (loading only).
    static let shimmer = Animation.linear(duration: 1.4)
    /// The mark loader breathing in and out (loading only).
    static let loader = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.7)

    /// Delay between items that arrive together (board rows, staggered titles).
    static let stagger: Double = 0.03

    enum Press {
        static let capsule: CGFloat = 0.98
        static let round: CGFloat = 0.92
        static let card: CGFloat = 0.98
    }

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The animation, or a plain fade under Reduce Motion.
    static func adaptive(_ animation: Animation) -> Animation { reduceMotion ? fade : animation }
}

/// `withAnimation` that respects Reduce Motion.
@MainActor @discardableResult
func withMotion<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.adaptive(animation), body)
}

extension AnyTransition {
    /// The next Discover card rising from underneath.
    static var qCardIn: AnyTransition {
        Motion.reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .identity)
    }

    /// A card coming back (undo, a rolled-back like) from the side it left.
    static func qReturn(from edge: Edge) -> AnyTransition {
        Motion.reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .identity)
    }

    /// A chat bubble growing in from its sender's side.
    static func qBubble(mine: Bool) -> AnyTransition {
        Motion.reduceMotion ? .opacity
            : .asymmetric(insertion: .scale(scale: 0.9, anchor: mine ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                          removal: .opacity)
    }

    /// A step in a flow: in from the direction of travel, out the other way.
    static func qStep(forward: Bool) -> AnyTransition {
        let d: CGFloat = forward ? 24 : -24
        return Motion.reduceMotion ? .opacity
            : .asymmetric(insertion: .offset(x: d).combined(with: .opacity),
                          removal: .offset(x: -d).combined(with: .opacity))
    }

    /// A status tag or small badge appearing.
    static var qPop: AnyTransition {
        Motion.reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }

    /// A departure-board row updating: drops in a few points and fades.
    static var qBoardRow: AnyTransition {
        Motion.reduceMotion ? .opacity
            : .asymmetric(insertion: .offset(y: -8).combined(with: .opacity), removal: .opacity)
    }

    /// Something rising from the composer or a bottom bar.
    static var qRise: AnyTransition {
        Motion.reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}

/// Press feedback for things that aren't capsule buttons: round actions, tappable cards.
struct QPressStyle: ButtonStyle {
    var scale: CGFloat = Motion.Press.round

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && Motion.reduceMotion ? 0.7 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QPressStyle {
    static var qPress: QPressStyle { QPressStyle() }
    static var qPressCard: QPressStyle { QPressStyle(scale: Motion.Press.card) }
}

/// Feedback for view state changes. One place, so the map in the motion spec holds.
extension SensoryFeedback {
    /// A swipe crossing the like / pass line, a card flipping, a photo page.
    static let qThreshold = SensoryFeedback.impact(flexibility: .soft, intensity: 0.7)
    /// Long-press menus, recording starts.
    static let qKnock = SensoryFeedback.impact(weight: .medium)
}
