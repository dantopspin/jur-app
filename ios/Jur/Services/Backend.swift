// The Supabase client and a thin, typed layer over the database functions (RPCs).
// All rules (limits, matching, safety, purchases) live in SQL and are tested there;
// the app only calls them.
import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseAnonKey,
    // Emit the stored session at launch right away (the SDK's upcoming default); requests
    // refresh an expired token by themselves.
    options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true)))

enum Backend {
    /// snake_case JSON from Postgres → camelCase Swift properties.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Calls a database function and decodes its JSON result.
    static func rpc<T: Decodable>(_ fn: String, _ params: [String: AnyJSON] = [:], as type: T.Type = T.self) async throws -> T {
        let response = try await supabase.rpc(fn, params: params).execute()
        return try decoder.decode(T.self, from: response.data)
    }

    /// Calls a database function that returns nothing useful.
    static func call(_ fn: String, _ params: [String: AnyJSON] = [:]) async throws {
        _ = try await supabase.rpc(fn, params: params).execute()
    }

    // MARK: profile and limits

    static func myProfile(userId: UUID) async throws -> MyProfile? {
        let response = try await supabase.from("profiles").select().eq("id", value: userId.uuidString).limit(1).execute()
        let rows = try decoder.decode([MyProfile].self, from: response.data)
        if !rows.isEmpty { DataCache.put(response.data, CacheKey.me) }
        return rows.first
    }

    static func limits() async throws -> Limits { try await rpc("my_limits", cacheAs: CacheKey.limits) }

    static func recordActivity() async throws { try await call("record_activity") }

    static func updateLocale(_ lang: AppLanguage, userId: UUID) async throws {
        _ = try await supabase.from("profiles").update(["locale": lang.rawValue]).eq("id", value: userId.uuidString).execute()
    }

    /// Deletes the account and its stored files (delete-account Edge Function).
    static func deleteAccount() async throws {
        try await supabase.functions.invoke("delete-account")
    }
}

/// `{ ok, error }` results from the database functions.
struct OkResult: Decodable {
    let ok: Bool
    let error: String?
}
