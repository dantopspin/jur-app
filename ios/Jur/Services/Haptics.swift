// Touch feedback for code that isn't a view (models, services, button actions).
// Views reacting to state use `.sensoryFeedback` with the map in Motion.swift.
// The big moments (match, super like, check-in) add sound.
import AVFoundation
import UIKit

@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notify = UINotificationFeedbackGenerator()

    /// Chips, choices, toggles, reactions.
    static func tick() { selection.selectionChanged(); selection.prepare() }
    /// A swipe crosses its threshold, a card flips, a photo pages.
    static func bump() { soft.impactOccurred(intensity: 0.7); soft.prepare() }
    /// Long-press menus, recording starts.
    static func knock() { medium.impactOccurred(); medium.prepare() }
    /// A stamp landing.
    static func thump() { rigid.impactOccurred(); rigid.prepare() }
    static func success() { notify.notificationOccurred(.success); notify.prepare() }
    static func failure() { notify.notificationOccurred(.error); notify.prepare() }

    /// Warm the generators before a gesture that will need them (a drag starting).
    static func prepare() { soft.prepare(); selection.prepare() }
}

/// The app's short sounds (Resources/Sounds). Ambient category: the ring/silent switch
/// mutes them and they never stop the person's music.
@MainActor
enum Sounds {
    enum Name: String { case match, like, `super`, checkin, message }
    private static var players: [Name: AVAudioPlayer] = [:]

    static func play(_ name: Name) {
        // Don't take the session from a voice note that's playing.
        if VoicePlayer.shared.playingPath == nil {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        }
        if players[name] == nil,
           let url = Bundle.main.url(forResource: name.rawValue, withExtension: "wav") {
            players[name] = try? AVAudioPlayer(contentsOf: url)
            players[name]?.volume = 0.6
        }
        guard let p = players[name] else { return }
        p.currentTime = 0
        p.play()
    }
}
