import Foundation

/// 一个语法点。全部内容来自 App Bundle 里的静态 JSON（Resources/Grammar/grammar_*.json），不依赖任何网络或大模型。
struct GrammarPoint: Codable, Identifiable, Hashable {
    struct Example: Codable, Hashable {
        let ja: String
        let zh: String
    }

    struct Similar: Codable, Hashable {
        /// 若相近语法也收录在库中，则有 id，可跳转。
        let id: String?
        let title: String
        let explanation: String
    }

    let id: String
    let title: String
    let reading: String?
    let level: JLPTLevel
    let meaning: String
    let connection: String
    let usage: [String]
    let scenarios: [String]
    let etymology: String
    let examples: [Example]
    let similar: [Similar]
    let patterns: [String]
    let subsumes: [String]?

    static func == (lhs: GrammarPoint, rhs: GrammarPoint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
