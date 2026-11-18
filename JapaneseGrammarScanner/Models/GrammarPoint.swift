import Foundation

/// 一个语法点。全部内容来自 App Bundle 里的静态 JSON（Resources/Grammar/），不依赖任何网络或大模型。
/// 基础文件 grammar_*.json 包含日语例句、识别规则和简体中文讲解；
/// l10n/l10n_<语言>_*.json 提供其它语言的讲解，加载时按用户语言覆盖。
struct GrammarPoint: Codable, Identifiable, Hashable {
    struct Example: Codable, Hashable {
        let ja: String
        /// 例句译文（基础文件中为简体中文，键名为 "zh"）。
        var translation: String

        enum CodingKeys: String, CodingKey {
            case ja
            case translation = "zh"
        }
    }

    /// 一个义项（用法）：意思讲解 + 接续讲解 + 最常见例句（≤3）。
    struct Sense: Codable, Hashable {
        var label: String
        /// 该义项所属的 JLPT 等级（同形语法合并后，各义项等级可能不同；缺省 = 语法点等级）。
        var level: JLPTLevel?
        var meaning: String
        var connection: String
        var examples: [Example]
    }

    /// 一个具体使用场景。
    struct Scene: Codable, Hashable {
        var title: String
        var description: String
        var example: Example
    }

    struct Scenes: Codable, Hashable {
        var daily: [Scene]
        var work: [Scene]
    }

    struct Similar: Codable, Hashable {
        /// 若相近语法也收录在库中，则有 id，可跳转。
        let id: String?
        var title: String
        var explanation: String
    }

    let id: String
    var title: String
    let reading: String?
    let level: JLPTLevel
    /// 一句话概述。
    var meaning: String
    /// 总体接续。
    var connection: String
    var senses: [Sense]
    var notes: [String]
    var scenes: Scenes
    var etymology: String
    /// 组词逻辑：由哪些部分构成、为什么这样组合、如何体现在意思和用法上。
    var formation: String
    var similar: [Similar]
    /// 常见的汉字写法（如「〜挙げ句」）。考试/工作/日常中常以汉字书写时提供，用于标题显示与搜索。
    let kanji: String?
    /// 其它常见写法（用于搜索）。
    let aliases: [String]
    /// JLPT 出题频率（来自 Resources/Grammar/frequency.json，根据公开资料整理，仅供参考）
    var frequency: ExamFrequency?
    let patterns: [String]
    let subsumes: [String]?
    /// 是否在扫描时高亮。最基础的助词等（は・が・を…）设为 false：收录在语法库，但不在扫描结果中高亮。
    let scannable: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, reading, level, meaning, connection, senses, notes, scenes, etymology, formation, similar, patterns, subsumes, scannable, kanji, aliases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        reading = try c.decodeIfPresent(String.self, forKey: .reading)
        level = try c.decode(JLPTLevel.self, forKey: .level)
        meaning = try c.decode(String.self, forKey: .meaning)
        connection = try c.decode(String.self, forKey: .connection)
        senses = try c.decode([Sense].self, forKey: .senses)
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        scenes = try c.decode(Scenes.self, forKey: .scenes)
        etymology = try c.decode(String.self, forKey: .etymology)
        formation = try c.decodeIfPresent(String.self, forKey: .formation) ?? ""
        similar = try c.decode([Similar].self, forKey: .similar)
        kanji = try c.decodeIfPresent(String.self, forKey: .kanji)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        patterns = try c.decode([String].self, forKey: .patterns)
        subsumes = try c.decodeIfPresent([String].self, forKey: .subsumes)
        scannable = try c.decodeIfPresent(Bool.self, forKey: .scannable) ?? true
    }

    /// 标题中的日语形式（优先使用常见汉字写法）。
    var titleForm: String {
        if let k = kanji, !k.isEmpty { return k }
        return title
    }

    /// 列表与导航栏中显示的标题。
    var displayTitle: String { titleForm }

    /// 义项的等级（未标注时为语法点等级）。
    func level(of sense: Sense) -> JLPTLevel { sense.level ?? level }

    /// 本语法点涉及的全部等级（合并后的语法点可能横跨多个等级），从低到高。
    var levels: [JLPTLevel] { Array(Set([level] + senses.compactMap(\.level))).sorted() }

    /// 所有义项的例句。
    var allExamples: [Example] { senses.flatMap(\.examples) }

    static func == (lhs: GrammarPoint, rhs: GrammarPoint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// 用某种语言的讲解覆盖当前内容。结构不一致的部分保持原样（回退为简体中文）。
    mutating func apply(_ l: GrammarLocalization) {
        if let t = l.title, !t.isEmpty { title = t }
        meaning = l.meaning
        connection = l.connection
        etymology = l.etymology
        if let f = l.formation, !f.isEmpty { formation = f }
        if l.senses.count == senses.count {
            for i in senses.indices {
                let ls = l.senses[i]
                senses[i].label = ls.label
                senses[i].meaning = ls.meaning
                senses[i].connection = ls.connection
                if ls.examples.count == senses[i].examples.count {
                    for j in senses[i].examples.indices { senses[i].examples[j].translation = ls.examples[j] }
                }
            }
        }
        if let ln = l.notes, ln.count == notes.count { notes = ln }
        Self.apply(l.scenes.daily, to: &scenes.daily)
        Self.apply(l.scenes.work, to: &scenes.work)
        if l.similar.count == similar.count {
            for i in similar.indices {
                similar[i].title = l.similar[i].title
                similar[i].explanation = l.similar[i].explanation
            }
        }
    }

    private static func apply(_ texts: [GrammarLocalization.SceneText], to scenes: inout [Scene]) {
        guard texts.count == scenes.count else { return }
        for i in scenes.indices {
            scenes[i].title = texts[i].title
            scenes[i].description = texts[i].description
            scenes[i].example.translation = texts[i].example
        }
    }
}

