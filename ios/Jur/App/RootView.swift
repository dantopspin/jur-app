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
                OnboardingView()
                    .transition(Motion.reduceMotion ? .opacity
                                : .asymmetric(insertion: .offset(y: 32).combined(with: .opacity),
                                              removal: .scale(scale: 0.96).combined(with: .opacity)))
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
        .animation(Motion.adaptive(Motion.smooth), value: session.phase)
    }
}

