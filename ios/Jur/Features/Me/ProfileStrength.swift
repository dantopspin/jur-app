// What makes a profile complete: photos, a few words, a goal, a prompt, verification.
// Shown on Me (until everything is done) and on the empty Matches screen.
import SwiftUI

struct ProfileStrength {
    enum Kind: CaseIterable { case photos, about, challenge, prompts, verify }

    struct Item: Identifiable {
        let kind: Kind
        let title: String
        let symbol: String
        let done: Bool
        var id: Kind { kind }
    }

    let items: [Item]
    var done: Int { items.filter(\.done).count }
    var complete: Bool { done == items.count }

    init(profile p: MyProfile, hasPrompts: Bool) {
        let filled = { (s: String?) in !(s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        items = [
            Item(kind: .photos, title: t("empty.itemPhotos", ["n": min(p.photos.count, 3)]),
                 symbol: "photo.on.rectangle", done: p.photos.count >= 3),
            Item(kind: .about, title: t("empty.itemAbout"), symbol: "text.alignleft", done: filled(p.bio)),
            Item(kind: .challenge, title: t("empty.itemChallenge"), symbol: "flag", done: filled(p.nextChallenge)),
            Item(kind: .prompts, title: t("empty.itemPrompts"), symbol: "text.quote", done: hasPrompts),
            // A selfie waiting for review counts: there's nothing more the person can do.
            Item(kind: .verify, title: t("empty.itemVerify"), symbol: "checkmark.seal",
                 done: p.verificationStatus == .approved || p.verificationStatus == .pending),
        ]
    }
}

/// The checklist card. Tapping an unfinished item calls `open`; the screen showing the
/// card navigates (List rows can't hold several links), usually to `destination(for:)`.
struct ProfileStrengthCard: View {
    let strength: ProfileStrength
    let open: (ProfileStrength.Kind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t(strength.complete ? "empty.strengthDone" : "empty.strengthTitle"))
                        .qText(.headline).foregroundStyle(Color.q.ink)
                    if !strength.complete {
                        Text(t("empty.strengthSub")).qText(.footnote).foregroundStyle(Color.q.muted)
                    }
                }
                Spacer(minLength: Sp.sm)
                Text("\(strength.done)/\(strength.items.count)").qText(.number).foregroundStyle(Color.q.blueText)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
            }
            ProgressView(value: Double(strength.done), total: Double(strength.items.count))
                .tint(Color.q.blue)
                .accessibilityHidden(true)
            VStack(spacing: Sp.sm) {
                ForEach(strength.items) { item in
                    if item.done {
                        row(item)
                    } else {
                        Button { open(item.kind) } label: { row(item) }
                            .buttonStyle(QPressStyle())
                    }
                }
            }
        }
        .padding(Sp.lg)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func row(_ item: ProfileStrength.Item) -> some View {
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

}

extension ProfileStrength.Kind {
    /// The screen that finishes this item.
    @ViewBuilder var destination: some View {
        switch self {
        case .photos, .about, .challenge: EditProfileView()
        case .prompts: PromptsEditor()
        case .verify: VerifyView()
        }
    }
}
