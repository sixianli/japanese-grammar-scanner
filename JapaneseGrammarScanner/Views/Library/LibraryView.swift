import SwiftUI

/// 语法库：按 JLPT 等级浏览、搜索全部内置语法点。
struct LibraryView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @State private var query = DemoMode.screen == "library" ? (DemoMode.search ?? "") : ""
    @State private var levelFilter: JLPTLevel?
    @State private var path: [Route] = []

    private var availableLevels: [JLPTLevel] {
        JLPTLevel.allCases.filter { !library.points(for: $0).isEmpty }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("等级", selection: $levelFilter) {
                        Text("全部").tag(JLPTLevel?.none)
                        ForEach(availableLevels) { Text($0.rawValue).tag(JLPTLevel?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if isSearching {
                    searchSections
                } else {
                    browseSections
                }
            }
            .overlay {
                if isSearching, searchResults.isEmpty, exampleResults.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .themedList()
            .dismissesKeyboardOnTapAndScroll()
            .searchable(text: $query, prompt: "搜索语法或意思")
            .navigationTitle("语法库")
            .navigationBarTitleDisplayMode(.inline)
            .withAppRoutes()
        }
        .environment(\.pushRoute, { path.append($0) })
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
            if note.object as? Int == AppTab.library { path = [] }
        }
    }

    /// 浏览：选了等级时，列出该等级的全部语法（合并后的语法点只要有义项属于该等级就会出现）；
    /// 「全部」时每个语法点只出现一次，放在它最低的等级下。
    @ViewBuilder
    private var browseSections: some View {
        ForEach(availableLevels.filter { levelFilter == nil || $0 == levelFilter }) { level in
            let items = levelFilter == nil ? library.points.filter { $0.level == level } : library.points(for: level)
            Section {
                ForEach(items) { p in
                    NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p, shownLevel: level) }
                        .accessibilityIdentifier("library.row")
                        .listRowBackground(Theme.card)
                }
            } header: {
                Text(verbatim: "\(level.rawValue) (\(items.count))")
            }
        }
    }

    /// 搜索：按相关度排序；只在例句里出现的单独列在后面。
    @ViewBuilder
    private var searchSections: some View {
        let main = searchResults
        if !main.isEmpty {
            Section {
                ForEach(main) { p in
                    NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p, shownLevel: levelFilter) }
                        .accessibilityIdentifier("library.row")
                        .listRowBackground(Theme.card)
                }
            }
        }
        let inExamples = exampleResults
        if !inExamples.isEmpty {
            Section {
                ForEach(inExamples) { p in
                    NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p, shownLevel: levelFilter) }
                        .accessibilityIdentifier("library.row")
                        .listRowBackground(Theme.card)
                }
            } header: {
                Text("在例句中出现")
            }
        }
    }

    private func applyFilter(_ list: [GrammarPoint]) -> [GrammarPoint] {
        guard let levelFilter else { return list }
        return list.filter { $0.levels.contains(levelFilter) }
    }

    private var searchResults: [GrammarPoint] { applyFilter(library.search(query)) }

    /// 主结果为空时才列出「在例句中出现」，避免干扰。
    private var exampleResults: [GrammarPoint] {
        let main = library.search(query)
        guard main.isEmpty else { return [] }
        return applyFilter(library.searchInExamples(query, excluding: main))
    }
}
