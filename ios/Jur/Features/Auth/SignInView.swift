// Welcome → Sign in with Apple (or an email code, when Config.emailSignInEnabled).
// The password route exists only for the App Review demo account: long-press the mark.
import AuthenticationServices
import CryptoKit
import Supabase
import SwiftUI

struct SignInView: View {
    @State private var showEmail = false
    @State private var passwordMode = false
    @State private var error: String?
    @State private var nonce = ""
    @State private var errorDetail: String?
    /// The welcome lands in order: the mark draws in, then the words, then the buttons.
    @State private var wordsShown = false
    @State private var buttonsShown = false
    #if DEBUG
    /// Debug builds only: triple-tap the wordmark to walk through onboarding without an account.
    @State private var previewOnboarding = false
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(L10n.storageKey) private var language: String = AppLanguage.device.rawValue

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.q.blue.ignoresSafeArea()
                // 36% of the screen, 200–330 pt, so the peaks never reach the hero on small phones.
                Horizon()
                    .containerRelativeFrame(.vertical) { height, _ in min(max(height * 0.36, 200), 330) }
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    languageSwitch
                    Spacer()
                    hero
                    Spacer()
                    buttons
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, Sp.lg)
            }
            .onAppear {
                if reduceMotion { wordsShown = true; buttonsShown = true; return }
                withAnimation(Motion.smooth.delay(0.35)) { wordsShown = true }
                withAnimation(Motion.smooth.delay(0.45)) { buttonsShown = true }
            }
            // Go online once, right away: on iPhones that ask "Allow JÜR to use wireless data?",
            // the system prompt then appears now, not while a sign-in request is waiting on it.
            .task { await Self.warmUpNetwork() }
            .onChange(of: error) { _, new in
                if let new { AccessibilityNotification.Announcement(new).post() }
            }
            .navigationDestination(isPresented: $showEmail) {
                EmailSignInView(passwordMode: passwordMode)
            }
        }
    }

    private var languageSwitch: some View {
        HStack(spacing: Sp.xs) {
            Spacer()
            ForEach(AppLanguage.allCases) { lang in
                let on = language == lang.rawValue
                Button {
                    Haptics.tick()
                    L10n.current = lang
                    language = lang.rawValue
                } label: {
                    Text(verbatim: lang == .kk ? "ҚАЗ" : lang == .ru ? "РУС" : "ENG")
                        .qText(.label)
                        .foregroundStyle(on ? .white : Color.q.blueMist)
                        .padding(.horizontal, Sp.md)
                        .frame(minHeight: 32)
                        .background(on ? Color.q.onBlueFill : .clear, in: Capsule())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(lang.nativeName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            MarkView(size: 112, color: Color.q.gold, animate: true)
                .onLongPressGesture(minimumDuration: 1.2) {
                    // App Review demo account only.
                    passwordMode = true
                    showEmail = true
                }
            Wordmark(size: 46, ink: .white, dots: Color.q.gold)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Sp.lg)
                #if DEBUG
                .onTapGesture(count: 3) { previewOnboarding = true }
                .fullScreenCover(isPresented: $previewOnboarding) {
                    OnboardingView(preview: true) { previewOnboarding = false }
                }
                #endif
            VStack(spacing: 0) {
                Text(t("auth.tagline"))
                    .qText(.title3)
                    .foregroundStyle(Color.q.gold)
                    .multilineTextAlignment(.center)
                    .padding(.top, Sp.md)
                Text(t("auth.sub"))
                    .qText(.body)
                    .foregroundStyle(Color.q.blueMist)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, Sp.sm)
            }
            .opacity(wordsShown ? 1 : 0)
            .offset(y: wordsShown || reduceMotion ? 0 : 8)
        }
    }

    private var buttons: some View {
        VStack(spacing: Sp.md) {
            if !Config.isConfigured {
                Text(t("auth.notConfiguredIOS")).qText(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
            }
            SignInWithAppleButton(.continue) { request in
                nonce = Self.randomNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                Task { await finishApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: Layout.buttonHeight)
            .clipShape(Capsule())

            if Config.emailSignInEnabled {
                Button {
                    error = nil
                    passwordMode = false
                    showEmail = true
                } label: {
                    Label(t("welcome.email"), systemImage: "envelope")
                }
                .buttonStyle(.qOnBlue)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .qText(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                // What actually went wrong, small, so a tester's screenshot tells us the cause.
                if let errorDetail {
                    Text(verbatim: errorDetail)
                        .qText(.caption)
                        .foregroundStyle(Color.q.blueMist)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            LegalFooter(leadKey: "auth.legalLead", trailingKey: "legal.adult", onBlue: true)
                .padding(.top, Sp.xs)
        }
        .opacity(buttonsShown ? 1 : 0)
        .offset(y: buttonsShown || reduceMotion ? 0 : 12)
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                error = t("welcome.socialFailed"); return
            }
            // Apple shares the name only the first time; keep it for onboarding.
            if let given = cred.fullName?.givenName, !given.isEmpty {
                UserDefaults.standard.set(given, forKey: "jur.prefillName")
            }
            error = nil; errorDetail = nil
            let credentials = OpenIDConnectCredentials(provider: .apple, idToken: token, nonce: nonce)
            do {
                // A dropped connection, or network access not allowed yet (the system prompt
                // still on screen): retry with growing pauses, about 9 seconds in all.
                var attempt = 0
                while true {
                    do {
                        try await supabase.auth.signInWithIdToken(credentials: credentials)
                        break
                    } catch let e as URLError where Self.isTransient(e) && attempt < 3 {
                        attempt += 1
                        try await Task.sleep(for: .seconds(1.5 * Double(attempt)))
                    }
                }
                // the session listener routes onward
            } catch {
                show(error)
            }
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code != .canceled { show(err) }
        }
    }

    /// A tiny request to the server, ignored either way.
    private static func warmUpNetwork() async {
        var request = URLRequest(url: Config.supabaseURL.appending(path: "auth/v1/health"), timeoutInterval: 10)
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func isTransient(_ e: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed,
         .internationalRoamingOff, .dataNotAllowed, .cannotFindHost].contains(e.code)
    }

    private func show(_ err: Error) {
        if let e = err as? URLError {
            error = t("welcome.socialOffline")
            errorDetail = "net \(e.code.rawValue)"
        } else if let e = err as? ASAuthorizationError {
            error = t("welcome.socialFailed")
            errorDetail = "apple \(e.code.rawValue)"
        } else {
            error = t("welcome.socialFailed")
            errorDetail = String(String(describing: err).prefix(160))
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
