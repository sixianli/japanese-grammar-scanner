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
        let builtRules = points.filter(\.scannable).map { point -> Rule in
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
    /// 把命中分组成高亮块：显示片段有重叠的命中合成一块（一块里有多个语法点时点击后让用户选择）。
    /// 跨度很长的语法（如「や……など」「は……が」）只用关键部分（开头、结尾的假名）参与判断和显示，
    /// 中间的文字不框，也不会把中间别的语法合并进来。
    static func clusters(from matches: [GrammarMatch], text: String = "") -> [HighlightCluster] {
        let ns = text as NSString
        let segments = matches.map { displaySegments(for: $0.range, in: ns) }

        // 并查集：任意两个命中的显示片段有重叠就归为一组
        var parent = Array(matches.indices)
        func find(_ i: Int) -> Int {
            var x = i
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        for i in matches.indices {
            for j in matches.indices where j > i {
                if segments[i].contains(where: { a in segments[j].contains { NSIntersectionRange(a, $0).length > 0 } }) {
                    parent[find(i)] = find(j)
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in matches.indices { groups[find(i), default: []].append(i) }

        let ordered = groups.values
            .map { $0.sorted { matches[$0].range.location < matches[$1].range.location } }
            .sorted { a, b in
                let la = a.flatMap { segments[$0] }.map(\.location).min() ?? 0
                let lb = b.flatMap { segments[$0] }.map(\.location).min() ?? 0
                return la < lb
            }
        return ordered.enumerated().map { index, members in
            var ids: [String] = []
            var texts: [String: String] = [:]
            for m in members {
                let id = matches[m].grammarID
                if !ids.contains(id) { ids.append(id) }
                if texts[id] == nil, ns.length > 0, NSMaxRange(matches[m].range) <= ns.length {
                    texts[id] = ns.substring(with: matches[m].range)
                }
            }
            let ranges = mergeOverlapping(members.flatMap { segments[$0] })
            let union = ranges.dropFirst().reduce(ranges[0]) { NSUnionRange($0, $1) }
            return HighlightCluster(id: index, range: union, grammarIDs: ids, ranges: ranges, matchedTexts: texts)
        }
    }

    /// 一个命中实际要框出来的片段。短的整段框；长的（超过 6 个字）只框开头和结尾的平假名部分。
    static func displaySegments(for range: NSRange, in text: NSString) -> [NSRange] {
        guard range.length > 6, text.length >= NSMaxRange(range) else { return [range] }
        // 语法的关键部分几乎都是平假名（や、など、は、が……），遇到汉字、片假名（名词）就停
        func isHiragana(_ c: unichar) -> Bool { (0x3041...0x3096).contains(c) || c == 0x30FC }
        var head = 0
        while head < min(3, range.length), isHiragana(text.character(at: range.location + head)) { head += 1 }
        var tail = 0
        while tail < min(4, range.length), isHiragana(text.character(at: NSMaxRange(range) - 1 - tail)) { tail += 1 }
        head = max(head, 1)
        tail = max(tail, 1)
        guard head + tail < range.length - 1 else { return [range] }
        return [NSRange(location: range.location, length: head),
                NSRange(location: NSMaxRange(range) - tail, length: tail)]
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
