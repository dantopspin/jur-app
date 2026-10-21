// Qadam Home Screen widget. Reads a small JSON snapshot that the app writes to
// the shared App Group (src/lib/widget.ts) and shows likes, unread chats and the
// next event you joined. Strings arrive already translated by the app.
import SwiftUI
import WidgetKit

private let appGroup = "group.kz.qadam.app"
private let blue = Color(red: 31 / 255, green: 95 / 255, blue: 160 / 255)
private let blueDeep = Color(red: 24 / 255, green: 76 / 255, blue: 130 / 255)
private let gold = Color(red: 226 / 255, green: 166 / 255, blue: 59 / 255)
private let mist = Color(red: 220 / 255, green: 231 / 255, blue: 243 / 255)

struct Snapshot: Codable {
  struct Event: Codable { let id: String; let title: String; let when: String; let place: String }
  struct Labels: Codable { let likes: String; let unread: String; let next: String; let none: String }
  let likes: Int
  let unread: Int
  let event: Event?
  let labels: Labels

  static let sample = Snapshot(
    likes: 12, unread: 2,
    event: Event(id: "", title: "Saturday 5K", when: "Sat, 08:00", place: "Medeu gate"),
    labels: Labels(likes: "liked you", unread: "unread", next: "Next", none: "Find an event this weekend"))
}

struct Entry: TimelineEntry {
  let date: Date
  let snap: Snapshot
}

struct Provider: TimelineProvider {
  func read() -> Snapshot {
    guard let json = UserDefaults(suiteName: appGroup)?.string(forKey: "widget"),
          let data = json.data(using: .utf8),
          let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return .sample }
    return snap
  }
  func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .sample) }
  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(Entry(date: Date(), snap: context.isPreview ? .sample : read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let entry = Entry(date: Date(), snap: read())
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
  }
}

/// The Qadam mark: two strokes curling into a heart (100 × 100 design box).
struct MarkShape: Shape {
  func path(in r: CGRect) -> Path {
    let s = min(r.width, r.height) / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
    var path = Path()
    for m: CGFloat in [1, -1] {
      func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { p(m == 1 ? x : 100 - x, y) }
      path.move(to: q(50, 88))
      path.addCurve(to: q(14, 38), control1: q(30, 70), control2: q(14, 56))
      path.addCurve(to: q(40, 18), control1: q(14, 22), control2: q(28, 14))
      path.addCurve(to: q(40, 38), control1: q(50, 22), control2: q(50, 36))
      path.addCurve(to: q(33, 30), control1: q(34, 39), control2: q(30, 34))
    }
    return path
  }
}

struct Mark: View {
  var size: CGFloat
  var body: some View {
    MarkShape()
      .stroke(gold, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round, lineJoin: .round))
      .frame(width: size, height: size)
  }
}

/// The horizon line along the bottom.
struct Horizon: Shape {
  func path(in r: CGRect) -> Path {
    let pts: [(CGFloat, CGFloat)] = [(0, 62), (60, 48), (110, 58), (170, 28), (220, 46), (280, 20), (330, 42), (390, 32)]
    var path = Path()
    path.move(to: CGPoint(x: r.minX, y: r.maxY))
    for (x, y) in pts { path.addLine(to: CGPoint(x: r.minX + x / 390 * r.width, y: r.minY + y / 90 * r.height)) }
    path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    path.closeSubpath()
    return path
  }
}

struct Background: ViewModifier {
  func body(content: Content) -> some View {
    let bg = ZStack(alignment: .bottom) {
      blue
      Horizon().fill(blueDeep).frame(height: 34)
    }
    if #available(iOSApplicationExtension 17.0, *) {
      return AnyView(content.containerBackground(for: .widget) { bg })
    } else {
      return AnyView(content.padding().background(bg))
    }
  }
}

struct QadamWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: Entry

  var counts: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(entry.snap.likes)")
        .font(.system(size: 34, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
      Text(entry.snap.labels.likes)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(mist)
      if entry.snap.unread > 0 {
        Text("\(entry.snap.unread) \(entry.snap.labels.unread)")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Color(red: 27 / 255, green: 36 / 255, blue: 48 / 255))
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(Capsule().fill(gold))
          .padding(.top, 4)
      }
    }
  }

  var event: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(entry.snap.labels.next.uppercased())
        .font(.system(size: 11, weight: .heavy)).tracking(0.8)
        .foregroundStyle(gold)
      if let e = entry.snap.event {
        Text(e.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(2)
        Text(e.when).font(.system(size: 13, weight: .semibold)).foregroundStyle(mist)
        Text(e.place).font(.system(size: 12, weight: .medium)).foregroundStyle(mist).lineLimit(1)
      } else {
        Text(entry.snap.labels.none).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(3)
      }
    }
  }

  var body: some View {
    Group {
      if family == .systemMedium {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading) { Mark(size: 30); Spacer(); counts }
          Rectangle().fill(mist.opacity(0.25)).frame(width: 1)
          event
          Spacer(minLength: 0)
        }
      } else {
        VStack(alignment: .leading) {
          Mark(size: 28)
          Spacer()
          counts
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .modifier(Background())
    .widgetURL(URL(string: entry.snap.event.map { "qadam://event/\($0.id)" } ?? "qadam://likes"))
  }
}

struct QadamWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "QadamWidget", provider: Provider()) { entry in
      QadamWidgetView(entry: entry)
    }
    .configurationDisplayName("Qadam")
    .description("Likes, messages and your next event.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct QadamWidgets: WidgetBundle {
  var body: some Widget {
    QadamWidget()
  }
}
