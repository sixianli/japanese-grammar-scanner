import SwiftUI

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
                        Section(tr("最近查看")) {
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
                            Section(tr("在例句中出现")) { ForEach(inExamples) { p in row(p) } }
                        }
                    }
                }
            }
            .themedList()
            .overlay {
                if !trimmed.isEmpty, library.search(trimmed).isEmpty, library.searchInExamples(trimmed, excluding: []).isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                } else if trimmed.isEmpty, history.recentGrammarIDs.isEmpty {
                    ContentUnavailableView(tr("搜索语法"), systemImage: "magnifyingglass",
                                           description: Text(localized: "输入语法、读音或意思，例如「ようになる」「にもかかわらず」「尽管」。"))
                }
            }
            .dismissesKeyboardOnTapAndScroll()
            .searchable(text: $query, isPresented: $isPresented,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: tr("搜索语法或意思"))
            .modifier(SearchFieldFocus(focused: $fieldFocused))
            .navigationTitle(tr("搜索"))
            .navigationBarTitleDisplayMode(.inline)
            .withAppRoutes()
        }
        .environment(\.pushRoute, { path.append($0) })
        .onAppear { focusField(delay: 0.1) }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            returnToSearch(delay: 0.35)
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
            if note.object as? Int == AppTab.search { returnToSearch(delay: 0.15) }
        }
    }

    private func returnToSearch(delay: Double) {
        let wasDeep = !path.isEmpty
        path = []
        focusField(delay: wasDeep ? max(delay, 0.5) : delay)
    }

    private func focusField(delay: Double) {
        fieldFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isPresented = true
            fieldFocused = true
        }
    }

    private func row(_ p: GrammarPoint) -> some View {
        NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p, shownLevel: GrammarLibrary.level(named: trimmed)) }
            .listRowBackground(Theme.card)
            .accessibilityIdentifier("search.result")
    }
}

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
