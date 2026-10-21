// Pro is the passport cover: deep blue, gold mark, gold wordmark, member №.
// Shown after purchase and on the Pro screen; the gift card sits below it.
import SwiftUI

struct MembershipCover: View {
    let memberNo: String   // "№0042"
    var tilted = true
    /// Lift the cover in once when it appears (skipped under Reduce Motion).
    var animatesIn = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text(t("cover.title"))
                .font(.q(.label))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Color.q.gold)
            MarkView(size: 96, color: Color.q.gold).padding(.top, Sp.xxl)
            HStack(alignment: .lastTextBaseline, spacing: Sp.sm) {
                Wordmark(size: 30, ink: Color.q.gold, dots: Color.q.gold)
                Text(verbatim: "PRO")
                    .font(.qFont("Unbounded-ExtraBold", size: 14, relativeTo: .caption, weight: .heavy))
                    .tracking(2).foregroundStyle(Color.q.gold)
            }
            .padding(.top, Sp.xl)
            Spacer(minLength: Sp.md)
            RidgeShape(layer: .line)
                .stroke(Color.q.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 210, height: 34)
                .padding(.bottom, Sp.md)
            Text(memberNo)
                .qText(.title3)
                .monospacedDigit()
                .foregroundStyle(Color.q.gold)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.vertical, Sp.xl)
        .padding(.horizontal, Sp.lg)
        .frame(width: 250, height: 340)
        .background(Color.q.coverGround, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        // The hero exception to qElevated: the cover is an object held up to the camera.
        .shadow(color: Color.q.boardShade.opacity(0.45), radius: 20, y: 18)
        .rotationEffect(.degrees(tilted ? -3 : 0))
        .scaleEffect(shown ? 1 : 0.92)
        .opacity(shown ? 1 : 0)
        .onAppear {
            guard animatesIn, !reduceMotion else { shown = true; return }
            withAnimation(.spring(duration: 0.6, bounce: 0.25)) { shown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("JÜR Pro, \(memberNo)")
    }
}

/// "Give a friend a week of Pro." Shows the code once one exists.
struct GiftCard: View {
    var code: String?
    var busy = false
    let onSend: () -> Void
    var onCopy: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            Text(t("cover.giftLabel")).qText(.overline).foregroundStyle(Color.q.clayDeep)
            Text(t("cover.giftTitle")).qText(.headline)
            if let code {
                HStack {
                    Text(code)
                        .font(.q(.title2).monospacedDigit())
                        .tracking(3)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        Haptics.success()
                        onCopy?()
                    } label: {
                        Image(systemName: "doc.on.doc").font(.q(.headline))
                            .foregroundStyle(Color.q.blueText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(t("chat2.copy"))
                }
                .padding(.leading, Sp.lg)
                .background(Color.q.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            Button(action: onSend) { BusyLabel(title: t("cover.giftSend"), busy: busy, spinner: Color.q.onGold) }
                .buttonStyle(.qAccent)
                .disabled(busy)
            Text(t("cover.giftRule")).qText(.caption)
                .foregroundStyle(Color.q.muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .qCard()
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            MembershipCover(memberNo: "№0042")
            Text(t("cover.welcome")).qText(.title2).foregroundStyle(.white)
            GiftCard(code: "K7MD-P2QA", onSend: {})
        }
        .padding()
    }
    .background(Color.q.blue)
}
