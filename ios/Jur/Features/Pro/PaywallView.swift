// Pro: the paywall (RevenueCat sells; the server decides who is Pro), then the
// passport cover with a week of Pro to give a friend.
import RevenueCat
import SwiftUI

struct PaywallView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var packages: [Package] = []
    @State private var selected: Package?
    @State private var loading = true
    @State private var buying = false
    @State private var welcome = false

    var body: some View {
        ZStack {
            if welcome {
                ProWelcomeView { dismiss() }
                    .transition(.qStep(forward: true))
            } else {
                paywall
                    .transition(.qStep(forward: true))
            }
        }
        .task { await loadOfferings() }
    }

    private var paywall: some View {
        ZStack(alignment: .topTrailing) {
            Color.q.blue.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Sp.xl) {
                    MembershipCover(memberNo: formatMemberNo(session.profile?.memberNo ?? 0), tilted: true)
                        .scaleEffect(0.7)
                        .frame(height: 250)
                        .padding(.top, Sp.xl)
                    VStack(spacing: Sp.sm) {
                        Text(t("paywall.title")).qText(.title1).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                        Text(t("paywall.sub")).qText(.body).foregroundStyle(Color.q.blueMist)
                    }
                    .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: Sp.md) {
                        ForEach(["paywall.f1", "paywall.f2", "paywall.f3", "paywall.f4"], id: \.self) { k in
                            Label(t(k), systemImage: "checkmark.circle.fill")
                                .qText(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    plans
                    VStack(spacing: Sp.sm) {
                        Button { Task { await buy() } } label: { BusyLabel(title: t("paywall.buy"), busy: buying, spinner: Color.q.onGold) }
                            .buttonStyle(.q(.accent))
                            .disabled(selected == nil || buying)
                        Button(t("paywall.restore")) { Task { await restore() } }
                            .buttonStyle(.qOnBlue)
                            .disabled(buying)
                        Text(t("paywall.legal")).qText(.caption).foregroundStyle(Color.q.blueMist).multilineTextAlignment(.center)
                        LegalFooter(leadKey: "legal.lead", onBlue: true)
                    }
                }
                .padding(Layout.margin)
            }
            CloseButton(action: { dismiss() }, onBlue: true).padding(Layout.margin)
        }
    }

    @ViewBuilder private var plans: some View {
        if loading {
            ProgressView().tint(.white)
        } else if packages.isEmpty {
            Text(t("paywall.unavailable")).qText(.callout).foregroundStyle(Color.q.blueMist).multilineTextAlignment(.center)
        } else {
            VStack(spacing: Sp.sm) {
                ForEach(packages, id: \.identifier) { p in
                    let on = selected?.identifier == p.identifier
                    Button { selected = p; Haptics.tick() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Sp.xxs) {
                                Text(planName(p)).qText(.headline)
                                if p.packageType == .sixMonth { Text(t("paywall.best")).qText(.label).foregroundStyle(Color.q.gold) }
                            }
                            Spacer()
                            Text(p.storeProduct.localizedPriceString).qText(.number).fixedSize()
                        }
                        .foregroundStyle(.white)
                        .padding(Sp.lg)
                        .background(Color.white.opacity(on ? 0.2 : 0.08), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(on ? Color.q.gold : .clear, lineWidth: 2))
                        .animation(Motion.snappy, value: on)
                    }
                    .buttonStyle(.qPressCard)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func planName(_ p: Package) -> String {
        switch p.packageType {
        case .weekly: t("paywall.weekly")
        case .monthly: t("paywall.monthly")
        case .sixMonth: t("paywall.sixMonths")
        default: p.storeProduct.localizedTitle
        }
    }

    private func loadOfferings() async {
        defer { loading = false }
        guard Purchases.isConfigured, let offerings = try? await Purchases.shared.offerings() else { return }
        let order: [PackageType] = [.weekly, .monthly, .sixMonth]
        let offering = offerings.offering(identifier: "default") ?? offerings.current
        packages = (offering?.availablePackages ?? []).sorted {
            (order.firstIndex(of: $0.packageType) ?? 9) < (order.firstIndex(of: $1.packageType) ?? 9)
        }
        selected = packages.first { $0.packageType == .monthly } ?? packages.first
    }

    private func buy() async {
        guard let selected else { return }
        buying = true
        defer { buying = false }
        do {
            let result = try await Purchases.shared.purchase(package: selected)
            if result.userCancelled { return }
            await waitForPro()
            Haptics.success()
            withMotion(Motion.smooth) { welcome = true }
        } catch {
            toasts.show(t("common.error"), error: true)
        }
    }

    private func restore() async {
        buying = true
        defer { buying = false }
        do {
            _ = try await Purchases.shared.restorePurchases()
            await waitForPro()
            toasts.show(t("paywall.restored"))
            if session.limits?.pro == true { withMotion(Motion.smooth) { welcome = true } }
        } catch {
            toasts.show(t("common.error"), error: true)
        }
    }

    /// The store tells our server through a webhook; give it a few seconds.
    private func waitForPro() async {
        for _ in 0..<6 {
            await session.refreshLimits()
            if session.limits?.pro == true { return }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }
}

/// After buying: the passport cover, then a week of Pro to give a friend.
struct ProWelcomeView: View {
    let onClose: () -> Void
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var code: String?
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.q.blue.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Sp.xl) {
                    MembershipCover(memberNo: formatMemberNo(session.profile?.memberNo ?? 0), animatesIn: true)
                        .padding(.top, Sp.xxl)
                    VStack(spacing: Sp.sm) {
                        Text(t("cover.welcome")).qText(.title2).foregroundStyle(.white)
                        Text("\(t("paywall.f1")) · \(t("paywall.f2")) · \(t("paywall.f3"))")
                            .qText(.callout).foregroundStyle(Color.q.blueMist)
                    }
                    .multilineTextAlignment(.center)
                    GiftCard(code: code, busy: busy, onSend: { Task { await gift() } }, onCopy: { toasts.show(t("states.copied")) })
                }
                .padding(Layout.margin)
            }
            CloseButton(action: onClose, onBlue: true).padding(Layout.margin)
        }
    }

    private func gift() async {
        if let code {
            share(code)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let r = try await Backend.createGift()
            if let c = r.code { code = c; share(c) }
            else { toasts.show(t(r.error == "once_a_month" ? "cover.giftRule" : "common.error"), error: true) }
        } catch { toasts.show(t("common.error"), error: true) }
    }

    private func share(_ code: String) {
        let text = t("cover.giftShare", ["code": code])
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?
            .rootViewController?.topmost.present(vc, animated: true)
    }
}

extension UIViewController {
    var topmost: UIViewController { presentedViewController?.topmost ?? self }
}

/// Redeem a friend's gift code (Me → Pro).
struct RedeemGiftSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            Text(t("cover.redeemTitle")).qText(.title3).accessibilityAddTraits(.isHeader)
            TextField("K7MD-P2QA", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.q(.title3))
                .qField(isError: error != nil)
            if let error { Text(error).qText(.callout).foregroundStyle(Color.q.danger) }
            Button { Task { await redeem() } } label: { BusyLabel(title: t("cover.redeem"), busy: busy) }
                .buttonStyle(.qPrimary)
                .disabled(code.count < 4 || busy)
        }
        .padding(Layout.margin)
        .padding(.top, Sp.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .qSheet(detents: [.height(300)])
    }

    private func redeem() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let r = try await Backend.redeemGift(code)
            if r.ok {
                await session.refreshLimits()
                toasts.show(t("cover.redeemed"))
                dismiss()
            } else {
                error = t("cover.err_\(r.error ?? "not_found")")
            }
        } catch { self.error = t("common.error") }
    }
}
