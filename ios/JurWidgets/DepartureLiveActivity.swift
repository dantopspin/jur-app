// "Your departure": a countdown to an event you're going to, on the lock screen and in
// the Dynamic Island. Styled like the departure board: navy, gold time, white title.
import ActivityKit
import SwiftUI
import WidgetKit

private enum Board {
    static let ground = Color(red: 0x12 / 255, green: 0x3A / 255, blue: 0x64 / 255)
    static let gold = Color(red: 0xE2 / 255, green: 0xA6 / 255, blue: 0x3B / 255)
    static let mist = Color(red: 0xDC / 255, green: 0xE7 / 255, blue: 0xF3 / 255)
}

struct DepartureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureAttributes.self) { context in
            LockScreenDeparture(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Board.ground)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(link(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.attributes.sportEmoji)
                        Text(context.attributes.title)
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(attributes: context.attributes, state: context.state, large: false)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GateLine(attributes: context.attributes, state: context.state)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                JurMarkShape()
                    .stroke(Board.gold, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                Countdown(attributes: context.attributes, state: context.state, large: false)
            } minimal: {
                JurMarkShape()
                    .stroke(Board.gold, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
            }
            .widgetURL(link(context.attributes))
            .keylineTint(Board.gold)
        }
    }

    private func link(_ a: DepartureAttributes) -> URL? {
        URL(string: "jur://event/\(a.eventId.uuidString.lowercased())")
    }
}

/// Minutes to the start, counting down by itself (no app updates needed). Once the
/// person has checked in it says so instead.
private struct Countdown: View {
    let attributes: DepartureAttributes
    let state: DepartureAttributes.ContentState
    var large = true

    var body: some View {
        if state.checkedIn {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Board.gold)
                .accessibilityLabel(attributes.words.checkedIn)
        } else {
            Text(timerInterval: Date.now...max(attributes.start, .now), countsDown: true, showsHours: true)
                .font(.system(large ? .title : .headline, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(Board.gold)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: large ? 120 : 64, alignment: .trailing)
        }
    }
}

private struct GateLine: View {
    let attributes: DepartureAttributes
    let state: DepartureAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            Text(attributes.words.gate.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Board.mist)
            Text(attributes.place)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(attributes.words.going.replacingOccurrences(of: "{n}", with: "\(state.going)"))
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Board.mist)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

private struct LockScreenDeparture: View {
    let attributes: DepartureAttributes
    let state: DepartureAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        JurMarkShape()
                            .stroke(Board.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(state.checkedIn ? attributes.words.checkedIn.uppercased() : attributes.words.startsIn.uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(Board.gold)
                    }
                    Text("\(attributes.sportEmoji) \(attributes.title)")
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Countdown(attributes: attributes, state: state)
            }
            ProgressView(timerInterval: attributes.start.addingTimeInterval(-3 * 3600)...max(attributes.start, .now), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Board.gold)
            GateLine(attributes: attributes, state: state)
        }
        .padding(16)
    }
}
