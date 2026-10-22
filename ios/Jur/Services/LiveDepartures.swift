// Lock-screen countdowns ("Live Activities") for the events you're going to.
// iOS lets an app start one only while it's open, so this runs whenever events load
// (Discover, Events, an event changing): it starts a countdown for every event you
// joined that starts within the next 3 hours, updates the ones running, and ends the
// ones you left, that were cancelled or that are over.
import ActivityKit
import Foundation

@MainActor
enum LiveDepartures {
    /// How long before the start a countdown appears.
    static let lead: TimeInterval = 3 * 3600

    static func sync(_ events: [EventItem], emoji: (String) -> String) {
        let now = Date()
        let wanted = events.filter {
            $0.iAmGoing && !$0.cancelled && $0.end > now && $0.start.timeIntervalSince(now) < lead
        }
        let wantedIds = Set(wanted.map(\.id))

        for activity in Activity<DepartureAttributes>.activities
        where !wantedIds.contains(activity.attributes.eventId) && events.contains(where: { $0.id == activity.attributes.eventId }) {
            // Left or cancelled (the event is in the list but no longer wanted).
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        for activity in Activity<DepartureAttributes>.activities where activity.attributes.end < now {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for event in wanted {
            let state = DepartureAttributes.ContentState(going: event.goingCount, checkedIn: event.iCheckedIn)
            let content = ActivityContent(state: state, staleDate: event.end)
            if let running = Activity<DepartureAttributes>.activities.first(where: { $0.attributes.eventId == event.id }) {
                Task { await running.update(content) }
            } else {
                let attributes = DepartureAttributes(
                    eventId: event.id, title: event.title, place: event.meetingPoint,
                    sportEmoji: emoji(event.sportCode), start: event.start, end: event.end,
                    words: .init(startsIn: t("live.startsIn"), gate: t("live.gate"),
                                 going: t("live.going"), checkedIn: t("live.checkedIn")))
                _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
            }
        }
    }

    /// Signing out: nothing of this account stays on the lock screen.
    static func endAll() {
        for activity in Activity<DepartureAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
