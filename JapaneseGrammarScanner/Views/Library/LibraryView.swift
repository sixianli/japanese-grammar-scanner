import SwiftUI

/// 语法库：按 JLPT 等级浏览、搜索全部内置语法点。
struct LibraryView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @State private var query = ""
    @State private var levelFilter: JLPTLevel?

    private var availableLevels: [JLPTLevel] {
        JLPTLevel.allCases.filter { level in library.points.contains { $0.level == level } }
    }

    var body: some View {
        NavigationStack {
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
                ForEach(availableLevels.filter { levelFilter == nil || $0 == levelFilter }) { level in
                    let items = filtered.filter { $0.level == level }
                    if !items.isEmpty {
                        Section("\(level.rawValue)（\(items.count)）") {
                            ForEach(items) { p in
                                NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p) }
                            }
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: "搜索语法、意思或例句")
            .navigationTitle("语法库")
            .withAppRoutes()
        }
    }

    private var filtered: [GrammarPoint] {
        library.search(query)
    }
}
