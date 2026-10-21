// Email → 6-digit code (or a password, for the App Review demo account only).
import Supabase
import SwiftUI

struct EmailSignInView: View {
    var passwordMode = false
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var resendAt: Date?
    @FocusState private var focused: Bool

    private var validEmail: Bool {
        email.trimmingCharacters(in: .whitespaces).range(of: #"^\S+@\S+\.\S+$"#, options: .regularExpression) != nil
    }
    private var normalized: String { email.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Sp.sm) {
                    Text(codeSent ? t("auth.code") : t("welcome.emailTitle")).qText(.title1).foregroundStyle(Color.q.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(codeSent ? t("auth.codeSent", ["email": normalized]) : t("welcome.emailHint"))
                        .qText(.body).foregroundStyle(Color.q.inkSoft)
                }

                VStack(alignment: .leading, spacing: Sp.lg) {
                    if !codeSent {
                        TextField(t("auth.emailPlaceholder"), text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focused)
                            .onSubmit { if !passwordMode { Task { await sendCode() } } }
                            .qField(isError: error != nil)
                    }
                    if passwordMode {
                        SecureField(t("auth.password"), text: $password)
                            .textContentType(.password)
                            .qField(isError: error != nil)
                    }
                    if codeSent {
                        CodeField(length: 6, code: $code, isError: error != nil, accessibilityLabel: t("auth.code")) { _ in
                            Task { await verify() }
                        }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .qText(.callout).foregroundStyle(Color.q.danger)
                    }

                    if passwordMode {
                        Button { Task { await signInWithPassword() } } label: { BusyLabel(title: t("auth.verify"), busy: busy) }
                            .buttonStyle(.qPrimary).disabled(!validEmail || password.isEmpty || busy)
                    } else if codeSent {
                        Button { Task { await verify() } } label: { BusyLabel(title: t("auth.verify"), busy: busy) }
                            .buttonStyle(.qPrimary).disabled(code.count < 6 || busy)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = Int((resendAt ?? .distantPast).timeIntervalSince(context.date).rounded(.up))
                            Button(left > 0 ? t("auth.resendIn", ["s": left]) : t("auth.sendCode")) {
                                Task { await sendCode() }
                            }
                            .font(.q(.footnote)).fontWeight(.semibold)
                            .foregroundStyle(left > 0 ? Color.q.muted : Color.q.blueText)
                            .frame(minHeight: Layout.rowMin)
                            .frame(maxWidth: .infinity)
                            .disabled(left > 0 || busy)
                        }
                    } else {
                        Button { Task { await sendCode() } } label: { BusyLabel(title: t("auth.sendCode"), busy: busy) }
                            .buttonStyle(.qPrimary).disabled(!validEmail || busy)
                    }
                }
                .padding(.top, Sp.xl)
            }
            .padding(.horizontal, Layout.margin)
            .padding(.top, Sp.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            LegalFooter(leadKey: "auth.legal")
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Layout.margin)
                .padding(.vertical, Sp.sm)
                .background(Color.q.bg)
        }
        .background(Color.q.bg)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onChange(of: error) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    private func sendCode() async {
        guard validEmail else { error = t("auth.badEmail"); return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await supabase.auth.signInWithOTP(email: normalized, shouldCreateUser: true)
            codeSent = true
            code = ""
            resendAt = Date().addingTimeInterval(60)
            focused = true
        } catch {
            self.error = Self.message(for: error)
        }
    }

    private func verify() async {
        guard code.count == 6, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await supabase.auth.verifyOTP(email: normalized, token: code, type: .email)
        } catch {
            self.error = t("auth.badCode")
            Haptics.failure()
        }
    }

    private func signInWithPassword() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await supabase.auth.signIn(email: normalized, password: password)
        } catch {
            self.error = Self.message(for: error)
        }
    }

    /// Server and network errors in the person's language, never raw English.
    static func message(for error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("rate") || text.contains("security purposes") || text.contains("429") { return t("auth.tooMany") }
        return t("auth.failed")
    }
}

extension View {
    /// A text field on the chalk ground: white fill, 12 pt corners, 50 pt tall; a red
    /// outline while it has an error.
    func qField(isError: Bool = false) -> some View {
        self.font(.q(.body))
            .padding(.horizontal, Sp.lg)
            .frame(minHeight: Layout.buttonHeight)
            .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isError ? Color.q.danger : .clear, lineWidth: 1.5))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}
