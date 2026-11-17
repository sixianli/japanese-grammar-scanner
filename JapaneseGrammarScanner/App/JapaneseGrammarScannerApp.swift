import SwiftUI

@main
struct JapaneseGrammarScannerApp: App {
    @StateObject private var library = GrammarLibrary.shared
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(library)
                .environmentObject(favorites)
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
        .onAppear {
            if DemoMode.screen == "favorites", favorites.ids.isEmpty {
                for id in ["te-shimau", "you-ni-naru", "ni-mo-kakawarazu", "okage-de", "rashii"].reversed() {
                    favorites.toggle(id)
                }
            }
        }
    }
}
