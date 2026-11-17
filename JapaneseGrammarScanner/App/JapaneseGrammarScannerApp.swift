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
    var body: some View {
        TabView {
            ScanHomeView()
                .tabItem { Label("扫描", systemImage: "text.viewfinder") }
            LibraryView()
                .tabItem { Label("语法库", systemImage: "books.vertical") }
            FavoritesView()
                .tabItem { Label("收藏", systemImage: "star") }
        }
    }
}
