import Foundation

final class GrammarLibrary: ObservableObject {
    static var shared = GrammarLibrary()

    let points: [GrammarPoint]
    private let byID: [String: GrammarPoint]
    private let searchIndex: [SearchEntry]
    let matcher: GrammarMatcher
    let aliases: [String: String]
    private let contrastsByID: [String: GrammarContrasts]

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
        let sorted = loaded.sorted { ($0.level, $0.reading ?? $0.title) < ($1.level, $1.reading ?? $1.title) }
        points = sorted
        searchIndex = sorted.map(GrammarLibrary.searchEntry(for:))
        byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        matcher = GrammarMatcher(points: loaded)
        aliases = GrammarLibrary.loadAliases(from: bundle)
        contrastsByID = GrammarLibrary.loadContrasts(language, from: bundle)
    }

    func contrasts(for id: String) -> GrammarContrasts? { contrastsByID[resolve(id)] }

    func resolve(_ id: String) -> String { byID[id] != nil ? id : (aliases[id] ?? id) }

    func point(id: String) -> GrammarPoint? { byID[resolve(id)] }

    func displayableIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map(resolve).filter { byID[$0] != nil && seen.insert($0).inserted }
    }

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
        points.filter { $0.levels.contains(level) }
    }

    func search(_ query: String) -> [GrammarPoint] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return points }
        if let level = GrammarLibrary.level(named: q) {
            let all = points(for: level)
            return all.filter { $0.level == level } + all.filter { $0.level != level }
        }
        let key = GrammarLibrary.fold(q)
        guard !key.isEmpty else { return [] }
        let hasKana = key.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        let expansions = GrammarLibrary.synonymExpansions(of: key)
        var scored: [(Int, Int)] = []
        for (i, entry) in searchIndex.enumerated() {
            var best = 0
            for form in entry.forms {
                if form == key {
                    best = max(best, 1000)
                } else if form.hasPrefix(key) {
                    best = max(best, 800 - min(form.count - key.count, 99))
                } else if form.contains(key) {
                    best = max(best, 600 - min(form.count - key.count, 99))
                } else if key.count >= 6, form.count >= 2, key.contains(form) {
                    best = max(best, 400 + min(form.count, 99))
                }
            }
            for alias in entry.aliases {
                if alias == key { best = max(best, 900) } else if alias.contains(key) { best = max(best, 150) }
            }
            if best == 0, !hasKana {
                if entry.gloss.contains(key) {
                    best = 320
                } else if expansions.contains(where: { entry.gloss.contains($0) }) {
                    best = 300
                } else if entry.body.contains(key) {
                    best = 120
                }
            }
            if best > 0 { scored.append((best, i)) }
        }
        if scored.contains(where: { $0.0 >= 200 }) { scored.removeAll { $0.0 < 200 } }
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }.map { points[$0.1] }
    }

    func searchInExamples(_ query: String, excluding: [GrammarPoint]) -> [GrammarPoint] {
        let key = GrammarLibrary.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard key.count >= 2 else { return [] }
        let skip = Set(excluding.map(\.id))
        return points.indices.filter { !skip.contains(points[$0].id) && searchIndex[$0].examples.contains(key) }.map { points[$0] }
    }

    static func level(named query: String) -> JLPTLevel? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return JLPTLevel.allCases.first { $0.rawValue.caseInsensitiveCompare(q) == .orderedSame }
    }

    static func fold(_ s: String) -> String {
        var t = s
        for mark in ["〜", "～", "~", " ", "　"] { t = t.replacingOccurrences(of: mark, with: "") }
        t = t.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        return t.applyingTransform(.hiraganaToKatakana, reverse: true) ?? t
    }

    static let synonymGroups: [[String]] = [
        ["不太", "不那么", "不怎么", "不大", "不很"],
        ["也许", "可能", "说不定", "或许", "大概"],
        ["必须", "一定要", "非…不可", "不…不行"],
        ["不得不", "只好", "只能", "不能不"],
        ["虽然", "尽管", "虽说", "固然"],
        ["即使", "就算", "哪怕", "即便", "纵然"],
        ["因为", "由于", "正因为"],
        ["为了", "以便", "为的是"],
        ["如果", "要是", "假如", "假设", "倘若"],
        ["只有", "仅仅", "只是", "光是"],
        ["应该", "应当", "理应", "理所当然"],
        ["好像", "似乎", "看起来", "仿佛", "像是"],
        ["听说", "据说", "传闻"],
        ["关于", "有关", "就…而言"],
        ["根据", "按照", "依照", "依据"],
        ["一…就", "刚…就", "马上"],
        ["甚至", "连…都", "连…也"],
        ["越来越", "日益", "逐渐"],
        ["想要", "希望", "愿望"],
        ["打算", "准备", "计划"],
        ["结果", "最终", "终于"],
        ["不管", "无论", "不论"],
    ]

    static func synonymExpansions(of key: String) -> [String] {
        var out: [String] = []
        for group in synonymGroups {
            for word in group where key.contains(word) {
                for other in group where other != word && !other.contains("…") {
                    out.append(key.replacingOccurrences(of: word, with: other))
                }
            }
        }
        return out
    }

    struct SearchEntry {
        let forms: [String]
        let aliases: [String]
        let gloss: String
        let body: String
        let examples: String
    }

    private static func searchEntry(for p: GrammarPoint) -> SearchEntry {
        var raw: [String] = [p.title, p.kanji ?? "", p.reading ?? ""]
        for t in raw where t.contains("・") || t.contains("／") || t.contains("/") {
            raw += t.split(whereSeparator: { "・／/".contains($0) }).map(String.init)
        }
        for t in raw where t.contains("（") {
            raw.append(t.replacingOccurrences(of: "（", with: "").replacingOccurrences(of: "）", with: ""))
            if let r = t.range(of: "（") { raw.append(String(t[..<r.lowerBound])) }
        }
        let forms = Array(Set(raw.map(fold).filter { !$0.isEmpty }))
        let gloss = fold(([p.meaning] + p.senses.map(\.label)).joined(separator: "\n"))
        let body = fold(p.senses.map(\.meaning).joined(separator: "\n"))
        let examples = fold(p.allExamples.flatMap { [$0.ja, $0.translation] }.joined(separator: "\n"))
        let aliases = Array(Set(p.aliases.map(fold).filter { !$0.isEmpty }))
        return SearchEntry(forms: forms, aliases: aliases, gloss: gloss, body: body, examples: examples)
    }

    private static func jsonURLs(in bundle: Bundle, prefix: String) -> [URL] {
        var urls: [URL] = []
        for sub in [nil, "Grammar", "Grammar/l10n", "l10n"] as [String?] {
            urls += bundle.urls(forResourcesWithExtension: "json", subdirectory: sub) ?? []
        }
        return Array(Set(urls.filter { $0.lastPathComponent.hasPrefix(prefix) }))
    }

    private static func loadContrasts(_ language: ContentLanguage, from bundle: Bundle) -> [String: GrammarContrasts] {
        func load(_ name: String) -> [GrammarContrasts] {
            var urls: [URL] = []
            for sub in [nil, "Grammar", "Grammar/contrasts", "contrasts"] as [String?] {
                if let u = bundle.url(forResource: name, withExtension: "json", subdirectory: sub) { urls.append(u) }
            }
            guard let url = urls.first else { return [] }
            do {
                return try JSONDecoder().decode(GrammarContrasts.File.self, from: Data(contentsOf: url)).points
            } catch {
                assertionFailure("无法解析 \(name).json: \(error)")
                return []
            }
        }
        var result: [String: GrammarContrasts] = [:]
        for c in load("contrasts") { result[c.id] = c }
        if language != .zhHans {
            for l in load("contrasts_\(language.rawValue)") { result[l.id]?.apply(l) }
        }
        return result
    }

    private static func loadAliases(from bundle: Bundle) -> [String: String] {
        guard let url = jsonURLs(in: bundle, prefix: "id_aliases").first,
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw
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
