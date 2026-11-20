import Foundation

/// 「相近语法」新版对比资料（Resources/Grammar/contrasts/contrasts.json，简体中文基础文件；
/// contrasts_<语言>.json 为翻译，结构一一对应，只含需要翻译的文字）。
/// 只有部分语法点有这份资料；没有的语法点仍显示旧版的 `GrammarPoint.similar`。
struct GrammarContrasts: Decodable {
    let id: String
    var groups: [Group]

    struct Group: Decodable {
        enum Kind: String, Decodable {
            /// 同一个词变来的
            case root
            /// 长得像的
            case look
            /// 意思差不多的
            case meaning
        }

        let kind: Kind
        /// 组名旁的一句说明（如「都来自『ところ（所）』」）
        var note: String
        var items: [Item]
    }

    struct Item: Decodable {
        /// 对比对象的语法点 id
        let id: String
        /// 显示用的标题（对比的是合并语法点中的某个用法时，如「〜ように（目的）」）；缺省用对方的标题
        var title: String?
        /// 一句话的差别（收起时也显示）
        var diff: String
        var current: Sentence
        var other: Sentence
        var wrong: Wrong?
        /// 「怎么分辨」讲解
        var explain: String

        enum CodingKeys: String, CodingKey {
            case id, title, diff, wrong, explain
            case current = "this"
            case other = "that"
        }
    }

    /// 对比例句。`ja` 的写法：用 | 分段；「漢字:かな」= 带注音；* 开头 = 语法本体；~ 开头 = 线索。
    struct Sentence: Decodable {
        var ja: String?
        var tag: String
        var tr: String

        /// 拆成可排版的片段（语法本体高亮，线索加虚线）
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

        /// 去掉标记后的整句（无障碍朗读用）
        var plain: String { segments.map(\.text).joined() }
    }

    struct Wrong: Decodable {
        var ja: String?
        var why: String
    }

    /// 用某种语言的翻译覆盖文字（结构不一致的部分保留简体中文）。
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
                groups[g].items[i].diff = li.diff
                groups[g].items[i].explain = li.explain
                groups[g].items[i].current.tag = li.current.tag
                groups[g].items[i].current.tr = li.current.tr
                groups[g].items[i].other.tag = li.other.tag
                groups[g].items[i].other.tr = li.other.tr
                if let why = li.wrong?.why { groups[g].items[i].wrong?.why = why }
            }
        }
    }

    struct File: Decodable {
        let points: [GrammarContrasts]
    }
}
