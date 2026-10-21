// The gate: loading → sign-in → onboarding → the app. A failed profile load
// shows Retry instead of onboarding.
import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                LoadingView()
            case .signedOut:
                SignInView()
            case .profileFailed:
                ErrorStateView(retry: { await session.retry() },
                               secondary: (t("settings.signOut"), { await session.signOut() }))
            case .needsProfile:
                OnboardingPlaceholder()
            case .banned:
                ContentUnavailableView {
                    Label(t("common.error"), systemImage: "hand.raised").font(.q(.title3))
                } description: {
                    Text(t("common.suspended"))
                } actions: {
                    Button(t("settings.signOut")) { Task { await session.signOut() } }
                        .buttonStyle(.q(.ghost, compact: true))
                        .fixedSize()
                }
                .background(Color.q.bg)
            case .ready:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }
}

/// Milestone 1 stand-in: onboarding is rebuilt in milestone 2.
private struct OnboardingPlaceholder: View {
    @Environment(SessionStore.self) private var session
    var body: some View {
        ContentUnavailableView {
            Label(t("ios.comingSoon"), systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text(t("ios.onboardingSoon"))
        } actions: {
            Button(t("settings.signOut")) { Task { await session.signOut() } }
                .buttonStyle(.q(.secondary, compact: true)).fixedSize()
        }
        .background(Color.q.bg)
    }
}
