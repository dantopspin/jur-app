// A one-time code entered into separate boxes: 6 for the email code, 4 for boarding.
// One hidden text field does the typing, so paste and "From Messages" autofill work.
import SwiftUI

struct CodeField: View {
    let length: Int
    @Binding var code: String
    var isError = false
    var accessibilityLabel: String
    var onComplete: (String) -> Void = { _ in }
    @FocusState private var focused: Bool
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.02)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(length))
                    if digits != new { code = digits }
                    if digits.count == length { onComplete(digits) }
                }
                .accessibilityLabel(accessibilityLabel)
            HStack(spacing: Sp.sm) {
                ForEach(0..<length, id: \.self) { i in box(i) }
            }
            .animation(Motion.snappy, value: code)
            .animation(Motion.snappy, value: isError)
            // A wrong code shakes the row: three swings, settling.
            .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-10, duration: 0.06)
                    LinearKeyframe(10, duration: 0.08)
                    LinearKeyframe(-8, duration: 0.08)
                    LinearKeyframe(8, duration: 0.08)
                    LinearKeyframe(-4, duration: 0.07)
                    SpringKeyframe(0, duration: 0.15)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onChange(of: isError) { _, wrong in if wrong && !reduceMotion { shakes += 1 } }
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }

    private func box(_ i: Int) -> some View {
        let chars = Array(code)
        let isNext = i == min(chars.count, length - 1) && focused
        let stroke: Color = isError ? Color.q.danger : (isNext ? Color.q.blue : .clear)
        return Text(i < chars.count ? String(chars[i]) : "")
            .qText(.title1)
            .contentTransition(.numericText())
            .foregroundStyle(Color.q.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(stroke, lineWidth: 2))
    }
}

#Preview {
    VStack(spacing: Sp.xl) {
        CodeField(length: 6, code: .constant("1234"), accessibilityLabel: "Code")
        CodeField(length: 4, code: .constant("47"), isError: true, accessibilityLabel: "Code")
    }
    .padding()
    .background(Color.q.bg)
}
