import SwiftUI

@main
struct JapaneseGrammarScannerApp: App {
    @StateObject private var library = GrammarLibrary.shared
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var entitlements = EntitlementStore()
    @StateObject private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(library)
                .environmentObject(favorites)
                .environmentObject(entitlements)
                .environmentObject(history)
        }
    }
}

extension Notification.Name {
    static let openSamplePage = Notification.Name("openSamplePage")
    static let showOnboarding = Notification.Name("showOnboarding")
}

struct RootTabView: View {
    @State private var tab: Int = {
        switch DemoMode.screen {
        case "home": 0
        case "scan", "result", "detail": 1
        case "library": 2
        case "favorites": 3
        default: 0
        }
    }()
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            HomeView(openCamera: { tab = 1 })
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)
            // 相机只在用户切换到「扫描」时才启动
            ScanHomeView()
                .tabItem { Label("扫描", systemImage: "text.viewfinder") }
                .tag(1)
            LibraryView()
                .tabItem { Label("语法库", systemImage: "books.vertical") }
                .tag(2)
            FavoritesView()
                .tabItem { Label("收藏", systemImage: "star") }
                .tag(3)
        }
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
            if !didCompleteOnboarding, DemoMode.screen == nil || DemoMode.screen == "onboarding" {
                showOnboarding = true
            }
            if DemoMode.screen == "favorites", favorites.ids.isEmpty {
                for id in ["te-shimau", "you-ni-naru", "ni-mo-kakawarazu", "okage-de", "rashii"].reversed() {
                    favorites.toggle(id)
                }
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
