// No matches yet: how many people you've liked so far, then what would make your
// profile stronger. Each unfinished item opens the screen that fixes it.
import SwiftUI

struct PairsEmpty: View {
    var goDiscover: () -> Void

    @Environment(SessionStore.self) private var session
    /// nil until loaded, or if the server doesn't have the count yet: the line is hidden.
    @State private var likesSent: Int?
    @State private var hasPrompts = false

    private struct Item: Identifiable {
        enum Kind { case photos, about, challenge, prompts, verify }
        let kind: Kind
        let title: String
        let symbol: String
        let done: Bool
        var id: Kind { kind }
    }

    private var items: [Item] {
        guard let p = session.profile else { return [] }
        let filled = { (s: String?) in !(s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return [
            Item(kind: .photos, title: t("empty.itemPhotos", ["n": min(p.photos.count, 3)]),
                 symbol: "photo.on.rectangle", done: p.photos.count >= 3),
            Item(kind: .about, title: t("empty.itemAbout"), symbol: "text.alignleft", done: filled(p.bio)),
            Item(kind: .challenge, title: t("empty.itemChallenge"), symbol: "flag", done: filled(p.nextChallenge)),
            Item(kind: .prompts, title: t("empty.itemPrompts"), symbol: "text.quote", done: hasPrompts),
            Item(kind: .verify, title: t("empty.itemVerify"), symbol: "checkmark.seal",
                 done: p.verificationStatus == .approved || p.verificationStatus == .pending),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Sp.xl) {
                VStack(spacing: Sp.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Color.q.muted)
                        .accessibilityHidden(true)
                    Text(t("matches.empty")).qText(.title3).foregroundStyle(Color.q.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if let n = likesSent, n > 0 {
                        Text(t("empty.likesSent", ["n": n])).qText(.headline).foregroundStyle(Color.q.blueText)
                            .contentTransition(.numericText())
                        Text(t("empty.likesSentSub")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(t("matches.emptySubApp")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    Button(t("matches.goDiscover"), action: goDiscover)
                        .buttonStyle(.q(.primary, compact: true))
                        .fixedSize()
                        .padding(.top, Sp.xs)
                }
                .padding(.top, Sp.xxl)

                if !items.isEmpty { checklist }
            }
            .padding(.horizontal, Layout.margin)
            .padding(.bottom, Sp.xl)
        }
        .background(Color.q.bg)
        .task { await load() }
    }

    private var checklist: some View {
        let done = items.filter(\.done).count
        return VStack(alignment: .leading, spacing: Sp.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t(done == items.count ? "empty.strengthDone" : "empty.strengthTitle"))
                        .qText(.headline).foregroundStyle(Color.q.ink)
                    if done < items.count {
                        Text(t("empty.strengthSub")).qText(.footnote).foregroundStyle(Color.q.muted)
                    }
                }
                Spacer(minLength: Sp.sm)
                Text("\(done)/\(items.count)").qText(.number).foregroundStyle(Color.q.blueText)
                    .accessibilityHidden(true)
            }
            ProgressView(value: Double(done), total: Double(items.count))
                .tint(Color.q.blue)
                .accessibilityHidden(true)
            VStack(spacing: Sp.sm) {
                ForEach(items) { item in
                    if item.done {
                        row(item)
                    } else {
                        NavigationLink { destination(item.kind) } label: { row(item) }
                            .buttonStyle(QPressStyle())
                    }
                }
            }
        }
        .padding(Sp.lg)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: Sp.md) {
            Image(systemName: item.done ? "checkmark.circle.fill" : item.symbol)
                .font(.q(.callout))
                .foregroundStyle(item.done ? Color.q.good : Color.q.blueText)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(item.title).qText(.callout)
                .foregroundStyle(item.done ? Color.q.muted : Color.q.ink)
                .strikethrough(item.done, color: Color.q.hint)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !item.done {
                Image(systemName: "chevron.right")
                    .font(.q(.footnote).weight(.semibold))
                    .foregroundStyle(Color.q.hint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Sp.md)
        .frame(minHeight: Layout.rowMin)
        .background(Color.q.bg, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(t(item.done ? "empty.done" : "empty.todo"))
    }

    @ViewBuilder private func destination(_ kind: Item.Kind) -> some View {
        switch kind {
        case .photos, .about, .challenge: EditProfileView()
        case .prompts: PromptsEditor()
        case .verify: VerifyView()
        }
    }

    private func load() async {
        async let sent = try? Backend.likesSent()
        if let id = session.userId, let card = try? await Backend.profile(id) {
            hasPrompts = !(card.prompts ?? []).isEmpty
        }
        let n = await sent
        withMotion(Motion.smooth) { likesSent = n }
    }
}
