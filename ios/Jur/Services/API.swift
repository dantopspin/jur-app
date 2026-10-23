// Typed calls for milestone 2. Every rule (limits, matching, check-in codes, gifts)
// lives in SQL; these only pass arguments and decode results.
import Foundation
import Supabase

extension AnyJSON {
    static func uuid(_ id: UUID) -> AnyJSON { .string(id.uuidString.lowercased()) }
    static func optional(_ s: String?) -> AnyJSON {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .null }
        return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Errors the database functions return as `{ ok: false, error }`.
struct ServerError: LocalizedError {
    let code: String
    var errorDescription: String? { code }
}

extension Backend {
    static var me: UUID? { supabase.auth.currentUser?.id }

    // MARK: catalog

    static func sports() async throws -> [Sport] {
        let r = try await supabase.from("sports").select().order("sort").execute()
        return try decoder.decode([Sport].self, from: r.data)
    }

    // MARK: profile

    struct NewProfile: Encodable {
        let id: UUID
        let name: String
        let birthdate: String
        let gender: String
        let interestedIn: String
        let city: String
        let bio: String?
        let nextChallenge: String?
        let photos: [String]
        let locale: String
        enum CodingKeys: String, CodingKey {
            case id, name, birthdate, gender, city, bio, photos, locale
            case interestedIn = "interested_in", nextChallenge = "next_challenge"
        }
    }

    struct SportRow: Codable {
        let profileId: UUID
        let sportCode: String
        let level: String
        enum CodingKeys: String, CodingKey { case profileId = "profile_id", sportCode = "sport_code", level }
    }

    static func createProfile(_ p: NewProfile, sports: [String: Level]) async throws {
        try await supabase.from("profiles").insert(p).execute()
        try await replaceSports(userId: p.id, sports: sports)
    }

    struct ProfileUpdate: Encodable {
        let name: String
        let interestedIn: String
        let ageMin: Int
        let ageMax: Int
        let city: String
        let bio: String?
        let nextChallenge: String?
        let photos: [String]
        enum CodingKeys: String, CodingKey {
            case name, city, bio, photos
            case interestedIn = "interested_in", ageMin = "age_min", ageMax = "age_max", nextChallenge = "next_challenge"
        }
    }

    static func updateProfile(userId: UUID, _ u: ProfileUpdate, sports: [String: Level]) async throws {
        try await supabase.from("profiles").update(u).eq("id", value: userId.uuidString).execute()
        try await replaceSports(userId: userId, sports: sports)
    }

    static func mySports(userId: UUID) async throws -> [String: Level] {
        let r = try await supabase.from("profile_sports").select("profile_id, sport_code, level")
            .eq("profile_id", value: userId.uuidString).execute()
        let rows = try JSONDecoder().decode([SportRow].self, from: r.data)
        return Dictionary(rows.map { ($0.sportCode, Level(rawValue: $0.level) ?? .casual) }, uniquingKeysWith: { a, _ in a })
    }

    private static func replaceSports(userId: UUID, sports: [String: Level]) async throws {
        try await supabase.from("profile_sports").delete().eq("profile_id", value: userId.uuidString).execute()
        let rows = sports.map { SportRow(profileId: userId, sportCode: $0.key, level: $0.value.rawValue) }
        if !rows.isEmpty { try await supabase.from("profile_sports").insert(rows).execute() }
    }

    static func profile(_ id: UUID) async throws -> ProfileCard? {
        try await rpc("get_profile", ["p_id": .uuid(id)], as: ProfileCard?.self)
    }

    /// Your own card (stamps, prompts), kept for next time.
    static func myCard(_ id: UUID) async throws -> ProfileCard? {
        try await rpc("get_profile", ["p_id": .uuid(id)], cacheAs: CacheKey.card, as: ProfileCard?.self)
    }

    static func requestVerification(selfiePath: String) async throws {
        try await call("request_verification", ["p_selfie_path": .string(selfiePath)])
    }

    // MARK: discover

    static func discover() async throws -> [ProfileCard] { try await rpc("discover", ["p_limit": .integer(20)]) }

    static func swipe(_ target: UUID, _ kind: SwipeKind, note: String? = nil) async throws -> SwipeResult {
        try await rpc("swipe", ["p_target": .uuid(target), "p_kind": .string(kind.rawValue), "p_note": .optional(note)])
    }

    static func rewind() async throws -> RewindResult { try await rpc("rewind") }

    // MARK: discover filters

    private static func filterParams(_ f: DiscoverFilters) -> [String: AnyJSON] {
        [
            "p_interested": .string(f.interested.rawValue),
            "p_age_min": .integer(f.ageMin), "p_age_max": .integer(f.ageMax),
            "p_sports": .array(f.sports.sorted().map { .string($0) }),
            "p_verified": .bool(f.verified), "p_attended": .bool(f.attended),
            "p_active_days": f.activeDays.map { .integer($0) } ?? .null,
        ]
    }

