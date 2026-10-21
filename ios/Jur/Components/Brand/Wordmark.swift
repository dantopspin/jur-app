// The JÜR wordmark. The Ü's two dots are drawn separately: two people, the brand's
// smallest device. They can take their own colour (gold on blue, blue on chalk).
import SwiftUI

struct Wordmark: View {
    var size: CGFloat = 22
    var ink: Color = Color.q.ink
    var dots: Color = Color.q.blueText

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.06) {
            letter("J")
            letter("U")
                .overlay(alignment: .top) {
                    HStack(spacing: size * 0.2) {
                        Circle().fill(dots).frame(width: size * 0.2, height: size * 0.2)
                        Circle().fill(dots).frame(width: size * 0.2, height: size * 0.2)
                    }
                    .offset(y: -size * 0.24)
                }
            letter("R")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("JÜR")
    }

    private func letter(_ s: String) -> some View {
        Text(s)
            .font(.qFont("Unbounded-ExtraBold", size: size, relativeTo: .title, weight: .heavy))
            .foregroundStyle(ink)
            .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

/// The two dots meeting: a loading indicator and the match moment's opening beat.
struct DotsMeeting: View {
    var size: CGFloat = 12
    var color: Color = Color.q.blueText
    @State private var together = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: together ? size * 0.15 : size * 1.4) {
            Circle().fill(color).frame(width: size, height: size)
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size * 4, height: size)
        .onAppear {
            guard !reduceMotion else { together = true; return }
            withAnimation(.spring(duration: 0.8, bounce: 0.3).repeatForever(autoreverses: true)) { together = true }
        }
        .accessibilityElement()
        .accessibilityLabel(t("common.loading"))
    }
}

#Preview {
    VStack(spacing: 40) {
        Wordmark(size: 84, ink: .white, dots: Color.q.gold).padding().background(Color.q.blue)
        Wordmark(size: 22)
        DotsMeeting()
    }
}
