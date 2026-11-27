import SwiftUI

@main
struct JapaneseGrammarScannerApp: App {
    @StateObject private var languages = LanguageStore()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var entitlements = EntitlementStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var appearance = AppearanceStore.shared
    @StateObject private var favoriteFlight = FavoriteFlight()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appearance)
                .environmentObject(languages)
                .environmentObject(languages.library)
                .environment(\.locale, languages.language.locale ?? .autoupdatingCurrent)
                .environmentObject(favorites)
                .environmentObject(entitlements)
                .environmentObject(history)
                .environmentObject(favoriteFlight)
                .overlay { FavoriteFlightOverlay(model: favoriteFlight) }
                .overlay(alignment: .bottomLeading) {
                    if DemoMode.e2e { LanguageDiagnostics(code: languages.language.rawValue) }
                }
        }
    }
}

private struct LanguageDiagnostics: View {
    let code: String

    var body: some View {
        let key = "语言"
        let lproj = Bundle.main.path(forResource: code, ofType: "lproj")
        let sub = lproj.flatMap { Bundle(path: $0) }
        let files = lproj.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0) } ?? []
        let rootTables = (try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundlePath))?
            .filter { $0.hasSuffix(".lproj") || $0.contains("loctable") || $0.hasSuffix(".strings") } ?? []
        let info = [
            "code=\(code)",
            "class=\(String(describing: type(of: Bundle.main)))",
            "main=\(Bundle.main.localizedString(forKey: key, value: "∅", table: nil))",
            "sub=\(sub?.localizedString(forKey: key, value: "∅", table: nil) ?? "nolproj")",
            "files=\(files.joined(separator: "+"))",
            "root=\(rootTables.joined(separator: "+"))",
            "pref=\(Bundle.main.preferredLocalizations.joined(separator: "+"))",
            "locs=\(Bundle.main.localizations.joined(separator: "+"))",
        ].joined(separator: " | ")
        VStack(spacing: 0) {
            Text(verbatim: info)
                .accessibilityIdentifier("lang.debug")
            Text(localized: "语言")
                .accessibilityIdentifier("lang.debug.text")
        }
        .font(.system(size: 2))
        .opacity(0.02)
        .allowsHitTesting(false)
        .frame(width: 2, height: 2)
    }
}

extension Notification.Name {
    static let openSamplePage = Notification.Name("openSamplePage")
    static let showOnboarding = Notification.Name("showOnboarding")
    static let popToRoot = Notification.Name("popToRoot")
    static let focusSearch = Notification.Name("focusSearch")
    static let showSettings = Notification.Name("showSettings")
    static let showFeedback = Notification.Name("showFeedback")
}

enum AppTab {
    static let home = 0, scan = 1, library = 2, favorites = 3, search = 4
    static let count = 5
}

struct RootTabView: View {
    @State private var tab: Int = {
        switch DemoMode.screen {
        case "home": 0
        case "scan", "result", "detail": 1
        case "library": 2
        case "favorites": 3
        case "search": 4
        default: 0
        }
    }()
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favoriteFlight: FavoriteFlight
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    private static var didLaunchSetup = false
    @State private var showOnboarding = false

    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var languages: LanguageStore
    @State private var showSettings = false
    @State private var feedbackContext: FeedbackContext?

    struct FeedbackContext: Identifiable {
        let id = UUID()
        let text: String?
        var kind: FeedbackView.Kind = .bug
    }

    private var selection: Binding<Int> {
        Binding(get: { tab }, set: { newValue in
            if newValue == tab || newValue == AppTab.search {
                NotificationCenter.default.post(name: .popToRoot, object: newValue)
            }
            tab = newValue
        })
    }

