import Foundation

/// 从 App Bundle 加载全部语法静态资源。
final class GrammarLibrary: ObservableObject {
    static let shared = GrammarLibrary()

    let points: [GrammarPoint]
    private let byID: [String: GrammarPoint]
    let matcher: GrammarMatcher

    init(bundle: Bundle = .main) {
        let loaded = GrammarLibrary.loadPoints(from: bundle)
        points = loaded.sorted { ($0.level, $0.reading ?? $0.title) < ($1.level, $1.reading ?? $1.title) }
        byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        matcher = GrammarMatcher(points: loaded)
    }

    func point(id: String) -> GrammarPoint? { byID[id] }

    func points(for level: JLPTLevel) -> [GrammarPoint] {
        points.filter { $0.level == level }
    }

    /// 语法库搜索：标题、读音、意思、例句都参与匹配。
    func search(_ query: String) -> [GrammarPoint] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return points }
        let normalizedQ = q.replacingOccurrences(of: "〜", with: "").replacingOccurrences(of: "~", with: "")
        return points.filter { p in
            let fields = [p.title, p.reading ?? "", p.meaning] + p.examples.map(\.ja)
            return fields.contains { $0.localizedCaseInsensitiveContains(normalizedQ) }
                || p.level.rawValue.caseInsensitiveCompare(q) == .orderedSame
        }
    }

    private static func loadPoints(from bundle: Bundle) -> [GrammarPoint] {
        // 资源可能被平铺到 Bundle 根目录，也可能保留在 Grammar 子目录中，两种都兼容。
        var urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        urls += bundle.urls(forResourcesWithExtension: "json", subdirectory: "Grammar") ?? []
        let grammarURLs = Set(urls.filter { $0.lastPathComponent.hasPrefix("grammar_") })

        let decoder = JSONDecoder()
        var result: [GrammarPoint] = []
        for url in grammarURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try Data(contentsOf: url)
                result += try decoder.decode([GrammarPoint].self, from: data)
            } catch {
                assertionFailure("无法解析 \(url.lastPathComponent): \(error)")
            }
        }
        return result
    }
}
