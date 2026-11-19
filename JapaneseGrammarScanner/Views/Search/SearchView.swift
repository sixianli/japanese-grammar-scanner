import SwiftUI

/// 搜索：按相关度查找语法（语法形式 > 意思）；没有输入时显示最近查看。
struct SearchView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var history: HistoryStore
    @State private var query = DemoMode.screen == "search" ? (DemoMode.search ?? "") : ""
    @State private var isPresented = false
    @FocusState private var fieldFocused: Bool
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
            // 搜索框始终显示在顶部，不会因为列表滚动而收起
            .searchable(text: $query, isPresented: $isPresented,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索语法或意思")
            .modifier(SearchFieldFocus(focused: $fieldFocused))
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .withAppRoutes()
        }
        .environment(\.pushRoute, { path.append($0) })
        // 切到「搜索」标签就是要搜索：直接激活搜索框、弹出键盘
        .onAppear { focusField(delay: 0.1) }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            focusField(delay: 0.35)
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
            if note.object as? Int == AppTab.search {
                path = []
                focusField(delay: 0.1)
            }
        }
    }

    private func focusField(delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isPresented = true
            fieldFocused = true
        }
    }

    private func row(_ p: GrammarPoint) -> some View {
        NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p) }
            .listRowBackground(Theme.card)
    }
}

/// iOS 18 起可以直接把光标放进搜索框（保留已输入的文字）；iOS 17 靠激活搜索（isPresented）弹出键盘。
private struct SearchFieldFocus: ViewModifier {
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.searchFocused(focused)
        } else {
            content
        }
    }
}
