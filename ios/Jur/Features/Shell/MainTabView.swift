// The four tabs. The system tab bar on purpose: on iOS 26 it becomes the floating
// Liquid Glass bar by itself, and it keeps re-tap-to-top and accessibility for free.
// Counts (new likes, unread chats) go on tabs with `.badge(n)`, never custom dots.
// Title rule: root tabs use `.inlineLarge` (large title on the toolbar's row);
// Discover shows the lockup inline; pushed screens are `.inline`.
import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable { case discover, events, matches, me }
    @State private var tab: Tab = .discover

    var body: some View {
        TabView(selection: $tab) {
            DiscoverPlaceholder()
                .tabItem { Label(t("tabs.discover"), systemImage: "safari") }
                .tag(Tab.discover)
            if Config.eventsEnabled {
                ComingSoonTab(titleKey: "tabs.events", symbol: "ticket")
                    .tabItem { Label(t("tabs.events"), systemImage: "ticket") }
                    .tag(Tab.events)
            }
            ComingSoonTab(titleKey: "tabs.matches", symbol: "bubble.left.and.bubble.right")
                .tabItem { Label(t("tabs.matches"), systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.matches)
            MeView()
                .tabItem { Label(t("tabs.me"), systemImage: "person.crop.circle") }
                .tag(Tab.me)
        }
    }
}

/// Milestone 1 stand-in for screens rebuilt next.
struct ComingSoonTab: View {
    let titleKey: String
    let symbol: String
    var body: some View {
        NavigationStack {
            QEmptyState(symbol: symbol, title: t("ios.comingSoon"), message: t("ios.comingSoonSub"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(t(titleKey))
                .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

private struct DiscoverPlaceholder: View {
    @Environment(SessionStore.self) private var session
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Sp.lg) {
                    if let p = session.profile {
                        Text(t(greetingKey(), ["name": p.name]))
                            .qText(.footnote).foregroundStyle(Color.q.inkSoft)
                    }
                    QEmptyState(symbol: "safari", title: t("ios.comingSoon"), message: t("ios.comingSoonSub"))
                }
                .padding(Layout.margin)
            }
            .background(Color.q.bg)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Lockup(size: 20) }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// "Good morning / afternoon / evening" by Almaty time.
func greetingKey(_ date: Date = .now) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Almaty") ?? .current
    let h = cal.component(.hour, from: date)
    return h >= 5 && h < 12 ? "greet.morning" : (h >= 18 || h < 5) ? "greet.evening" : "greet.day"
}
