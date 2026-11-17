import SwiftUI

/// 收藏的语法点。
struct FavoritesView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        NavigationStack {
            Group {
                if favorites.ids.isEmpty {
                    ContentUnavailableView(
                        "还没有收藏",
                        systemImage: "star",
                        description: Text("在语法讲解页或列表中点击 ☆ 即可收藏。")
                    )
                } else {
                    List {
                        ForEach(favorites.ids, id: \.self) { id in
                            if let p = library.point(id: id) {
                                NavigationLink(value: Route.grammar(id)) { GrammarRow(point: p) }
                            }
                        }
                        .onDelete { favorites.remove(atOffsets: $0) }
                        .onMove { favorites.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .toolbar { EditButton() }
                }
            }
            .navigationTitle("收藏（\(favorites.ids.count)）")
            .withAppRoutes()
        }
    }
}
