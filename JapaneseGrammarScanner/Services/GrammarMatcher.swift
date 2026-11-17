import Foundation

/// 基于规则（正则）的语法点识别器。规则全部来自静态 JSON 的 `patterns` 字段，完全离线。
final class GrammarMatcher {
    private struct Rule {
        let grammarID: String
        let regexes: [NSRegularExpression]
        let subsumes: Set<String>
    }

    private let rules: [Rule]
    private let subsumesByID: [String: Set<String>]

    init(points: [GrammarPoint]) {
        let builtRules = points.map { point -> Rule in
            let regexes = point.patterns.compactMap { pattern -> NSRegularExpression? in
                do {
                    return try NSRegularExpression(pattern: pattern)
                } catch {
                    assertionFailure("语法 \(point.id) 的正则无法编译: \(pattern)")
                    return nil
                }
            }
            return Rule(grammarID: point.id, regexes: regexes, subsumes: Set(point.subsumes ?? []))
        }
        rules = builtRules
        subsumesByID = Dictionary(builtRules.map { ($0.grammarID, $0.subsumes) }, uniquingKeysWith: { a, _ in a })
    }

    /// 在文本中查找所有语法点。
    func matches(in text: String) -> [GrammarMatch] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        guard whole.length > 0 else { return [] }

        // 1. 收集所有命中；同一语法点的重叠命中合并为一个。
        var raw: [GrammarMatch] = []
        for rule in rules {
            var ranges: [NSRange] = []
            for regex in rule.regexes {
                regex.enumerateMatches(in: text, range: whole) { result, _, _ in
                    guard let r = result?.range, r.location != NSNotFound, r.length > 0 else { return }
                    ranges.append(r)
                }
            }
            raw += Self.mergeOverlapping(ranges).map { GrammarMatch(grammarID: rule.grammarID, range: $0) }
        }

        // 2. 抑制被“包含”的语法点（例如 なければならない 中的 〜ば）。
        let filtered = raw.filter { candidate in
            !raw.contains { other in
                other.grammarID != candidate.grammarID
                    && (subsumesByID[other.grammarID]?.contains(candidate.grammarID) ?? false)
                    && NSIntersectionRange(other.range, candidate.range).length > 0
            }
        }

        return filtered.sorted {
            $0.range.location != $1.range.location
                ? $0.range.location < $1.range.location
                : $0.range.length > $1.range.length
        }
    }

    /// 把重叠的命中合并成可点击的高亮块。
    static func clusters(from matches: [GrammarMatch]) -> [HighlightCluster] {
        let sorted = matches.sorted { $0.range.location < $1.range.location }
        var clusters: [HighlightCluster] = []
        var currentRange: NSRange?
        var currentIDs: [String] = []

        func flush() {
            if let r = currentRange {
                clusters.append(HighlightCluster(id: clusters.count, range: r, grammarIDs: currentIDs))
            }
        }

        for m in sorted {
            if let r = currentRange, NSIntersectionRange(r, m.range).length > 0 {
                currentRange = NSUnionRange(r, m.range)
                if !currentIDs.contains(m.grammarID) { currentIDs.append(m.grammarID) }
            } else {
                flush()
                currentRange = m.range
                currentIDs = [m.grammarID]
            }
        }
        flush()
        return clusters
    }

    private static func mergeOverlapping(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for r in sorted {
            if let last = result.last, NSIntersectionRange(last, r).length > 0 {
                result[result.count - 1] = NSUnionRange(last, r)
            } else {
                result.append(r)
            }
        }
        return result
    }
}
