import SwiftUI
import Translation

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
    var range = NSRange(location: 0, length: 0)
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
        var offset = 0
        for seg in segments {
            if let ruby = seg.ruby {
                let length = (seg.text as NSString).length
                out.append(Atom(text: seg.text, ruby: ruby, highlighted: seg.highlighted, cue: seg.cue,
                                range: NSRange(location: offset, length: length)))
                offset += length
                continue
            }
            var word = ""
            var wordStart = offset
            func flushWord() {
                if !word.isEmpty {
                    out.append(Atom(text: word, ruby: nil, highlighted: seg.highlighted, cue: seg.cue,
                                    range: NSRange(location: wordStart, length: offset - wordStart)))
                    word = ""
                }
                wordStart = offset
            }
            for ch in seg.text {
                let length = (String(ch) as NSString).length
                if ch == "\n" {
                    flushWord()
                    out.append(Atom(text: "", isLineBreak: true, range: NSRange(location: offset, length: length)))
                    offset += length
                    wordStart = offset
                } else if isCJK(ch) || noLineStart.contains(ch) || noLineEnd.contains(ch) {
                    flushWord()
                    out.append(Atom(text: String(ch), ruby: nil, highlighted: seg.highlighted, cue: seg.cue,
                                    range: NSRange(location: offset, length: length)))
                    offset += length
                    wordStart = offset
                } else if ch == " " {
                    word.append(ch)
                    offset += length
                    flushWord()
                } else {
                    word.append(ch)
                    offset += length
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
    private var isPickable = false
    @State private var picked: NSRange?
    @State private var lookup: PickedWord?
    @State private var translating: PickedWord?
    @State private var copied: String?

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

    func pickable(_ on: Bool = true) -> RubyText {
        var copy = self
        copy.isPickable = on
        return copy
    }

    var body: some View {
        if isPickable {
            pickableFlow
        } else if hasRuby || segments.contains(where: { $0.highlighted || $0.cue }) {
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
                            if isPickable {
                                pickableAtom(atom)
                            } else {
                                atomView(atom)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, hasRuby ? Self.rubyLine(style) : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plain)
    }

    private var pickableFlow: some View {
        flow
            .accessibilityValue(Text(verbatim: DemoMode.e2e ? copied ?? "" : ""))
            .sensoryFeedback(.selection, trigger: picked) { _, new in new != nil }
            .accessibilityAction(named: Text(localized: "拷贝整句")) { copy(plain) }
            .sheet(item: $lookup) { word in
                DictionaryLookup(term: word.text).ignoresSafeArea()
            }
            .modifier(SystemTranslation(word: $translating))
    }

    private var atomRanges: [NSRange] {
        groups.flatMap { $0 }.filter { !$0.isLineBreak }.map(\.range)
    }

    private var pickedText: String {
        guard let picked else { return "" }
        return (plain as NSString).substring(with: picked)
    }

    private func pickableAtom(_ atom: Atom) -> some View {
        let inPick = picked.map { NSIntersectionRange($0, atom.range).length > 0 } ?? false
        let anchorsMenu = picked?.location == atom.range.location
        return atomView(atom)
            .background {
                if inPick {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.accentFill)
                        .padding(.horizontal, -1)
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.4) {
                picked = WordPick.range(in: plain, unbreakable: atomRanges, at: atom.range.location)
            }
            .popover(isPresented: Binding(get: { anchorsMenu }, set: { if !$0 { picked = nil } }),
                     arrowEdge: .bottom) {
                PickMenu(
                    canTranslate: SystemTranslation.isAvailable,
                    onCopy: { copy(pickedText) },
                    onLookup: { present(.lookup) },
                    onTranslate: { present(.translate) },
                    onCopySentence: { copy(plain) }
                )
                .presentationCompactAdaptation(.popover)
            }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied = text
        picked = nil
    }

    private enum PickAction { case lookup, translate }

    private func present(_ action: PickAction) {
        let word = PickedWord(text: pickedText)
        picked = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            switch action {
            case .lookup: lookup = word
            case .translate: translating = word
            }
        }
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

struct PickedWord: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

private struct PickMenu: View {
    let canTranslate: Bool
    let onCopy: () -> Void
    let onLookup: () -> Void
    let onTranslate: () -> Void
    let onCopySentence: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item("拷贝", id: "pick.copy", action: onCopy)
            Divider()
            item("查询", id: "pick.lookup", action: onLookup)
            if canTranslate {
                Divider()
                item("翻译", id: "pick.translate", action: onTranslate)
            }
            Divider()
            item("拷贝整句", id: "pick.copySentence", action: onCopySentence)
        }
        .fixedSize()
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pick.menu")
    }

    private func item(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(localized: title)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .accessibilityIdentifier(id)
    }
}

private struct DictionaryLookup: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

private struct SystemTranslation: ViewModifier {
    @Binding var word: PickedWord?

    static var isAvailable: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }

    func body(content: Content) -> some View {
        if #available(iOS 17.4, *) {
            content.translationPresentation(
                isPresented: Binding(get: { word != nil }, set: { if !$0 { word = nil } }),
                text: word?.text ?? ""
            )
        } else {
            content
        }
    }
}
