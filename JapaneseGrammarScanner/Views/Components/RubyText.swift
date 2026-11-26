import SwiftUI

struct RubySegment: Hashable {
    var text: String
    var ruby: String?
    var highlighted = false
    var cue = false
}

private struct Atom: Hashable {
    var text: String
    var ruby: String?
    var highlighted = false
    var cue = false
    var isLineBreak = false
}

private enum AtomBuilder {
    static let noLineStart: Set<Character> = ["、", "。", "，", "．", "」", "』", "）", ")", "！", "？", "!", "?", "：", "；", ":", ";", ",", ".", "…", "ー", "ゃ", "ゅ", "ょ", "っ", "ャ", "ュ", "ョ", "ッ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "〜", "”", "’"]
    static let noLineEnd: Set<Character> = ["「", "『", "（", "(", "“", "‘"]

    static func isCJK(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first?.value else { return false }
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

struct RubyText: View {
    struct Style {
        var font: Font = .body
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
    private let groups: [[Atom]]
    private let hasRuby: Bool
    private var style: Style

    init(japanese: String, highlights: [NSRange] = [], style: Style = Style()) {
        plain = japanese
        self.style = style
        let segs = FuriganaStore.shared.segments(for: japanese)
        segments = RubyText.applyHighlights(segs.map { RubySegment(text: $0.base, ruby: $0.ruby) }, highlights: highlights)
        hasRuby = segs.contains { $0.ruby != nil }
        groups = AtomBuilder.groups(AtomBuilder.atoms(from: segments))
    }

    init(segments: [RubySegment], style: Style = Style()) {
        plain = segments.map(\.text).joined()
        self.style = style
        self.segments = segments
        hasRuby = segments.contains { $0.ruby != nil }
        groups = AtomBuilder.groups(AtomBuilder.atoms(from: segments))
    }

    init(explanation: String, cues: [String] = [], style: Style = Style()) {
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
        if !cues.isEmpty {
            segs = RubyText.applyMarks(segs, ranges: RubyText.cueRanges(in: explanation, cues: cues), mark: \.cue)
        }
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
                .lineSpacing(Self.lineGap(style))
                .multilineTextAlignment(style.alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var flow: some View {
        return FlowLayout(lineSpacing: Self.lineGap(style), centered: style.alignment == .center) {
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
        .padding(.top, hasRuby ? Self.rubyLine(style) : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plain)
    }

    static func rubyLine(_ style: Style) -> CGFloat {
        ceil(UIFontMetrics(forTextStyle: .body).scaledValue(for: style.rubySize) * 1.3)
    }

    static func lineGap(_ style: Style) -> CGFloat {
        max(style.lineSpacing, rubyLine(style))
    }

    private func atomView(_ atom: Atom) -> some View {
        let rubySize = UIFontMetrics(forTextStyle: .body).scaledValue(for: style.rubySize)
        let rubyLine = Self.rubyLine(style)
        return Text(atom.text)
            .font(style.font)
            .fontWeight(atom.highlighted ? .semibold : style.weight)
            .foregroundStyle(atom.highlighted ? style.highlightColor : style.color)
            .lineLimit(1)
            .fixedSize()
            .background(atom.highlighted ? style.highlightColor.opacity(0.14) : Color.clear)
            .overlay(alignment: .bottom) {
                if atom.cue {
                    DashedLine()
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2.5]))
                        .frame(height: 1.2)
                        .offset(y: 2)
                }
            }
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
                        .offset(y: -rubyLine)
                }
            }
    }

    static func cueRanges(in text: String, cues: [String]) -> [NSRange] {
        let ns = text as NSString
        func isHan(_ c: unichar) -> Bool { (0x4E00...0x9FFF).contains(c) || c == 0x3005 }
        func hasKana(_ s: String) -> Bool { s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) } }
        var out: [NSRange] = []
        for cue in cues where !cue.isEmpty {
            let kana = hasKana(cue)
            var search = NSRange(location: 0, length: ns.length)
            while true {
                let r = ns.range(of: cue, options: [], range: search)
                if r.location == NSNotFound { break }
                let before = r.location > 0 ? ns.character(at: r.location - 1) : nil
                let after = NSMaxRange(r) < ns.length ? ns.character(at: NSMaxRange(r)) : nil
                if kana || !(before.map(isHan) ?? false || after.map(isHan) ?? false) { out.append(r) }
                let next = r.location + 1
                search = NSRange(location: next, length: ns.length - next)
            }
        }
        return out
    }

    private static func applyHighlights(_ segs: [RubySegment], highlights: [NSRange]) -> [RubySegment] {
        applyMarks(segs, ranges: highlights, mark: \.highlighted)
    }

    static func applyMarks(_ segs: [RubySegment], ranges highlights: [NSRange], mark: WritableKeyPath<RubySegment, Bool>) -> [RubySegment] {
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
                var marked = seg
                if highlights.contains(where: { NSIntersectionRange($0, segRange).length > 0 }) { marked[keyPath: mark] = true }
                out.append(marked)
                continue
            }
            func piece(_ t: String, _ hit: Bool) -> RubySegment {
                var p = seg
                p.text = t
                if hit { p[keyPath: mark] = true }
                return p
            }
            let ns = text as NSString
            var buffer = ""
            var bufferHit: Bool?
            var i = 0
            while i < len {
                let r = ns.rangeOfComposedCharacterSequence(at: i)
                let global = NSRange(location: offset + r.location, length: r.length)
                let hit = highlights.contains { NSIntersectionRange($0, global).length > 0 }
                if let bh = bufferHit, bh != hit {
                    out.append(piece(buffer, bh))
                    buffer = ""
                }
                buffer += ns.substring(with: r)
                bufferHit = hit
                i = NSMaxRange(r)
            }
            if let bh = bufferHit, !buffer.isEmpty { out.append(piece(buffer, bh)) }
        }
        return out
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
