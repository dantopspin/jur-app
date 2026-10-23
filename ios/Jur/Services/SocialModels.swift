// What the server returns for other people, matches, messages and events.
// Mirrors profile_card / event_card / my_matches / chat_messages in SQL.
// Dates stay ISO strings; `Date.iso(_:)` parses them where they're shown.
import Foundation

enum SwipeKind: String, Codable { case pass, like, `super` }
enum Level: String, Codable, CaseIterable { case beginner, casual, regular, competitive }

struct CardSport: Codable, Hashable { let code: String; let level: Level? }
struct PromptAnswer: Codable, Hashable { let key: String; let answer: String }
struct Achievement: Codable, Hashable { let title: String; let result: String?; let sport: String? }

/// Another person, as `profile_card` shapes them.
struct ProfileCard: Decodable, Identifiable, Hashable {
    let id: UUID
    let memberNo: Int
    let name: String
    let age: Int
    let city: String
    let bio: String?
    let nextChallenge: String?
    let photos: [String]
    let verified: Bool
    let isHost: Bool?
    let eventsAttended: Int?
    let sports: [CardSport]?
    let achievements: [Achievement]?
    let prompts: [PromptAnswer]?
    let memberSince: String?
    let travelCity: String?
    let badges: [String]?
    let cityNo: Int?
    // only in discover / likes
    let sharedSports: Int?
    let superLikedMe: Bool?
    let boosted: Bool?
    let note: String?
    // only in daily picks: what you already decided today
    var mySwipe: SwipeKind? = nil

    var photoURLs: [URL] { photos.compactMap(URL.init(string:)) }
    var stamps: [StampData] {
        (badges ?? []).compactMap { StampKind(rawValue: $0) }.map { kind in
            switch kind {
            case .founding: StampData(kind: kind, detail: cityNo.map { String(format: "%04d", $0) })
            default: StampData(kind: kind)
            }
        }
    }
}

/// Friends who joined with your code, and how many more until the next free Pro week.
struct Referrals: Decodable, Equatable {
    /// Friends who are verified (they count towards Pro).
    let count: Int
    /// Joined with your code but not verified yet.
    let pending: Int?
    let every: Int
    let toNext: Int
    let bonusDays: Int
}

struct SwipeResult: Decodable {
    let ok: Bool
    let error: String?
    let matchId: UUID?
}

/// Saying yes to a date at an event: `joined` is false when the event had no spot left.
struct DateAnswer: Decodable {
    let ok: Bool
    let error: String?
    let joined: Bool?
    let reason: String?
}

/// "too_many_tries" comes with the time the next try is allowed.
struct CheckInResult: Decodable {
    let ok: Bool
    let error: String?
    let retryAt: String?
}

struct RewindResult: Decodable {
    let ok: Bool
    let error: String?
    let profile: ProfileCard?
}

struct LikesReceived: Decodable {
    let count: Int
    let profiles: [ProfileCard]
}

struct LastMessage: Decodable, Hashable {
    let body: String
    let senderId: UUID
    let createdAt: String
    let kind: String?
}

struct MatchRow: Decodable, Identifiable, Hashable {
    let matchId: UUID
    let createdAt: String
    let other: ProfileCard
    let lastMessage: LastMessage?
    /// var: marking a chat read updates the row at once.
    var unread: Int
    var id: UUID { matchId }
}

/// The JSON a date suggestion carries (messages.payload). Every field optional:
/// an opener note uses the same column for its prompt.
struct DatePayload: Codable, Hashable {
    let sport: String?
    let when: String?
    let place: String?
    let eventId: UUID?
    let status: String?
}

struct Message: Decodable, Identifiable, Hashable {
    let id: UUID
    let matchId: UUID
    let senderId: UUID
    let body: String
    let createdAt: String
    let readAt: String?
    let kind: String?
    let payload: DatePayload?
    let mediaPath: String?
    let mediaMs: Int?
    let replyTo: UUID?
    /// var: a reaction shows at once; the server's answer follows.
    var reactions: [MessageReaction]?
    let reply: ReplyPreview?

    var isDate: Bool { kind == "date" }
    var isPhoto: Bool { kind == "photo" }
    var isVoice: Bool { kind == "voice" }
    var isMedia: Bool { kind == "photo" || kind == "voice" }
}

