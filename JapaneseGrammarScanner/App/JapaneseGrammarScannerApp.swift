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
    @State private var showWelcomePaywall = false

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
        .sheet(isPresented: $showWelcomePaywall) { PaywallView() }
        .onChange(of: entitlements.isLoaded) { _, loaded in
            // 首次启动且从未开始试用时，介绍一次免费试用（之后不再自动弹出）
            if loaded, entitlements.access == .notStarted, !didShowWelcomePaywall, DemoMode.screen == nil {
                didShowWelcomePaywall = true
                showWelcomePaywall = true
            }
        }
        .onAppear {
            if DemoMode.screen == "favorites", favorites.ids.isEmpty {
                for id in ["te-shimau", "you-ni-naru", "ni-mo-kakawarazu", "okage-de", "rashii"].reversed() {
                    favorites.toggle(id)
                }
            }
        }
    }
}
