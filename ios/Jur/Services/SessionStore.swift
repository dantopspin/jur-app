// Who is signed in, their profile and limits. Drives the root gate:
// signed out → sign-in; signed in without a profile → onboarding; a failed
// profile load → Retry (never onboarding, so a weak connection can't send an
// existing member back to "What's your name?").
import Foundation
import Observation
import RevenueCat
import Supabase

@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable { case loading, signedOut, profileFailed, needsProfile, banned, ready }

    private(set) var session: Session?
    private(set) var profile: MyProfile?
    private(set) var limits: Limits?
    private(set) var phase: Phase = .loading
    private var loadedFor: UUID?
    private var activityRecordedFor: UUID?

    var userId: UUID? { session?.user.id }

    init() {
        Task { await listen() }
    }

    private func listen() async {
        for await (event, session) in supabase.auth.authStateChanges {
            self.session = session
            guard let session else {
                profile = nil; limits = nil; loadedFor = nil
                phase = .signedOut
                continue
            }
            // Token refreshes don't need a reload; a new user or the first session does.
            if loadedFor != session.user.id || event == .signedIn || event == .initialSession {
                await load(userId: session.user.id)
            }
        }
    }

    private func load(userId: UUID) async {
        // Launch: the profile saved last time opens the app at once; the server answer follows.
        if profile == nil, let saved = DataCache.get(CacheKey.me, as: [MyProfile].self)?.first,
           saved.id == userId, !saved.banned {
            profile = saved
            limits = DataCache.get(CacheKey.limits, as: Limits.self)
            phase = .ready
        }
        do {
            let p = try await Backend.myProfile(userId: userId)
            profile = p
            loadedFor = userId
            if let p {
                if p.banned { phase = .banned; return }
                if UserDefaults.standard.string(forKey: L10n.storageKey) == nil,
                   let code = p.locale, let lang = AppLanguage(rawValue: code) {
                    L10n.current = lang
                }
                phase = .ready
                await refreshLimits()
                Purchases.connect(userId: userId)
                if activityRecordedFor != userId {
                    activityRecordedFor = userId
                    try? await Backend.recordActivity()
                }
            } else {
                phase = .needsProfile
            }
        } catch {
            // Already showing the saved profile: a weak connection isn't worth an error screen.
            if phase != .ready { phase = .profileFailed }
        }
    }

    func retry() async {
        guard let id = userId else { phase = .signedOut; return }
        phase = .loading
        await load(userId: id)
    }

    func refreshProfile() async {
        guard let id = userId else { return }
        await load(userId: id)
    }

    func refreshLimits() async {
        limits = try? await Backend.limits()
    }

    func signOut() async {
        // First, while still signed in: this phone stops getting the account's notifications.
        await Backend.unregisterPush()
        LiveDepartures.endAll()
        DataCache.clearAll()
        Drafts.clearAll()
        ImageLoader.shared.clearMemory()
        Purchases.disconnect()
        try? await supabase.auth.signOut()
    }
}

extension Purchases {
    /// RevenueCat is used only to sell and restore; Pro status shown in the app comes from the server.
    static func connect(userId: UUID) {
        guard !Config.revenueCatKey.isEmpty, !Config.revenueCatKey.hasPrefix("appl_xxxx") else { return }
        let id = userId.uuidString.lowercased()
        if isConfigured {
            Task { _ = try? await shared.logIn(id) }
        } else {
            configure(withAPIKey: Config.revenueCatKey, appUserID: id)
        }
    }

    static func disconnect() {
        guard isConfigured else { return }
        Task { _ = try? await shared.logOut() }
    }
}
