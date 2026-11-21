import SwiftUI

/// 收藏的语法点，可按「快遗忘了 / 最近收藏 / 最多查看」排序。
struct FavoritesView: View {
    enum SortOrder: String, CaseIterable, Identifiable {
        case forgetting, recent, mostViewed
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .forgetting: "快遗忘了"
            case .recent: "最近收藏"
            case .mostViewed: "最多查看"
            }
        }
        var icon: String {
            switch self {
            case .forgetting: "hourglass"
            case .recent: "clock"
            case .mostViewed: "eye"
            }
        }
    }

    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var history: HistoryStore
    @AppStorage("favorites.sort") private var sortRaw = SortOrder.recent.rawValue
    @State private var path: [Route] = []

    private var sort: SortOrder { SortOrder(rawValue: sortRaw) ?? .recent }

    /// 按当前排序方式排列的收藏 id
    private var sortedIDs: [String] {
        let ids = favorites.ids.filter { library.point(id: $0) != nil }
        switch sort {
        case .recent:
            return ids
        case .forgetting:
            // 保持率越低越靠前；没看过讲解的视为最需要看
            let now = Date()
            return ids.enumerated().sorted { a, b in
                let ra = history.retention(of: a.element, now: now) ?? -1
                let rb = history.retention(of: b.element, now: now) ?? -1
                return ra != rb ? ra < rb : a.offset < b.offset
            }.map(\.element)
        case .mostViewed:
            return ids.enumerated().sorted { a, b in
                let ca = history.viewCount(of: a.element), cb = history.viewCount(of: b.element)
                return ca != cb ? ca > cb : a.offset < b.offset
            }.map(\.element)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if favorites.ids.isEmpty {
                    ContentUnavailableView {
                        Label(tr("还没有收藏"), image: "Kinchaku")
                    } description: {
                        Text(localized: "在语法讲解页或列表中点一下樱花，就能收进这里。")
                    }
                } else {
                    let ids = sortedIDs
                    List {
                        ForEach(ids, id: \.self) { id in
                            if let p = library.point(id: id) {
                                NavigationLink(value: Route.grammar(id)) { GrammarRow(point: p) }
                                    .accessibilityIdentifier("favorites.row")
                                    .listRowBackground(Theme.card)
                            }
                        }
                        // 取消收藏：点星号，或向左轻扫（系统标准操作）。不再单独提供「编辑」按钮。
                        .onDelete { offsets in
                            for id in offsets.map({ ids[$0] }) { favorites.toggle(id) }
                        }
                    }
                    .themedList()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Picker(tr("排序"), selection: $sortRaw) {
                                    ForEach(SortOrder.allCases) { order in
                                        Label(order.title.localized, systemImage: order.icon).tag(order.rawValue)
                                    }
                                }
                            } label: {
                                Label(tr("排序"), systemImage: "arrow.up.arrow.down")
                            }
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(Text(localized: "收藏") + Text(verbatim: favorites.ids.isEmpty ? "" : " (\(favorites.ids.count))"))
            .navigationBarTitleDisplayMode(.inline)
            .withAppRoutes()
        }
        .environment(\.pushRoute, { path.append($0) })
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
            if note.object as? Int == AppTab.favorites { path = [] }
        }
    }
}
