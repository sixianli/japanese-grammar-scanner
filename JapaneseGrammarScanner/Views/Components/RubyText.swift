import SwiftUI

/// 注音文本的一个片段。
struct RubySegment: Hashable {
    var text: String
    var ruby: String?
    var highlighted = false
    /// 线索：下方画虚线（「相近语法」对比例句里，帮助分辨的那几个词）
    var cue = false
}

/// 文本中的一个最小排版单元（不可再拆分换行）。
private struct Atom: Hashable {
    var text: String
    var ruby: String?
    var highlighted = false
    var cue = false
    var isLineBreak = false
}

/// 把带注音的片段拆成可换行的单元：
/// - 有注音的汉字词整体作为一个单元；
/// - 日文/中文逐字拆分（可在任意字间换行）；
/// - 拉丁字母等按单词（含后面的空格）拆分；
/// - 句读点、右括号等不能出现在行首，并入前一个单元；左括号并入后一个单元（避头尾）。
private enum AtomBuilder {
    static let noLineStart: Set<Character> = ["、", "。", "，", "．", "」", "』", "）", ")", "！", "？", "!", "?", "：", "；", ":", ";", ",", ".", "…", "ー", "ゃ", "ゅ", "ょ", "っ", "ャ", "ュ", "ョ", "ッ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "〜", "”", "’"]
    static let noLineEnd: Set<Character> = ["「", "『", "（", "(", "“", "‘"]

    static func isCJK(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first?.value else { return false }
        // 日文假名、CJK 汉字、全角符号可在任意字间换行；韩文按空格分词，不算在内
        return (0x3000...0x30FF).contains(s) || (0x3400...0x9FFF).contains(s) || (0xF900...0xFAFF).contains(s)
            || (0xFF00...0xFFEF).contains(s)
    }

    static func atoms(from segments: [RubySegment]) -> [Atom] {
        var out: [Atom] = []
        for seg in segments {
            if let ruby = seg.ruby {
                out.append(Atom(text: seg.text, ruby: ruby, highlighted: seg.highlighted, cue: seg.cue))
                continue
            }
            var word = ""
            func flushWord() {
                if !word.isEmpty {
                    out.append(Atom(text: word, ruby: nil, highlighted: seg.highlighted, cue: seg.cue))
                    word = ""
                }
            }
            for ch in seg.text {
                if ch == "\n" {
                    flushWord()
                    out.append(Atom(text: "", isLineBreak: true))
                } else if isCJK(ch) || noLineStart.contains(ch) || noLineEnd.contains(ch) {
                    flushWord()
                    out.append(Atom(text: String(ch), ruby: nil, highlighted: seg.highlighted, cue: seg.cue))
                } else if ch == " " {
                    word.append(ch)
                    flushWord()
                } else {
                    word.append(ch)
                }
            }
            flushWord()
        }
        return out
    }

    /// 避头尾：把单元合并成不可拆分的组。
    static func groups(_ atoms: [Atom]) -> [[Atom]] {
        var groups: [[Atom]] = []
        var pendingOpen: [Atom] = []
        for atom in atoms {
            if atom.isLineBreak {
                if !pendingOpen.isEmpty { groups.append(pendingOpen); pendingOpen = [] }
                groups.append([atom])
                continue
            }
            if atom.ruby == nil, let first = atom.text.first, atom.text.count == 1, noLineEnd.contains(first) {
                pendingOpen.append(atom)
                continue
            }
            if atom.ruby == nil, atom.text.count == 1, let first = atom.text.first, noLineStart.contains(first),
               let last = groups.indices.last, !(groups[last].first?.isLineBreak ?? false), pendingOpen.isEmpty {
                groups[last].append(atom)
                continue
            }
            groups.append(pendingOpen + [atom])
            pendingOpen = []
        }
        if !pendingOpen.isEmpty { groups.append(pendingOpen) }
        return groups
    }
}

/// 带假名注音、可高亮的富文本。没有任何注音时退化为普通 Text（原生排版，支持所有语言换行）。
struct RubyText: View {
    struct Style {
        var font: Font = .body
        /// 假名字号（pt）
        var rubySize: CGFloat = 8
        var color: Color = .primary
        var highlightColor: Color = .accentColor
        var lineSpacing: CGFloat = 6
        var weight: Font.Weight = .regular
        var alignment: TextAlignment = .leading
    }

    private static let quoteRegex = try! NSRegularExpression(pattern: "「([^」]+)」|『([^』]+)』")

    private let plain: String
    private let segments: [RubySegment]
    /// 排版分组在初始化时算好，重绘时不再重复计算
    private let groups: [[Atom]]
    private let hasRuby: Bool
    private var style: Style

    /// - Parameters:
    ///   - japanese: 整段日语（例句），整体查注音表。
    ///   - highlights: 需要高亮的 UTF-16 范围（例如语法本体）。
    init(japanese: String, highlights: [NSRange] = [], style: Style = Style()) {
        plain = japanese
        self.style = style
        let segs = FuriganaStore.shared.segments(for: japanese)
        segments = RubyText.applyHighlights(segs.map { RubySegment(text: $0.base, ruby: $0.ruby) }, highlights: highlights)
        hasRuby = segs.contains { $0.ruby != nil }
        groups = AtomBuilder.groups(AtomBuilder.atoms(from: segments))
    }

