import SwiftUI

/// 收藏的语法点。
struct FavoritesView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore
    /// 自己管理编辑状态：系统 EditButton 在 iOS 不支持的界面语言（如缅甸语）下只会显示英文。
    @State private var editMode: EditMode = .inactive

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
                    .environment(\.editMode, $editMode)
                    .toolbar {
                        Button(editMode.isEditing ? "完成" : "编辑") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
            }
            .navigationTitle(Text("收藏") + Text(verbatim: favorites.ids.isEmpty ? "" : " (\(favorites.ids.count))"))
            .withAppRoutes()
        }
    }
}
