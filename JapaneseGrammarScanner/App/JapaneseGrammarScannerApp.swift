import SwiftUI

@main
struct JapaneseGrammarScannerApp: App {
    @StateObject private var library = GrammarLibrary.shared
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var entitlements = EntitlementStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(library)
                .environmentObject(favorites)
                .environmentObject(entitlements)
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
        case "library": 1
        case "favorites": 2
        default: 0
        }
    }()
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @AppStorage("didShowWelcomePaywall") private var didShowWelcomePaywall = false
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showWelcomePaywall = false
    @State private var showOnboarding = false
    @State private var openSampleAfterPaywall = false

    var body: some View {
        TabView(selection: $tab) {
            ScanHomeView()
                .tabItem { Label("扫描", systemImage: "text.viewfinder") }
                .tag(0)
            LibraryView()
                .tabItem { Label("语法库", systemImage: "books.vertical") }
                .tag(1)
            FavoritesView()
                .tabItem { Label("收藏", systemImage: "star") }
                .tag(2)
        }
        .sheet(isPresented: $showWelcomePaywall, onDismiss: {
            if openSampleAfterPaywall {
                openSampleAfterPaywall = false
                openSample()
            }
        }) { PaywallView() }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { wantsSample in
                didCompleteOnboarding = true
                showOnboarding = false
                // 引导结束后介绍一次 7 天免费试用；若用户想先看示例，关闭付费页后再打开示例书页
                if entitlements.access == .notStarted, !didShowWelcomePaywall {
                    didShowWelcomePaywall = true
                    openSampleAfterPaywall = wantsSample
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showWelcomePaywall = true }
                } else if wantsSample {
                    openSample()
                }
            }
        }
        .onChange(of: entitlements.isLoaded) { _, loaded in
            // 老用户（已看过引导）首次升级到含试用的版本时，介绍一次免费试用
            if loaded, didCompleteOnboarding, entitlements.access == .notStarted, !didShowWelcomePaywall, DemoMode.screen == nil {
                didShowWelcomePaywall = true
                showWelcomePaywall = true
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
        tab = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .openSamplePage, object: nil)
        }
    }
}