    /// 已经拆好的片段（自带注音、高亮、线索），例如「相近语法」的对比例句。
    init(segments: [RubySegment], style: Style = Style()) {
        plain = segments.map(\.text).joined()
        self.style = style
        self.segments = segments
        hasRuby = segments.contains { $0.ruby != nil }
        groups = AtomBuilder.groups(AtomBuilder.atoms(from: segments))
    }

    /// 讲解文字（任意语言），其中「」『』里的日语会自动注音。
    init(explanation: String, style: Style = Style()) {
        plain = explanation
        self.style = style
        var segs: [RubySegment] = []
        let ns = explanation as NSString
        var cursor = 0
        for m in RubyText.quoteRegex.matches(in: explanation, range: NSRange(location: 0, length: ns.length)) {
            let innerRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            if innerRange.location > cursor {
                segs.append(RubySegment(text: ns.substring(with: NSRange(location: cursor, length: innerRange.location - cursor))))
            }
            let inner = ns.substring(with: innerRange)
            segs += FuriganaStore.shared.segments(for: inner).map { RubySegment(text: $0.base, ruby: $0.ruby) }
            cursor = NSMaxRange(innerRange)
        }
        if cursor < ns.length { segs.append(RubySegment(text: ns.substring(from: cursor))) }
        segments = segs
        hasRuby = segs.contains { $0.ruby != nil }
        groups = AtomBuilder.groups(AtomBuilder.atoms(from: segs))
    }

    var body: some View {
        if hasRuby || segments.contains(where: { $0.highlighted || $0.cue }) {
            flow
        } else {
            Text(plain)
                .font(style.font)
                .fontWeight(style.weight)
                .foregroundStyle(style.color)
                .lineSpacing(style.lineSpacing)
                .multilineTextAlignment(style.alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var flow: some View {
        // 注音行本身已经占了一定高度，这里把行距收紧，避免段落显得松散
        return FlowLayout(lineSpacing: max(2, style.lineSpacing - 4), centered: style.alignment == .center) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if group.first?.isLineBreak == true {
                    Color.clear.frame(width: 0, height: 0).layoutValue(key: LineBreakKey.self, value: true)
                } else {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.offset) { _, atom in
                            atomView(atom)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plain)
    }

    /// 一个排版单元：正文 + 正上方居中的假名。
    /// 每个单元顶部都预留一行假名的高度（无论有没有注音），假名画在这块预留区域里，
    /// 永远不会和本行或上一行的汉字重叠；假名不改变正文宽度，过长时自动缩小。
    private func atomView(_ atom: Atom) -> some View {
        let rubySize = UIFontMetrics(forTextStyle: .body).scaledValue(for: style.rubySize)
        let rubyLine = ceil(rubySize * 1.3)
        return Text(atom.text)
            .font(style.font)
            .fontWeight(atom.highlighted ? .semibold : style.weight)
            .foregroundStyle(atom.highlighted ? style.highlightColor : style.color)
            .lineLimit(1)
            .fixedSize()
            .background(atom.highlighted ? style.highlightColor.opacity(0.14) : Color.clear)
            .overlay(alignment: .bottom) {
                if atom.cue {
                    // 线索：正文下方一条虚线
                    DashedLine()
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2.5]))
                        .frame(height: 1.2)
                        .offset(y: 2)
                }
            }
            .padding(.top, rubyLine)
            .overlay(alignment: .top) {
                if let ruby = atom.ruby {
                    Text(ruby)
                        .font(.system(size: rubySize))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, -4)
                        .frame(height: rubyLine, alignment: .bottom)
                }
            }
    }

    /// 把高亮范围（UTF-16）映射到片段上；必要时拆分无注音片段，使高亮边界精确。
    private static func applyHighlights(_ segs: [RubySegment], highlights: [NSRange]) -> [RubySegment] {
        guard !highlights.isEmpty else { return segs }
        var out: [RubySegment] = []
        var offset = 0
        for seg in segs {
            let text = seg.text
            let ruby = seg.ruby
            let len = (text as NSString).length
            let segRange = NSRange(location: offset, length: len)
            defer { offset += len }
            if ruby != nil {
                // 注音词不拆分：有任何重叠就整体高亮
                let hit = highlights.contains { NSIntersectionRange($0, segRange).length > 0 }
                out.append(RubySegment(text: text, ruby: ruby, highlighted: hit))
                continue
            }
            // 按字符逐个判断是否在高亮范围内，再合并相邻同状态字符
            let ns = text as NSString
            var buffer = ""
            var bufferHit: Bool?
            var i = 0
            while i < len {
                let r = ns.rangeOfComposedCharacterSequence(at: i)
                let global = NSRange(location: offset + r.location, length: r.length)
                let hit = highlights.contains { NSIntersectionRange($0, global).length > 0 }
                if let bh = bufferHit, bh != hit {
                    out.append(RubySegment(text: buffer, ruby: nil, highlighted: bh))
                    buffer = ""
                }
                buffer += ns.substring(with: r)
                bufferHit = hit
                i = NSMaxRange(r)
            }
            if let bh = bufferHit, !buffer.isEmpty { out.append(RubySegment(text: buffer, ruby: nil, highlighted: bh)) }
        }
        return out
    }
}

/// 水平虚线（线索标记用）。
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