    /// How many people these filters would show (before saving them). Capped at 999.
    static func discoverCount(_ f: DiscoverFilters) async throws -> Int {
        var params = filterParams(f)
        params["p_clear_active"] = .bool(f.activeDays == nil)
        return try await rpc("discover_count", params)
    }

    static func saveDiscoverFilters(_ f: DiscoverFilters) async throws -> OkResult {
        try await rpc("set_discover_filters", filterParams(f))
    }
    static func likesReceived() async throws -> LikesReceived { try await rpc("likes_received", cacheAs: CacheKey.likes) }
    /// How many people you've liked so far (a total only).
    static func likesSent() async throws -> Int { try await rpc("my_likes_sent") }

    /// Widening the search from the empty Discover screen.
    private struct AgeRangeUpdate: Encodable {
        let ageMin: Int, ageMax: Int
        enum CodingKeys: String, CodingKey { case ageMin = "age_min", ageMax = "age_max" }
    }
    private struct ModeUpdate: Encodable { let mode: String }

    static func setAgeRange(userId: UUID, min: Int, max: Int) async throws {
        try await supabase.from("profiles").update(AgeRangeUpdate(ageMin: min, ageMax: max))
            .eq("id", value: userId.uuidString).execute()
    }

    private struct BuddyWithUpdate: Encodable {
        let buddyWith: String
        enum CodingKeys: String, CodingKey { case buddyWith = "buddy_with" }
    }

    static func setBuddyWith(userId: UUID, _ who: InterestedIn) async throws {
        try await supabase.from("profiles").update(BuddyWithUpdate(buddyWith: who.rawValue))
            .eq("id", value: userId.uuidString).execute()
    }

    /// Hidden from Discover and Likes while paused; matches and chats keep working.
    static func setPaused(_ paused: Bool) async throws {
        try await call("set_paused", ["p_paused": .bool(paused)])
    }

    static func referrals() async throws -> Referrals { try await rpc("my_referrals") }

    static func redeemReferral(_ code: String) async throws -> OkResult {
        try await rpc("redeem_referral", ["p_code": .string(code.trimmingCharacters(in: .whitespaces).uppercased())])
    }

    static func setMode(userId: UUID, _ mode: ProfileMode) async throws {
        try await supabase.from("profiles").update(ModeUpdate(mode: mode.rawValue))
            .eq("id", value: userId.uuidString).execute()
    }

    // MARK: matches and chat

    static func matches() async throws -> [MatchRow] { try await rpc("my_matches", cacheAs: CacheKey.matches) }

    /// Newest first from the server; returned oldest first for display.
    static func messages(_ match: UUID) async throws -> [Message] {
        let list: [Message] = try await rpc("chat_messages", ["p_match": .uuid(match)])
        return list.reversed()
    }

    struct NewMessage: Encodable {
        let matchId: UUID
        let senderId: UUID
        let body: String
        let replyTo: UUID?
        enum CodingKeys: String, CodingKey { case matchId = "match_id", senderId = "sender_id", body, replyTo = "reply_to" }
    }

    static func send(_ body: String, match: UUID, from me: UUID, replyTo: UUID? = nil) async throws -> Message {
        let r = try await supabase.from("messages")
            .insert(NewMessage(matchId: match, senderId: me, body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                               replyTo: replyTo))
            .select().single().execute()
        return try decoder.decode(Message.self, from: r.data)
    }

    /// Toggles a reaction (same one again removes it).
    static func react(_ message: UUID, _ reaction: String) async throws {
        try await call("react", ["p_message": .uuid(message), "p_reaction": .string(reaction)])
    }

    static func markRead(_ match: UUID) async throws { try await call("mark_read", ["p_match": .uuid(match)]) }
    static func unmatch(_ match: UUID) async throws { try await call("unmatch", ["p_match": .uuid(match)]) }

    static func proposeDate(match: UUID, sport: String?, when: Date, place: String) async throws -> ProposeResult {
        try await rpc("propose_date", [
            "p_match": .uuid(match), "p_sport": .optional(sport),
            "p_when": .string(ISO8601DateFormatter().string(from: when)), "p_place": .string(place),
            "p_event": .null,
        ])
    }

    static func respondDate(_ message: UUID, accept: Bool) async throws -> OkResult {
        try await rpc("respond_date", ["p_message": .uuid(message), "p_answer": .string(accept ? "accepted" : "declined")])
    }

    // MARK: safety

    struct BlockRow: Encodable {
        let blockerId: UUID, blockedId: UUID
        enum CodingKeys: String, CodingKey { case blockerId = "blocker_id", blockedId = "blocked_id" }
    }
    struct ReportRow: Encodable {
        let reporterId: UUID, reportedId: UUID, reason: String, details: String?
        enum CodingKeys: String, CodingKey { case reporterId = "reporter_id", reportedId = "reported_id", reason, details }
    }

