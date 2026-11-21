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
                // 端对端测试用：显示各种查找翻译的方式实际得到的结果，排查 App 内切换语言
                .overlay(alignment: .bottomLeading) {
                    if DemoMode.e2e { LanguageDiagnostics(code: languages.language.rawValue) }
                }
        }
    }
}

/// 端对端测试用的语言诊断信息（不可见，只给 UI 测试读取）
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
    @Environment(\.scenePhase) private var scenePhase
    /// 启动时的一次性处理（迁移、演示/测试数据、引导）只做一次；切换语言重建界面时不重复
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
            // 外观（主题色、背景色）或语言变化时，标签页内容整体刷新（导航标题、标签栏等系统控件也随之换语言）。
            // 只刷新标签页，不刷新 RootTabView 本身：设置面板保持打开、停在原来的页面，当前标签也不变
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
        // 匿名使用统计：进入前台记一次使用，进入后台时上报
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

    /// 端到端测试（UI 测试启动参数 -e2e）：清空本地数据，放入固定的扫描记录、浏览记录，跳过引导。
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
            // iOS 18+：搜索作为独立的搜索标签（iOS 26 中显示在标签栏右侧）
            TabView(selection: selection) {
                Tab(tr("首页"), systemImage: "house", value: AppTab.home) { HomeView(openCamera: { tab = AppTab.scan }) }
                // 相机只在用户切换到「扫描」时才启动
                Tab(tr("扫描"), systemImage: "text.viewfinder", value: AppTab.scan) { ScanHomeView() }
                Tab(tr("语法库"), systemImage: "books.vertical", value: AppTab.library) { LibraryView() }
                Tab(tr("收藏"), systemImage: "star", value: AppTab.favorites) { FavoritesView() }
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
                    .tabItem { Label(tr("收藏"), systemImage: "star") }.tag(AppTab.favorites)
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
