import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @State private var query = DemoMode.screen == "library" ? (DemoMode.search ?? "") : ""
    @State private var levelFilter: JLPTLevel?
    @State private var path: [Route] = []
    @State private var scrolled: CGFloat = 0

    private var availableLevels: [JLPTLevel] {
        JLPTLevel.allCases.filter { !library.points(for: $0).isEmpty }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var levelPicker: some View {
        Picker(tr("等级"), selection: $levelFilter) {
            Text(localized: "全部").tag(JLPTLevel?.none)
            ForEach(availableLevels) { Text($0.rawValue).tag(JLPTLevel?.some($0)) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("library.levelFilter")
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
            .modifier(ScrollTracker(scrolled: $scrolled))
            .safeAreaInset(edge: .top, spacing: 0) {
                levelPicker
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                    .background {
                        Rectangle()
                            .fill(.regularMaterial)
                            .overlay(Theme.background.opacity(0.35))
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
                            }
                            .opacity(LibraryHeader.glassOpacity(scrolled: scrolled))
                            .ignoresSafeArea(edges: .top)
                    }
                    .offset(y: LibraryHeader.pullOffset(scrolled: scrolled))
            }
            .dismissesKeyboardOnTapAndScroll()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("搜索语法或意思"))
            .navigationTitle(tr("语法库"))
            .navigationBarTitleDisplayMode(.large)
            .withAppRoutes()
        }
        .environment(\.pushRoute, { path.append($0) })
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
            if note.object as? Int == AppTab.library { path = [] }
        }
    }

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
                Text(localized: "在例句中出现")
            }
        }
    }

    private func applyFilter(_ list: [GrammarPoint]) -> [GrammarPoint] {
        guard let levelFilter else { return list }
        return list.filter { $0.levels.contains(levelFilter) }
    }

    private var searchResults: [GrammarPoint] { applyFilter(library.search(query)) }

    private var exampleResults: [GrammarPoint] {
        let main = library.search(query)
        guard main.isEmpty else { return [] }
        return applyFilter(library.searchInExamples(query, excluding: main))
    }
}

enum LibraryHeader {
    static let glassFadeDistance: CGFloat = 12

    static func glassOpacity(scrolled: CGFloat) -> Double {
        Double(min(1, max(0, scrolled / glassFadeDistance)))
    }

    static func pullOffset(scrolled: CGFloat) -> CGFloat {
        max(0, -scrolled)
    }
}

private struct ScrollTracker: ViewModifier {
    @Binding var scrolled: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, y in
                let clamped = min(y, LibraryHeader.glassFadeDistance)
                if abs(clamped - scrolled) > 0.5 { scrolled = clamped }
            }
        } else {
            content.onAppear { scrolled = LibraryHeader.glassFadeDistance }
        }
    }
}
