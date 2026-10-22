// Shared by the app and the widget extension (JurWidgets): what a departure's Live Activity
// shows on the lock screen and in the Dynamic Island.
import ActivityKit
import Foundation
import SwiftUI

struct DepartureAttributes: ActivityAttributes {
    /// What can change while the activity runs.
    struct ContentState: Codable, Hashable {
        var going: Int
        var checkedIn: Bool
    }

    let eventId: UUID
    let title: String
    let place: String
    let sportEmoji: String
    let start: Date
    let end: Date
    /// Words in the app's language at the time the activity starts, so the extension
    /// needs no string catalog of its own.
    let words: Words

    struct Words: Codable, Hashable {
        /// "До старта"
        let startsIn: String
        /// "Выход" (the meeting point)
        let gate: String
        /// "Идут: {n}"
        let going: String
        /// "Вы на месте"
        let checkedIn: String
    }
}

/// The JÜR mark (two strides curling into a heart), drawn in a 100-unit box.
/// Same geometry as `HornShape` in the app.
struct JurMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * s, oy = rect.midY - 50 * s
        var path = Path()
        for right in [false, true] {
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + (right ? 100 - x : x) * s, y: oy + y * s)
            }
            path.move(to: p(50, 88))
            path.addCurve(to: p(14, 38), control1: p(30, 70), control2: p(14, 56))
            path.addCurve(to: p(40, 18), control1: p(14, 22), control2: p(28, 14))
            path.addCurve(to: p(40, 38), control1: p(50, 22), control2: p(50, 36))
            path.addCurve(to: p(33, 30), control1: p(34, 39), control2: p(30, 34))
        }
        return path
    }
}
