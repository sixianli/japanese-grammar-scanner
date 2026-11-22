import Foundation

struct GrammarContrasts: Decodable {
    let id: String
    var groups: [Group]

    struct Group: Decodable {
        enum Kind: String, Decodable {
            case root
            case look
            case meaning
        }

        let kind: Kind
        var note: String
        let sense: Int?
        var items: [Item]
    }

    var splitsMeaningBySense: Bool {
        groups.filter { $0.kind == .meaning }.count > 1
    }

    struct Item: Decodable {
        let id: String
        var title: String?
        var thisTitle: String?
        var diff: String
        var current: [Sentence]
        var other: [Sentence]
        var wrong: Wrong?
        var explain: String

        enum CodingKeys: String, CodingKey {
            case id, title, thisTitle, diff, wrong, explain
            case current = "this"
            case other = "that"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            thisTitle = try c.decodeIfPresent(String.self, forKey: .thisTitle)
            diff = try c.decode(String.self, forKey: .diff)
            explain = try c.decode(String.self, forKey: .explain)
            wrong = try c.decodeIfPresent(Wrong.self, forKey: .wrong)
            current = try Self.sentences(c, .current)
            other = try Self.sentences(c, .other)
        }

        var cues: [String] {
            var out: [String] = []
            for s in current + other {
                var cur = ""
                for seg in s.segments {
                    if seg.cue { cur += seg.text } else if !cur.isEmpty { out.append(cur); cur = "" }
                }
                if !cur.isEmpty { out.append(cur) }
            }
            var seen = Set<String>()
            return out.filter { seen.insert($0).inserted }
        }

        private static func sentences(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [Sentence] {
            if let list = try? c.decode([Sentence].self, forKey: key) { return list }
            return [try c.decode(Sentence.self, forKey: key)]
        }
    }

    struct Sentence: Decodable {
        var ja: String?
        var tag: String
        var tr: String

        var segments: [RubySegment] {
            guard let ja else { return [] }
            return ja.split(separator: "|", omittingEmptySubsequences: true).map { raw in
                var s = Substring(raw)
                var highlighted = false, cue = false
                if s.first == "*" { highlighted = true; s = s.dropFirst() } else if s.first == "~" { cue = true; s = s.dropFirst() }
                if let colon = s.firstIndex(of: ":") {
                    return RubySegment(text: String(s[..<colon]), ruby: String(s[s.index(after: colon)...]),
                                       highlighted: highlighted, cue: cue)
                }
                return RubySegment(text: String(s), ruby: nil, highlighted: highlighted, cue: cue)
            }
        }

        var plain: String { segments.map(\.text).joined() }
    }

    struct Wrong: Decodable {
        var ja: String?
        var why: String
    }

    mutating func apply(_ l: GrammarContrasts) {
        guard l.groups.count == groups.count else { return }
        for g in groups.indices {
            let lg = l.groups[g]
            guard lg.kind == groups[g].kind, lg.items.count == groups[g].items.count else { continue }
            groups[g].note = lg.note
            for i in groups[g].items.indices {
                let li = lg.items[i]
                guard li.id == groups[g].items[i].id else { continue }
                if let t = li.title { groups[g].items[i].title = t }
                if let t = li.thisTitle { groups[g].items[i].thisTitle = t }
                groups[g].items[i].diff = li.diff
                groups[g].items[i].explain = li.explain
                Self.apply(li.current, to: &groups[g].items[i].current)
                Self.apply(li.other, to: &groups[g].items[i].other)
                if let why = li.wrong?.why { groups[g].items[i].wrong?.why = why }
            }
        }
    }

    private static func apply(_ l: [Sentence], to s: inout [Sentence]) {
        guard l.count == s.count else { return }
        for n in s.indices {
            s[n].tag = l[n].tag
            s[n].tr = l[n].tr
        }
    }

    struct File: Decodable {
        let points: [GrammarContrasts]
    }
}
