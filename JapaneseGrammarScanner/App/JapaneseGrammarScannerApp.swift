import SwiftUI

@main
struct JapaneseGrammarScannerApp: App {
    @StateObject private var languages = LanguageStore()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var entitlements = EntitlementStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var appearance = AppearanceStore.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appearance)
                .environmentObject(languages)
                .environmentObject(languages.library)
                // App 内选择了语言时，界面文字按该语言查找翻译（不依赖系统语言）
                .environment(\.locale, languages.language.locale ?? .autoupdatingCurrent)
                .environmentObject(favorites)
                .environmentObject(entitlements)
                .environmentObject(history)
        }
    }
}

extension Notification.Name {
    static let openSamplePage = Notification.Name("openSamplePage")
    static let showOnboarding = Notification.Name("showOnboarding")
    /// 再次点击当前标签：回到该标签的首页（object = 标签序号）
    static let popToRoot = Notification.Name("popToRoot")
    /// 打开搜索并聚焦输入框
    static let focusSearch = Notification.Name("focusSearch")
    /// 打开设置（从底部弹出的整页面板，不挂在任何标签下）
    static let showSettings = Notification.Name("showSettings")
    /// 打开反馈（object 可为上下文字符串，如语法点 id）
    static let showFeedback = Notification.Name("showFeedback")
}

/// 底部标签序号
enum AppTab {
    static let home = 0, scan = 1, library = 2, favorites = 3, search = 4
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
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showOnboarding = false

    @EnvironmentObject private var appearance: AppearanceStore
    @State private var showSettings = false
    @State private var feedbackContext: FeedbackContext?

    struct FeedbackContext: Identifiable {
        let id = UUID()
        let text: String?
        var kind: FeedbackView.Kind = .bug
    }

    /// 再次点击当前标签时回到该标签的首页（iOS 标准行为）。
    /// 「搜索」标签例外：任何时候点它都是要搜索，一律回到搜索页并激活搜索框。
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
            // 外观（主题色、背景色）变化时整体刷新配色
            .id(appearance.key)
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
                // 不弹付费页：引导最后一页已写明试用时长与到期后的价格，这里直接开始免费试用
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
        .onAppear {
            favorites.migrate(aliases: library.aliases)
            history.migrate(aliases: library.aliases)
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

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            // iOS 18+：搜索作为独立的搜索标签（iOS 26 中显示在标签栏右侧）
            TabView(selection: selection) {
                Tab("首页", systemImage: "house", value: AppTab.home) { HomeView(openCamera: { tab = AppTab.scan }) }
                // 相机只在用户切换到「扫描」时才启动
                Tab("扫描", systemImage: "text.viewfinder", value: AppTab.scan) { ScanHomeView() }
                Tab("语法库", systemImage: "books.vertical", value: AppTab.library) { LibraryView() }
                Tab("收藏", systemImage: "star", value: AppTab.favorites) { FavoritesView() }
                Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search, role: .search) { SearchView() }
            }
        } else {
            TabView(selection: selection) {
                HomeView(openCamera: { tab = AppTab.scan })
                    .tabItem { Label("首页", systemImage: "house") }.tag(AppTab.home)
                ScanHomeView()
                    .tabItem { Label("扫描", systemImage: "text.viewfinder") }.tag(AppTab.scan)
                LibraryView()
                    .tabItem { Label("语法库", systemImage: "books.vertical") }.tag(AppTab.library)
                FavoritesView()
                    .tabItem { Label("收藏", systemImage: "star") }.tag(AppTab.favorites)
                SearchView()
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(AppTab.search)
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
