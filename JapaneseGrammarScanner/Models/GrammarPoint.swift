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
    var meaning: String
    var connection: String
    var usage: [String]
    var scenarios: [String]
    var etymology: String
    var examples: [Example]
    var similar: [Similar]
    let patterns: [String]
    let subsumes: [String]?

    static func == (lhs: GrammarPoint, rhs: GrammarPoint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// 用某种语言的讲解覆盖当前内容。结构不一致的字段保持原样。
    mutating func apply(_ l: GrammarLocalization) {
        if let t = l.title, !t.isEmpty { title = t }
        meaning = l.meaning
        connection = l.connection
        if l.usage.count == usage.count { usage = l.usage }
        if l.scenarios.count == scenarios.count { scenarios = l.scenarios }
        etymology = l.etymology
        if l.examples.count == examples.count {
            for i in examples.indices { examples[i].translation = l.examples[i] }
        }
        if l.similar.count == similar.count {
            for i in similar.indices {
                similar[i].title = l.similar[i].title
                similar[i].explanation = l.similar[i].explanation
            }
        }
    }
}

/// 某种语言的讲解（l10n/l10n_<语言>_<等级>.json 中的一项）。
struct GrammarLocalization: Decodable {
    struct SimilarText: Decodable {
        let title: String
        let explanation: String
    }

    let id: String
    let title: String?
    let meaning: String
    let connection: String
    let usage: [String]
    let scenarios: [String]
    let etymology: String
    let examples: [String]
    let similar: [SimilarText]
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
    case zhHans = "zh-Hans", zhHant = "zh-Hant", en, ko, es, vi

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
        return .en
    }
}
