import SwiftUI

/// 搜索：按相关度查找语法（语法形式 > 意思）；没有输入时显示最近查看。
struct SearchView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var history: HistoryStore
    @State private var query = DemoMode.screen == "search" ? (DemoMode.search ?? "") : ""
    @State private var isPresented = false
    @State private var path: [Route] = []

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trimmed.isEmpty {
                    let recent = history.recentGrammarIDs.prefix(8).compactMap { library.point(id: $0) }
                    if !recent.isEmpty {
                        Section("最近查看") {
                            ForEach(recent) { p in row(p) }
                        }
                    }
                } else {
                    let main = library.search(trimmed)
                    if !main.isEmpty {
                        Section { ForEach(main) { p in row(p) } }
                    } else {
                        let inExamples = library.searchInExamples(trimmed, excluding: [])
                        if !inExamples.isEmpty {
                            Section("在例句中出现") { ForEach(inExamples) { p in row(p) } }
                        }
                    }
                }
            }
            .themedList()
            .overlay {
                if !trimmed.isEmpty, library.search(trimmed).isEmpty, library.searchInExamples(trimmed, excluding: []).isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                } else if trimmed.isEmpty, history.recentGrammarIDs.isEmpty {
                    ContentUnavailableView("搜索语法", systemImage: "magnifyingglass",
                                           description: Text("输入语法、读音或意思，例如「ようになる」「にもかかわらず」「尽管」。"))
                }
            }
            .searchable(text: $query, isPresented: $isPresented, prompt: "搜索语法或意思")
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .withAppRoutes()
        }
        .environment(\.pushRoute, { path.append($0) })
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isPresented = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
            if note.object as? Int == AppTab.search { path = [] }
        }
    }

    private func row(_ p: GrammarPoint) -> some View {
        NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p) }
            .listRowBackground(Theme.card)
    }
}