    var body: some View {
        tabs
            .id("\(appearance.key)-\(languages.language.rawValue)")
            .tint(Theme.accent)
            .sheet(isPresented: $showSettings) {
                SettingsSheet().tint(Theme.accent)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in showSettings = true }
            .sheet(item: $feedbackContext) { ctx in
                FeedbackView(context: ctx.text, initialKind: ctx.kind).tint(Theme.accent)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showFeedback)) { note in
                if let kind = note.object as? FeedbackView.Kind {
                    feedbackContext = FeedbackContext(text: nil, kind: kind)
                } else {
                    let text = note.object as? String
                    feedbackContext = FeedbackContext(text: text, kind: text?.hasPrefix("grammar:") == true ? .content : .bug)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in tab = AppTab.search }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { wantsSample in
                didCompleteOnboarding = true
                showOnboarding = false
                Task {
                    if DemoMode.screen == nil {
                        try? await Task.sleep(for: .milliseconds(500))
                        await entitlements.startTrialIfNeeded()
                    }
                    if wantsSample { openSample() }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in showOnboarding = true }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: UsageStats.shared.appBecameActive()
            case .background: UsageStats.shared.appMovedToBackground()
            default: break
            }
        }
        .onAppear {
            KeyboardDismisser.shared.install()
            guard !Self.didLaunchSetup else { return }
            Self.didLaunchSetup = true
            favorites.migrate(aliases: library.aliases)
            history.migrate(aliases: library.aliases)
            if DemoMode.e2e { seedForEndToEndTests() }
            if !didCompleteOnboarding, DemoMode.screen == nil || DemoMode.screen == "onboarding" {
                showOnboarding = true
            }
            if DemoMode.seedsHistory {
                let old = Date().addingTimeInterval(-10 * 86_400)
                for id in ["ni-mo-kakawarazu", "you-ni-naru", "okage-de", "te-shimau"] { history.recordViewed(id, now: old) }
                for id in ["izen", "made-until", "sou-da-appearance"] { history.recordViewed(id) }
            }
            if DemoMode.screen == "settings" { showSettings = true }
            if DemoMode.screen == "favorites", favorites.ids.isEmpty {
                for id in ["te-shimau", "you-ni-naru", "ni-mo-kakawarazu", "okage-de", "rashii-typical"].reversed() {
                    favorites.toggle(id)
                }
            }
        }
    }

    private func seedForEndToEndTests() {
        history.clearScans()
        history.clearViewed()
        for id in favorites.ids { favorites.toggle(id) }
        appearance.accent = .matcha
        appearance.light = AppearanceStore.LightBackground.allCases[0]
        appearance.dark = AppearanceStore.DarkBackground.allCases[0]
        UsageStats.shared.isEnabled = true
        if DemoMode.e2eFresh {
            didCompleteOnboarding = false
            return
        }
        didCompleteOnboarding = true
        if let image = UIImage(named: "SamplePage")?.normalizedForOCR() {
            for _ in 0..<4 {
                _ = history.recordScan(image: image, grammarIDs: ["te-shimau", "you-ni-naru", "ni-mo-kakawarazu"])
            }
        }
        let old = Date().addingTimeInterval(-10 * 86_400)
        for id in ["ni-mo-kakawarazu", "you-ni-naru", "okage-de", "te-shimau", "rashii-typical"] { history.recordViewed(id, now: old) }
        for id in ["izen", "made-until", "sou-da-appearance", "nagara", "dake-ni"] { history.recordViewed(id) }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: selection) {
                Tab(tr("首页"), systemImage: "house", value: AppTab.home) { HomeView(openCamera: { tab = AppTab.scan }) }
                Tab(tr("扫描"), systemImage: "text.viewfinder", value: AppTab.scan) { ScanHomeView() }
                Tab(tr("语法库"), systemImage: "books.vertical", value: AppTab.library) { LibraryView() }
                Tab(tr("收藏"), image: "Kinchaku", value: AppTab.favorites) { FavoritesView() }
                Tab(tr("搜索"), systemImage: "magnifyingglass", value: AppTab.search, role: .search) { SearchView() }
            }
        } else {
            TabView(selection: selection) {
                HomeView(openCamera: { tab = AppTab.scan })
                    .tabItem { Label(tr("首页"), systemImage: "house") }.tag(AppTab.home)
                ScanHomeView()
                    .tabItem { Label(tr("扫描"), systemImage: "text.viewfinder") }.tag(AppTab.scan)
                LibraryView()
                    .tabItem { Label(tr("语法库"), systemImage: "books.vertical") }.tag(AppTab.library)
                FavoritesView()
                    .tabItem { Label(tr("收藏"), image: "Kinchaku") }.tag(AppTab.favorites)
                SearchView()
                    .tabItem { Label(tr("搜索"), systemImage: "magnifyingglass") }.tag(AppTab.search)
            }
        }
    }

    private func openSample() {
        tab = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .openSamplePage, object: nil)
        }
    }
}
