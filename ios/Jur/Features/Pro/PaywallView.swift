// Pro: the paywall (RevenueCat sells; the server decides who is Pro), then the
// passport cover with a week of Pro to give a friend.
import RevenueCat
import SwiftUI

/// Why the paywall opened: its top half speaks to that moment.
enum PaywallContext: Equatable {
    case generic
    /// From Likes: how many people are waiting.
    case likes(count: Int)
    /// The day's likes ran out (they come back at midnight, Almaty time).
    case outOfLikes
    case boost
    case undo
    /// "Active recently" in the filters.
    case filters

    /// The benefit this moment is about goes first in the list.
    var leadBenefit: String {
        switch self {
        case .likes: "seeLikes"
        case .outOfLikes, .undo: "unlimited"
        case .boost: "boost"
        default: "seeLikes"
        }
    }
}

struct PaywallView: View {
    var context: PaywallContext = .generic
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var packages: [Package] = []
    @State private var selected: Package?
    @State private var loading = true
    @State private var buying = false
    @State private var welcome = false
    /// Intro price (first week) the store says this person can still get, per product id.
    @State private var introEligible: Set<String> = []
    /// The weekly plan sits behind "Other options".
    @State private var showWeekly = false
    /// "В Алматы с Pro уже 1 240 человек" — only a real number, only from 100 up.
    @State private var proInCity: Int?
    @State private var appeared = false
    @State private var shine = false

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
        .legalLinks()
        .task { await loadOfferings() }
        .task { proInCity = try? await Backend.proMembersInCity() }
    }

    // MARK: layout

    /// Three layouts by the height there is (iPhone SE, regular, Pro Max), so the whole
    /// paywall fits without scrolling; very large text sizes scroll instead of clipping.
    private enum Fit {
        case compact, regular, large
        init(_ h: CGFloat) { self = h < 600 ? .compact : h > 730 ? .large : .regular }
        var side: CGFloat { self == .compact ? 20 : self == .regular ? 24 : 28 }
        var row: CGFloat { self == .compact ? 52 : self == .regular ? 60 : 64 }
    }

    private var paywall: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let fit = Fit(geo.size.height)
                ScrollView {
                    VStack(spacing: 0) {
                        header(fit)
                            .padding(.top, fit == .compact ? Sp.xl : Sp.xxl)
                        Spacer(minLength: Sp.md)
                        titles(fit)
                        Spacer(minLength: Sp.md)
                        benefits(fit)
                        Spacer(minLength: Sp.lg)
                        plans(fit)
                        buyButton
                            .padding(.top, fit == .compact ? Sp.md : Sp.lg)
                        afterButton
                            .padding(.top, Sp.sm)
                            .padding(.bottom, Sp.md)
                    }
                    .padding(.horizontal, fit.side)
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            footer
        }
        .background {
            ZStack(alignment: .top) {
                Color.q.blue
                // The ridge across the top: blue sky below the peaks, as on the sign-in screen.
                Horizon(far: Color.q.blueDeep, near: Color.q.blueNight)
                    .frame(height: 96)
                    .ignoresSafeArea(edges: .top)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            CloseButton(action: { dismiss() }, onBlue: true).padding(Layout.margin)
        }
        .onAppear {
            withAnimation(Motion.adaptive(Motion.hero)) { appeared = true }
            guard !Motion.reduceMotion else { return }
            withAnimation(Motion.sheen.delay(0.9)) { shine = true }
        }
    }

    // MARK: header (by context)

    @ViewBuilder private func header(_ fit: Fit) -> some View {
        Group {
            switch context {
            case .likes(let count):
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(LinearGradient(colors: [[Color.q.feltGround, Color.q.blueMist, Color.q.goodTint][i], Color.q.blueDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                            .blur(radius: 3)
                            .overlay(Circle().stroke(Color.q.blue, lineWidth: 3))
                            .offset(x: CGFloat(i - 1) * 40)
                    }
                    Text(verbatim: count > 99 ? "99+" : "\(count)")
                        .font(.qFont("Unbounded-ExtraBold", size: 22, relativeTo: .title, weight: .heavy, latinOnly: true))
                        .monospacedDigit()
                        .foregroundStyle(Color.q.onGold)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Color.q.gold, in: Capsule())
                        .offset(x: 58, y: 24)
                }
                .frame(height: 80)
            case .outOfLikes:
                VStack(spacing: Sp.xxs) {
                    Text(timerInterval: Date.now...Self.nextMidnight, countsDown: true)
                        .font(.qFont("Unbounded-ExtraBold", size: fit == .compact ? 36 : 44, relativeTo: .largeTitle,
                                     weight: .heavy, latinOnly: true))
                        .monospacedDigit()
                        .foregroundStyle(Color.q.gold)
                    Text(t("pw.likesBackIn")).qText(.label).foregroundStyle(Color.q.blueMist)
                }
            case .boost, .undo, .filters:
                Image(systemName: context == .boost ? "bolt.fill" : context == .undo ? "arrow.uturn.backward" : "line.3.horizontal.decrease")
                    .font(.system(size: IconSize.action, weight: .bold))
                    .foregroundStyle(Color.q.onGold)
                    .frame(width: fit == .compact ? 64 : 76, height: fit == .compact ? 64 : 76)
                    .background(Color.q.gold, in: Circle())
                    .qElevated()
            case .generic:
                MembershipCover(memberNo: formatMemberNo(session.profile?.memberNo ?? 0), tilted: true)
                    .scaleEffect(fit == .compact ? 0.42 : fit == .regular ? 0.52 : 0.6)
                    .frame(height: fit == .compact ? 96 : fit == .regular ? 120 : 140)
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared || Motion.reduceMotion ? 1 : 0.9)
        .accessibilityHidden(true)
    }

    private var title: String {
        switch context {
        case .likes(let count): tn("pw.likesTitle", count)
        case .outOfLikes: t("pw.outTitle")
        case .boost: t("pw.boostTitle", ["city": Cities.label(session.profile?.city ?? "")])
        case .undo: t("pw.undoTitle")
        case .filters: t("pw.filtersTitle")
        case .generic: t("pw.title")
        }
    }

    private var subtitle: String {
        switch context {
        case .likes: t("pw.likesSub")
        case .outOfLikes: t("pw.outSub")
        case .boost: t("pw.boostSub")
        case .undo: t("pw.undoSub")
        case .filters: t("pw.filtersSub")
        case .generic: t("pw.sub")
        }
    }

    private func titles(_ fit: Fit) -> some View {
        VStack(spacing: Sp.sm) {
            Text(title)
                .qText(fit == .compact ? .title2 : .title1)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if fit != .compact {
                Text(subtitle).qText(.callout).foregroundStyle(Color.q.blueMist)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: benefits

    /// One per line, the check marks on the same vertical line as the plan rows' radio buttons.
    private func benefits(_ fit: Fit) -> some View {
        var keys = ["seeLikes", "unlimited", "supers", "boost"]
        keys.removeAll { $0 == context.leadBenefit }
        keys.insert(context.leadBenefit, at: 0)
        return VStack(alignment: .leading, spacing: fit == .compact ? Sp.sm : Sp.md) {
            ForEach(Array(keys.enumerated()), id: \.element) { i, key in
                benefit(t("pw.b.\(key)"), symbol: "checkmark", index: i)
            }
            if fit != .compact {
                benefit(t("pw.b.gift"), symbol: "gift.fill", index: keys.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Sp.lg + 2)
    }

    private func benefit(_ text: String, symbol: String, index: Int) -> some View {
        HStack(spacing: Sp.md) {
            Image(systemName: symbol)
                .font(.system(size: IconSize.inline - 2, weight: .heavy))
                .foregroundStyle(Color.q.onGold)
                .frame(width: 22, height: 22)
                .background(Color.q.gold, in: Circle())
            Text(text).qText(.headline).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || Motion.reduceMotion ? 0 : 8)
        .animation(Motion.adaptive(Motion.smooth).delay(0.15 + 0.05 * Double(index)), value: appeared)
        .accessibilityElement(children: .combine)
    }

    // MARK: plans

    private var monthly: Package? { packages.first { $0.packageType == .monthly } }
    private var sixMonths: Package? { packages.first { $0.packageType == .sixMonth } }
    private var weekly: Package? { packages.first { $0.packageType == .weekly } }

    @ViewBuilder private func plans(_ fit: Fit) -> some View {
        if loading {
            VStack(spacing: Sp.sm) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous)
                        .fill(Color.q.onBlueFaint).frame(height: fit.row)
                }
            }
            .qShimmer()
        } else if packages.isEmpty {
            Text(t("paywall.unavailable")).qText(.callout).foregroundStyle(Color.q.blueMist).multilineTextAlignment(.center)
        } else {
            VStack(spacing: fit == .compact ? Sp.sm : Sp.sm + 2) {
                // Two plans up front (a month, and six months as the better deal); the week
                // waits behind "Other options".
                ForEach(Array(([monthly, sixMonths] + (showWeekly ? [weekly] : [])).compactMap { $0 }.enumerated()),
                        id: \.element.identifier) { i, p in
                    planRow(p, fit: fit)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || Motion.reduceMotion ? 0 : 10)
                        .animation(Motion.adaptive(Motion.smooth).delay(0.3 + 0.06 * Double(i)), value: appeared)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if weekly != nil && !showWeekly {
                    Button(t("pw.otherOptions")) { withMotion(Motion.smooth) { showWeekly = true } }
                        .font(.q(.footnote)).fontWeight(.bold)
                        .foregroundStyle(Color.q.blueMist)
                        .frame(minHeight: Layout.rowMin - 12)
                }
            }
        }
    }

    private func planRow(_ p: Package, fit: Fit) -> some View {
        let on = selected?.identifier == p.identifier
        return Button {
            selected = p
            Haptics.tick()
        } label: {
            HStack(spacing: Sp.md + 2) {
                ZStack {
                    Circle().strokeBorder(on ? Color.q.gold : Color.q.onBlueSoft, lineWidth: 2)
                    if on {
                        Circle().fill(Color.q.gold)
                        Circle().fill(Color.q.onGold).frame(width: 8, height: 8)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    HStack(spacing: Sp.sm) {
                        Text(planName(p)).qText(.headline).lineLimit(1)
                        if let off = discount(p) {
                            Text(verbatim: "−\(off)%")
                                .font(.q(.label)).foregroundStyle(Color.q.onGold)
                                .padding(.horizontal, Sp.sm).padding(.vertical, Sp.xxs)
                                .background(Color.q.gold, in: Capsule())
                                .fixedSize()
                        }
                    }
                    Text(planNote(p)).qText(.caption).foregroundStyle(Color.q.blueMist).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: Sp.sm)
                VStack(alignment: .trailing, spacing: 0) {
                    // The anchor: what six single months would cost, struck through.
                    if let anchor = anchorPrice(p) {
                        Text(anchor).qText(.caption).strikethrough().foregroundStyle(Color.q.blueMist)
                    }
                    Text(p.storeProduct.localizedPriceString).qText(.number).fixedSize()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Sp.lg)
            .frame(minHeight: fit.row)
            .background(on ? Color.q.onBlueFill : Color.q.onBlueFaint, in: RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous)
                .strokeBorder(on ? Color.q.gold : Color.q.onBlueLine, lineWidth: 2))
            .animation(Motion.snappy, value: on)
        }
        .buttonStyle(.qPressCard)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "920 ₸ в неделю", or the intro offer when this person can still get it.
    private func planNote(_ p: Package) -> String {
        if let intro = introOffer(p) {
            return t("pw.introNote", ["intro": intro.localizedPriceString, "period": introPeriod(intro)])
        }
        if p.packageType == .weekly { return t("pw.tryIt") }
        return p.storeProduct.localizedPricePerWeek.map { t("pw.perWeek", ["price": $0]) } ?? ""
    }

    private func introOffer(_ p: Package) -> StoreProductDiscount? {
        guard introEligible.contains(p.storeProduct.productIdentifier) else { return nil }
        return p.storeProduct.introductoryDiscount
    }

    /// "первая неделя", "первый месяц", "первые 3 дня".
    private func introPeriod(_ d: StoreProductDiscount) -> String {
        let period = d.subscriptionPeriod
        let n = period.value * max(d.numberOfPeriods, 1)
        switch period.unit {
        case .week where n == 1: return t("pw.firstWeek")
        case .month where n == 1: return t("pw.firstMonth")
        case .day: return tn("pw.firstDays", n)
        case .week: return tn("pw.firstDays", n * 7)
        default: return tn("pw.firstDays", n * 30)
        }
    }

    /// Six months against six single months, from the store's real prices. Shown from 10% up.
    private func discount(_ p: Package) -> Int? {
        guard p.packageType == .sixMonth, let m = monthly?.storeProduct.price, m > 0 else { return nil }
        let full = m * 6
        let off = NSDecimalNumber(decimal: (full - p.storeProduct.price) / full * 100).doubleValue
        return off >= 10 ? Int(off.rounded()) : nil
    }

    private func anchorPrice(_ p: Package) -> String? {
        guard discount(p) != nil, let m = monthly?.storeProduct.price,
              let f = p.storeProduct.priceFormatter else { return nil }
        return f.string(from: NSDecimalNumber(decimal: m * 6))
    }

    // MARK: buy

    private var buyButton: some View {
        Button { Task { await buy() } } label: {
            BusyLabel(title: buyTitle, busy: buying, spinner: Color.q.onGold)
        }
        .buttonStyle(.q(.accent))
        .disabled(selected == nil || buying)
        // One slow light across the button after the screen settles.
        .overlay {
            GeometryReader { g in
                LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.35)
                    .offset(x: shine ? g.size.width * 1.1 : -g.size.width * 0.5)
                    .blendMode(.plusLighter)
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .opacity(Motion.reduceMotion ? 0 : 1)
        }
    }

    /// The billed price stays the most visible amount: on the button when there's no intro
    /// offer, and in the row (with the full terms under the button) when there is.
    private var buyTitle: String {
        guard let p = selected else { return t("paywall.buy") }
        if introOffer(p) != nil { return t("paywall.buy") }
        return t("pw.buyPrice", ["price": p.storeProduct.localizedPriceString])
    }

    @ViewBuilder private var afterButton: some View {
        if let p = selected, let intro = introOffer(p) {
            Text(t("pw.introTerms", ["intro": intro.localizedPriceString, "period": introPeriod(intro),
                                     "price": p.storeProduct.localizedPriceString, "every": planEvery(p)]))
                .qText(.caption).foregroundStyle(Color.q.blueMist).multilineTextAlignment(.center)
        } else if let n = proInCity {
            Text(t("pw.proof", ["city": Cities.label(session.profile?.city ?? ""), "n": n.formatted()]))
                .qText(.caption).foregroundStyle(Color.q.blueMist).multilineTextAlignment(.center)
        }
    }

    private func planEvery(_ p: Package) -> String {
        switch p.packageType {
        case .weekly: t("pw.everyWeek")
        case .sixMonth: t("pw.every6")
        default: t("pw.everyMonth")
        }
    }

    // MARK: footer

    /// Restore and the documents, small and calm on a frosted bar: present and readable,
    /// never louder than the offer.
    private var footer: some View {
        VStack(spacing: Sp.xs) {
            HStack(spacing: Sp.xs) {
                Button(t("pw.restore")) { Task { await restore() } }.buttonStyle(.plain).disabled(buying)
                Text(verbatim: "·").foregroundStyle(Color.q.blueMist)
                Link(t("legal.terms"), destination: Config.termsURL).underline()
                Text(verbatim: "·").foregroundStyle(Color.q.blueMist)
                Link(t("legal.privacy"), destination: Config.privacyURL).underline()
            }
            .font(.q(.caption))
            .foregroundStyle(.white)
            .tint(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Text(t("paywall.legal"))
                .font(.q(.caption)).fontWeight(.medium)
                .foregroundStyle(Color.q.blueMist)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, Layout.margin)
        .padding(.top, Sp.md)
        .padding(.bottom, Sp.sm)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                .overlay(alignment: .top) { Rectangle().fill(Color.q.onBlueLine).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private static var nextMidnight: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Almaty") ?? .current
        return cal.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? .now
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
        loading = false
        // Who can still get the first-week price (once per person, per Apple).
        var eligible: Set<String> = []
        for p in packages where p.storeProduct.introductoryDiscount != nil {
            if await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: p.storeProduct) == .eligible {
                eligible.insert(p.storeProduct.productIdentifier)
            }
        }
        introEligible = eligible
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
            if session.limits?.pro == true {
                withMotion(Motion.smooth) { welcome = true }
            } else {
                // Paid, but the store's note to our server is late: say so instead of a welcome
                // whose Pro features (like the gift) wouldn't work yet, and keep checking.
                toasts.show(t("paywall.pending"), symbol: "hourglass")
                let session = session
                Task { await PaywallView.keepChecking(session) }
                dismiss()
            }
        } catch {
            toasts.show(error)
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
            toasts.show(error)
        }
    }

    /// After a slow purchase: check every 10 seconds for two minutes, so Pro turns on by itself.
    @MainActor static func keepChecking(_ session: SessionStore) async {
        for _ in 0..<12 {
            try? await Task.sleep(for: .seconds(10))
            await session.refreshLimits()
            if session.limits?.pro == true { Haptics.success(); return }
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
        } catch { toasts.show(error) }
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
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            Text(t("cover.redeemTitle")).qText(.title3).accessibilityAddTraits(.isHeader)
            TextField("K7MD-P2QA", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.q(.title3))
                .qField(isError: error != nil)
                .focused($typing)
                .submitLabel(.done)
                .onSubmit { if code.count >= 4 { Task { await redeem() } } }
                .onChange(of: code) { _, _ in error = nil }
            if let error { Text(error).qText(.callout).foregroundStyle(Color.q.danger) }
            Button { Task { await redeem() } } label: { BusyLabel(title: t("cover.redeem"), busy: busy) }
                .buttonStyle(.qPrimary)
                .disabled(code.count < 4 || busy)
        }
        .padding(Layout.margin)
        .padding(.top, Sp.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .qSheet(detents: [.height(300)])
        .onAppear { typing = true }
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
        } catch { self.error = errorText(error) }
    }
}
