// The four tabs. The system tab bar on purpose: on iOS 26 it becomes the floating
// Liquid Glass bar by itself, and it keeps re-tap-to-top and accessibility for free.
// Counts (new likes, unread chats) go on tabs with `.badge(n)`, never custom dots.
// Title rule: root tabs use `.inlineLarge` (large title on the toolbar's row);
// Discover shows the lockup inline; pushed screens are `.inline`.
import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable { case discover, events, matches, me }
    @Environment(SportsCatalog.self) private var catalog
    @State private var tab: Tab = .discover
    @State private var pairs = PairsModel()
    @State private var chatPath: [UUID] = []
    @State private var eventPath: [UUID] = []
    @State private var showLikes = false
    @State private var showPicks = false
    @State private var router = Router.shared

    var body: some View {
        TabView(selection: $tab) {
            DiscoverView(showPicks: $showPicks, openEvents: { tab = Config.eventsEnabled ? .events : .discover },
                         openChat: { id in
                             tab = .matches
                             chatPath = [id]
                             Task { await pairs.load() }
                         })
                .tabItem { Label(t("tabs.discover"), systemImage: "safari") }
                .tag(Tab.discover)
            if Config.eventsEnabled {
                EventsView(path: $eventPath)
                    .tabItem { Label(t("tabs.events"), systemImage: "ticket") }
                    .tag(Tab.events)
            }
            PairsView(model: pairs, path: $chatPath, showLikes: $showLikes, goDiscover: { tab = .discover })
                .tabItem { Label(t("tabs.matches"), systemImage: "bubble.left.and.bubble.right") }
                .badge(pairs.unread)
                .tag(Tab.matches)
            MeView()
                .tabItem { Label(t("tabs.me"), systemImage: "person.crop.circle") }
                .tag(Tab.me)
        }
        .onChange(of: router.pending) { _, dest in
            guard let dest else { return }
            router.pending = nil
            switch dest {
            case .chat(let id): tab = .matches; chatPath = [id]; Task { await pairs.load() }
            case .matches: tab = .matches
            case .likes: tab = .matches; showLikes = true
            case .event(let id): if Config.eventsEnabled { tab = .events; eventPath = [id] }
            case .picks: tab = .discover; showPicks = true
            case .discover: tab = .discover
            }
        }
        .task {
            await catalog.load()
            await pairs.load()
            await Push.refresh()
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
