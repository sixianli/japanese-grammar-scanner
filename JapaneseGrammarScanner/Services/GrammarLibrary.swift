import Foundation

/// 从 App Bundle 加载全部语法静态资源。
final class GrammarLibrary: ObservableObject {
    static let shared = GrammarLibrary()

    let points: [GrammarPoint]
    private let byID: [String: GrammarPoint]
    let matcher: GrammarMatcher

    let language: ContentLanguage

    init(bundle: Bundle = .main, language: ContentLanguage = .current) {
        self.language = language
        var loaded = GrammarLibrary.loadPoints(from: bundle)
        let freq = GrammarLibrary.loadFrequency(from: bundle)
        for i in loaded.indices { loaded[i].frequency = freq[loaded[i].id] }
        if language != .zhHans {
            let localizations = GrammarLibrary.loadLocalizations(language, from: bundle)
            for i in loaded.indices {
                if let l = localizations[loaded[i].id] { loaded[i].apply(l) }
            }
        }
        points = loaded.sorted { ($0.level, $0.reading ?? $0.title) < ($1.level, $1.reading ?? $1.title) }
        byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        matcher = GrammarMatcher(points: loaded)
    }

    func point(id: String) -> GrammarPoint? { byID[id] }

    /// 按标题（含汉字写法、别名）查找，用于相近语法缺少 id 时的兜底跳转。
    func point(matchingTitle title: String) -> GrammarPoint? {
        func norm(_ s: String) -> String {
            var t = s
            if let r = t.range(of: "（") ?? t.range(of: " (") { t = String(t[..<r.lowerBound]) }
            return t.replacingOccurrences(of: "〜", with: "").replacingOccurrences(of: "～", with: "").trimmingCharacters(in: .whitespaces)
        }
        let key = norm(title)
        guard !key.isEmpty else { return nil }
        return points.first { p in
            ([p.title, p.kanji ?? ""] + p.aliases).contains { norm($0) == key }
        }
    }

    func points(for level: JLPTLevel) -> [GrammarPoint] {
        points.filter { $0.level == level }
    }

    /// 语法库搜索：标题、读音、意思、例句都参与匹配。
    func search(_ query: String) -> [GrammarPoint] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return points }
        let normalizedQ = q.replacingOccurrences(of: "〜", with: "").replacingOccurrences(of: "~", with: "")
        return points.filter { p in
            var fields: [String] = [p.title, p.displayTitle, p.kanji ?? "", p.reading ?? "", p.meaning]
            fields.append(contentsOf: p.aliases)
            fields.append(contentsOf: p.senses.map(\.label))
            for example in p.allExamples {
                fields.append(example.ja)
                fields.append(example.translation)
            }
            return fields.contains { $0.localizedCaseInsensitiveContains(normalizedQ) }
                || p.level.rawValue.caseInsensitiveCompare(q) == .orderedSame
        }
    }

    /// 资源可能被平铺到 Bundle 根目录，也可能保留在子目录中，都兼容。
    private static func jsonURLs(in bundle: Bundle, prefix: String) -> [URL] {
        var urls: [URL] = []
        for sub in [nil, "Grammar", "Grammar/l10n", "l10n"] as [String?] {
            urls += bundle.urls(forResourcesWithExtension: "json", subdirectory: sub) ?? []
        }
        return Array(Set(urls.filter { $0.lastPathComponent.hasPrefix(prefix) }))
    }

    private static func loadFrequency(from bundle: Bundle) -> [String: ExamFrequency] {
        guard let url = jsonURLs(in: bundle, prefix: "frequency").first,
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw.compactMapValues(ExamFrequency.init(rawValue:))
    }

    private static func loadLocalizations(_ language: ContentLanguage, from bundle: Bundle) -> [String: GrammarLocalization] {
        var result: [String: GrammarLocalization] = [:]
        for url in jsonURLs(in: bundle, prefix: "l10n_\(language.rawValue)_") {
            do {
                let items = try JSONDecoder().decode([GrammarLocalization].self, from: Data(contentsOf: url))
                for item in items { result[item.id] = item }
            } catch {
                assertionFailure("无法解析 \(url.lastPathComponent): \(error)")
            }
        }
        return result
    }

    private static func loadPoints(from bundle: Bundle) -> [GrammarPoint] {
        let grammarURLs = jsonURLs(in: bundle, prefix: "grammar_")

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