    static func block(_ other: UUID, me: UUID) async throws {
        do { try await supabase.from("blocks").insert(BlockRow(blockerId: me, blockedId: other)).execute() }
        catch where "\(error)".contains("duplicate") {}
    }

    static func report(_ other: UUID, me: UUID, reason: String, details: String?) async throws {
        do { try await supabase.from("reports").insert(ReportRow(reporterId: me, reportedId: other, reason: reason, details: details)).execute() }
        catch where "\(error)".contains("duplicate") {}
    }

    // MARK: events

    static func upcomingEvents() async throws -> [EventItem] {
        let list: [EventItem] = try await rpc("upcoming_events", cacheAs: CacheKey.events)
        return list.sorted { $0.start < $1.start }
    }
    static func event(_ id: UUID) async throws -> EventItem? { try await rpc("get_event", ["p_id": .uuid(id)], as: EventItem?.self) }
    static func joinEvent(_ id: UUID) async throws -> OkResult { try await rpc("join_event", ["p_event": .uuid(id)]) }
    static func leaveEvent(_ id: UUID) async throws { try await call("leave_event", ["p_event": .uuid(id)]) }
    static func checkIn(_ id: UUID, code: String) async throws -> OkResult {
        try await rpc("check_in", ["p_event": .uuid(id), "p_code": .string(code)])
    }
    static func hostCode(_ id: UUID) async throws -> HostCode { try await rpc("host_checkin_code", ["p_event": .uuid(id)]) }

    struct NewEvent: Encodable {
        let hostId: UUID, city: String, sportCode: String, title: String, description: String?
        let meetingPoint: String, startsAt: String, durationMin: Int, capacity: Int, priceKzt: Int
        enum CodingKeys: String, CodingKey {
            case city, title, description, capacity
            case hostId = "host_id", sportCode = "sport_code", meetingPoint = "meeting_point"
            case startsAt = "starts_at", durationMin = "duration_min", priceKzt = "price_kzt"
        }
    }
    struct IdRow: Decodable { let id: UUID }

    static func createEvent(_ e: NewEvent) async throws -> UUID {
        let r = try await supabase.from("events").insert(e).select("id").single().execute()
        return try decoder.decode(IdRow.self, from: r.data).id
    }

    // MARK: Pro

    static func createGift() async throws -> GiftResult { try await rpc("create_pro_gift") }
    /// Pro members in your city, rounded to tens; nil below 100 (then the paywall says nothing).
    static func proMembersInCity() async throws -> Int? { try await rpc("pro_members_in_city", as: Int?.self) }
    static func redeemGift(_ code: String) async throws -> GiftResult {
        try await rpc("redeem_pro_gift", ["p_code": .string(code.trimmingCharacters(in: .whitespaces).uppercased())])
    }

    // MARK: push

    static func registerPush(token: String) async throws {
        try await call("register_push_token", ["p_token": .string(token), "p_platform": .string("ios")])
    }
}

// MARK: prompts, picks, travel
extension Backend {
    static let promptKeys = ["perfect_sunday", "slow_down_for", "after_finish", "proudest_finish", "teach_me",
                             "green_flag", "season_love", "first_date_idea", "training_secret"]

    struct PromptRow: Codable {
        let profileId: UUID?, position: Int?, promptKey: String, answer: String
        enum CodingKeys: String, CodingKey { case profileId = "profile_id", position, promptKey = "prompt_key", answer }
    }

    static func myPrompts(userId: UUID) async throws -> [PromptAnswer] {
        let r = try await supabase.from("profile_prompts").select("prompt_key, answer")
            .eq("profile_id", value: userId.uuidString).order("position").execute()
        return try JSONDecoder().decode([PromptRow].self, from: r.data).map { PromptAnswer(key: $0.promptKey, answer: $0.answer) }
    }

    static func savePrompts(userId: UUID, _ prompts: [PromptAnswer]) async throws {
        try await supabase.from("profile_prompts").delete().eq("profile_id", value: userId.uuidString).execute()
        let rows = prompts.filter { $0.answer.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }.prefix(3)
            .enumerated().map { PromptRow(profileId: userId, position: $0.offset, promptKey: $0.element.key,
                                          answer: $0.element.answer.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !rows.isEmpty { try await supabase.from("profile_prompts").insert(Array(rows)).execute() }
    }

    static func dailyPicks() async throws -> [ProfileCard] { try await rpc("daily_picks", cacheAs: CacheKey.picks(Backend.today)) }

    /// Almaty's date, for things that change daily (picks).
    static var today: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Almaty") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    struct TravelResult: Decodable { let ok: Bool; let error: String?; let until: String? }
    static func setTravel(city: String, days: Int) async throws -> TravelResult {
        try await rpc("set_travel", ["p_city": .string(city), "p_days": .integer(days)])
    }
    static func clearTravel() async throws { try await call("clear_travel") }

    struct BoostResult: Decodable { let ok: Bool; let error: String?; let boostedUntil: String? }
    static func boost() async throws -> BoostResult { try await rpc("activate_boost") }
}