/// 某种语言的讲解（l10n/l10n_<语言>_<等级>.json 中的一项）。日语例句不翻译，只给译文。
struct GrammarLocalization: Decodable {
    struct SenseText: Decodable {
        let label: String
        let meaning: String
        let connection: String
        let examples: [String]
    }

    struct SceneText: Decodable {
        let title: String
        let description: String
        let example: String
    }

    struct ScenesText: Decodable {
        let daily: [SceneText]
        let work: [SceneText]
    }

    struct SimilarText: Decodable {
        let title: String
        let explanation: String
    }

    let id: String
    let title: String?
    let meaning: String
    let connection: String
    let senses: [SenseText]
    let notes: [String]?
    let scenes: ScenesText
    let etymology: String
    let formation: String?
    let similar: [SimilarText]
}

/// JLPT 出题频率三档
enum ExamFrequency: String, Codable {
    case high, medium, low
}

enum JLPTLevel: String, Codable, CaseIterable, Comparable, Identifiable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"

    var id: String { rawValue }

    private var order: Int {
        switch self {
        case .n5: 0
        case .n4: 1
        case .n3: 2
        case .n2: 3
        case .n1: 4
        }
    }

    static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool { lhs.order < rhs.order }
}

/// 讲解内容使用的语言。
enum ContentLanguage: String, CaseIterable {
    case zhHans = "zh-Hans", zhHant = "zh-Hant", en, ko, es, vi, my

    /// 根据 App 当前生效的本地化语言（跟随系统，可在 设置 → App → 语言 中单独修改）决定。
    static var current: ContentLanguage {
        let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        return from(identifier: preferred)
    }

    static func from(identifier: String) -> ContentLanguage {
        let id = identifier.lowercased()
        if id.hasPrefix("zh") {
            return (id.contains("hant") || id.contains("-tw") || id.contains("-hk") || id.contains("-mo")) ? .zhHant : .zhHans
        }
        if id.hasPrefix("ko") { return .ko }
        if id.hasPrefix("es") { return .es }
        if id.hasPrefix("vi") { return .vi }
        if id.hasPrefix("my") { return .my }
        return .en
    }
}
