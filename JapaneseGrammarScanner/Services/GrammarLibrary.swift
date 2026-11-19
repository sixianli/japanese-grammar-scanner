import Foundation

/// 从 App Bundle 加载全部语法静态资源。
final class GrammarLibrary: ObservableObject {
    /// 当前语言的语法库；在「设置 → 语言」切换后由 LanguageStore 替换
    static var shared = GrammarLibrary()

    let points: [GrammarPoint]
    private let byID: [String: GrammarPoint]
    /// 与 `points` 一一对应的预处理搜索数据。
    private let searchIndex: [SearchEntry]
    let matcher: GrammarMatcher
    /// 旧 id → 新 id（同形语法合并后，被合并条目的 id 指向合并后的语法点）。
    let aliases: [String: String]

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
    }

    /// 把可能已被合并的旧 id 换成现在的 id。
    func resolve(_ id: String) -> String { byID[id] != nil ? id : (aliases[id] ?? id) }

    func point(id: String) -> GrammarPoint? { byID[resolve(id)] }

    /// 识别结果中真正会显示出来的语法点 id：旧 id 换成新 id、去重、只保留语法库里有的。
    /// 「识别到 N 个语法点」等所有数量都用它计算，保证数字与列表条目数一致。
    func displayableIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map(resolve).filter { byID[$0] != nil && seen.insert($0).inserted }
    }

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

    /// 某个等级下的语法点：合并后的语法点只要有义项属于该等级就会出现。
    func points(for level: JLPTLevel) -> [GrammarPoint] {
        points.filter { $0.levels.contains(level) }
    }

    /// 语法库搜索（按相关度排序）：
    /// 1. 语法形式（标题、汉字写法、别名、读音）：完全一致 > 开头一致 > 包含；
    /// 2. 意思（概述、义项名、义项讲解）包含关键词；
    /// 3. 输入「N5」等时列出该等级。
    /// 例句不参与（例句里出现某个词不代表要找这个语法），见 `searchInExamples`。
    func search(_ query: String) -> [GrammarPoint] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return points }
        if let level = JLPTLevel.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(q) == .orderedSame }) {
            return points(for: level)
        }
        let key = GrammarLibrary.fold(q)
        guard !key.isEmpty else { return [] }
        let hasKana = key.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        let expansions = GrammarLibrary.synonymExpansions(of: key)
        var scored: [(Int, Int)] = []   // (分数, 下标)
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
                    // 输入了一整句：句子里包含这个语法形式
                    best = max(best, 400 + min(form.count, 99))
                }
            }
            // 别名（其他写法、常见搭配）：完全一致才算强命中，部分包含只作补充
            for alias in entry.aliases {
                if alias == key { best = max(best, 900) } else if alias.contains(key) { best = max(best, 150) }
            }
            // 输入含假名时是在找日语形式，不再按讲解文字匹配（讲解里引用的日语会带来无关结果）
            if best == 0, !hasKana {
                // 按意思搜索：先看释义（概述 + 义项名），再看义项讲解正文；近义说法一起匹配
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
        // 有更直接的命中（语法形式或释义）时，只在别名或讲解正文里顺带出现的结果不再列出
        if scored.contains(where: { $0.0 >= 200 }) { scored.removeAll { $0.0 < 200 } }
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }.map { points[$0.1] }
    }

    /// 只在例句里出现关键词的语法点（作为单独一组「在例句中出现」，排除已在主结果中的）。
    func searchInExamples(_ query: String, excluding: [GrammarPoint]) -> [GrammarPoint] {
        let key = GrammarLibrary.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard key.count >= 2 else { return [] }
        let skip = Set(excluding.map(\.id))
        return points.indices.filter { !skip.contains(points[$0].id) && searchIndex[$0].examples.contains(key) }.map { points[$0] }
    }

    /// 搜索用的规范化：去掉 〜/～/~ 和空白，忽略大小写与全半角，片假名视同平假名。
    static func fold(_ s: String) -> String {
        var t = s
        for mark in ["〜", "～", "~", " ", "　"] { t = t.replacingOccurrences(of: mark, with: "") }
        t = t.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        return t.applyingTransform(.hiraganaToKatakana, reverse: true) ?? t
    }

    /// 中文释义里常见的近义说法：搜「不那么」也能找到释义写作「不太」的语法。
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

    /// 把查询里出现的近义说法换成同组的其他说法。
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
        /// 语法形式：标题、汉字写法、读音（已规范化）
        let forms: [String]
        /// 别名（已规范化）
        let aliases: [String]
        /// 释义：概述 + 义项名（已规范化）
        let gloss: String
        /// 义项讲解正文（已规范化）
        let body: String
        /// 例句（日语与译文，已规范化）
        let examples: String
    }

    private static func searchEntry(for p: GrammarPoint) -> SearchEntry {
        var raw: [String] = [p.title, p.kanji ?? "", p.reading ?? ""]
        // 「〜を通じて・〜を通して」这类标题拆成单独的写法；括号里的可选部分也作为一种写法
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

    /// 资源可能被平铺到 Bundle 根目录，也可能保留在子目录中，都兼容。
    private static func jsonURLs(in bundle: Bundle, prefix: String) -> [URL] {
        var urls: [URL] = []
        for sub in [nil, "Grammar", "Grammar/l10n", "l10n"] as [String?] {
            urls += bundle.urls(forResourcesWithExtension: "json", subdirectory: sub) ?? []
        }
        return Array(Set(urls.filter { $0.lastPathComponent.hasPrefix(prefix) }))
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