struct MessageReaction: Decodable, Hashable { let profileId: UUID; let reaction: String }
struct ReplyPreview: Decodable, Hashable { let id: UUID; let body: String; let kind: String?; let senderId: UUID }

/// The five reactions the server accepts, and how they look.
enum Reactions {
    static let all: [(key: String, emoji: String)] = [("heart", "❤️"), ("fire", "🔥"), ("clap", "👏"), ("laugh", "😂"), ("thumbsup", "👍")]
    static func emoji(_ key: String) -> String { all.first { $0.key == key }?.emoji ?? "❤️" }
}

struct EventHost: Decodable, Hashable { let id: UUID; let name: String; let photo: String? }

struct EventItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let hostId: UUID?
    let city: String
    let sportCode: String
    let title: String
    let description: String?
    let meetingPoint: String
    let startsAt: String
    let durationMin: Int
    let capacity: Int
    let priceKzt: Int
    let cancelled: Bool
    /// var: joining and leaving update the screen at once.
    var goingCount: Int
    var iAmGoing: Bool
    let iCheckedIn: Bool
    let host: EventHost?

    var start: Date { Date.iso(startsAt) ?? .distantPast }
    var end: Date { start.addingTimeInterval(TimeInterval(durationMin * 60)) }
    var spotsLeft: Int { max(capacity - goingCount, 0) }
    var isFull: Bool { spotsLeft == 0 && !iAmGoing }
    /// Check-in opens 30 minutes before the start and closes at the end.
    var boardingOpen: Bool {
        let now = Date()
        return now >= start.addingTimeInterval(-30 * 60) && now <= end
    }

    var departureStatus: Departure.Status {
        if isFull { return .full }
        if boardingOpen { return .boarding }
        if spotsLeft <= 5 { return .spots(spotsLeft) }
        return .onTime
    }

    var departure: Departure {
        Departure(id: id, time: Fmt.time(start), title: title, place: meetingPoint, status: departureStatus)
    }
}

struct HostCode: Decodable { let ok: Bool; let error: String?; let code: String?; let secondsLeft: Int? }
struct GiftResult: Decodable { let ok: Bool; let error: String?; let code: String?; let days: Int? }
struct ProposeResult: Decodable { let ok: Bool; let error: String?; let messageId: UUID? }

struct Sport: Decodable, Identifiable, Hashable {
    let code: String
    let season: String
    let emoji: String
    let nameKk: String
    let nameRu: String
    let nameEn: String
    let sort: Int
    var id: String { code }
    var name: String {
        switch L10n.current {
        case .kk: nameKk
        case .ru: nameRu
        case .en: nameEn
        }
    }
}

/// The cities JÜR runs in. Labels come from `cities.*`.
enum Cities {
    static let all = ["almaty", "astana", "shymkent", "karaganda", "aktobe", "atyrau", "oskemen"]
    static func label(_ code: String) -> String {
        let s = t("cities.\(code)")
        return s == "cities.\(code)" ? code.capitalized : s
    }
}

// MARK: dates

extension Date {
    static func iso(_ s: String) -> Date? { ISO8601DateFormatter.flexible(s) }
}

/// Formatting in the app's language, on Almaty time.
enum Fmt {
    static let zone = TimeZone(identifier: "Asia/Almaty") ?? .current
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = L10n.current.locale
        c.firstWeekday = 2
        return c
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.current.locale
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// "19:00"
    static func time(_ d: Date) -> String { formatter("HH:mm").string(from: d) }
    /// "Sat 25 Oct · 09:30"
    /// "Sat 25 Oct" in the app's language.
    static func day(_ d: Date) -> String { formatter("EEE d MMM").string(from: d) }
    static func dayTime(_ d: Date) -> String { formatter("EEE d MMM").string(from: d) + " · " + time(d) }
    /// "Oct 2026"
    static func monthYear(_ d: Date) -> String { formatter("MMM yyyy").string(from: d) }
    /// "18:42" today, "Mon" this week, "21 Oct" before that.
    static func relative(_ d: Date) -> String {
        let cal = calendar
        if cal.isDateInToday(d) { return time(d) }
        if let days = cal.dateComponents([.day], from: d, to: .now).day, days < 7 { return formatter("EEE").string(from: d) }
        return formatter("d MMM").string(from: d)
    }
}
