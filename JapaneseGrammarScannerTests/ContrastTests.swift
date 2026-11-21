import XCTest
@testable import JapaneseGrammarScanner

final class ContrastTests: XCTestCase {
    func testContrastsLoadAndReferencesExist() {
        let lib = GrammarLibrary(language: .zhHans)
        let ids = ["tokoro-da", "ta-bakari", "you-ni-naru", "you-ni-suru", "sou-da-appearance",
                   "you-da", "hazu-da", "wake-da", "tame-ni", "koto-ni-suru"]
        for id in ids {
            guard let c = lib.contrasts(for: id) else { return XCTFail("\(id) 没有对比资料") }
            XCTAssertFalse(c.groups.isEmpty, id)
            for g in c.groups {
                XCTAssertFalse(g.items.isEmpty, "\(id)/\(g.kind)")
                for item in g.items {
                    XCTAssertNotNil(lib.point(id: item.id), "\(id) → \(item.id) 不存在")
                    XCTAssertFalse(item.current.isEmpty || item.other.isEmpty, "\(id) → \(item.id) 缺少例句")
                    for s in item.current + item.other {
                        XCTAssertTrue(s.segments.contains { $0.highlighted }, "\(id) → \(item.id) 例句没有标出语法：\(s.plain)")
                        XCTAssertFalse(s.plain.contains("|") || s.plain.contains("*"), "\(id) → \(item.id) 标记没有去掉")
                    }
                }
            }
        }
        let none = lib.contrasts(for: "mou-ta-already")
        XCTAssertNotNil(none, "审过的语法点应有新版资料")
        XCTAssertEqual(none?.groups.isEmpty, true)
        XCTAssertNotNil(lib.contrasts(for: "te-shimau"))
    }

    func testEveryPointHasContrasts() {
        let lib = GrammarLibrary(language: .zhHans)
        for p in lib.points {
            guard let c = lib.contrasts(for: p.id) else { XCTFail("\(p.id) 缺少新版相近语法资料"); continue }
            for g in c.groups {
                XCTAssertFalse(g.items.isEmpty, "\(p.id)/\(g.kind) 不应有空组")
                for item in g.items {
                    XCTAssertNotNil(lib.point(id: item.id), "\(p.id) → \(item.id) 不存在")
                    for s in item.current + item.other {
                        XCTAssertTrue(s.segments.contains { $0.highlighted }, "\(p.id) → \(item.id) 例句没有标出语法：\(s.plain)")
                    }
                }
            }
        }
    }

    func testSegmentsParseRubyHighlightAndCue() {
        let s = GrammarContrasts.Sentence(ja: "~今:いま|、|家:いえ|を|出:で|*たところだ|。", tag: "", tr: "")
        let segs = s.segments
        XCTAssertEqual(s.plain, "今、家を出たところだ。")
        XCTAssertEqual(segs.first?.ruby, "いま")
        XCTAssertEqual(segs.first?.cue, true)
        XCTAssertEqual(segs.first(where: { $0.highlighted })?.text, "たところだ")
    }

    func testEveryLanguageTranslatesContrasts() {
        let base = GrammarLibrary(language: .zhHans)
        guard let b = base.contrasts(for: "tokoro-da") else { return XCTFail("没有 tokoro-da") }
        for lang in ContentLanguage.allCases where lang != .zhHans {
            let lib = GrammarLibrary(language: lang)
            guard let c = lib.contrasts(for: "tokoro-da") else { XCTFail("\(lang.rawValue)"); continue }
            XCTAssertEqual(c.groups.count, b.groups.count, lang.rawValue)
            let first = c.groups[0].items[0], bFirst = b.groups[0].items[0]
            XCTAssertEqual(first.current.map(\.plain), bFirst.current.map(\.plain), lang.rawValue)
            if lang != .zhHant {
                XCTAssertNotEqual(first.diff, bFirst.diff, "\(lang.rawValue) 缺少翻译")
                XCTAssertNotEqual(first.explain, bFirst.explain, "\(lang.rawValue) 缺少翻译")
                XCTAssertNotEqual(first.current[0].tr, bFirst.current[0].tr, "\(lang.rawValue) 缺少翻译")
            }
        }
    }

    private struct FormsEntry: Decodable {
        struct Form: Decodable { let key: String }
        let type: String
        let forms: [Form]?
    }

    func testMultiFormPointsHaveSentenceForEveryForm() throws {
        let url = try XCTUnwrap(["Grammar/contrasts", "contrasts", nil].lazy.compactMap {
            Bundle.main.url(forResource: "forms", withExtension: "json", subdirectory: $0)
        }.first, "缺少 contrasts/forms.json")
        let forms = try JSONDecoder().decode([String: FormsEntry].self, from: Data(contentsOf: url))
            .compactMapValues { $0.type == "A" ? $0.forms?.map(\.key) : nil }
        XCTAssertFalse(forms.isEmpty)
        let lib = GrammarLibrary(language: .zhHans)

        func covered(_ list: [GrammarContrasts.Sentence], _ keys: [String]) -> Set<String> {
            let sorted = keys.sorted { $0.count > $1.count }
            return Set(list.compactMap { s in
                let h = s.segments.filter(\.highlighted).map(\.text).joined()
                return sorted.first { h.contains($0) }
            })
        }
        for p in lib.points {
            guard let c = lib.contrasts(for: p.id) else { continue }
            for g in c.groups {
                for item in g.items {
                    if let keys = forms[p.id], item.thisTitle == nil {
                        XCTAssertEqual(covered(item.current, keys), Set(keys), "\(p.id) → \(item.id)：本页每种形式都要有例句")
                    }
                    if let keys = forms[item.id], item.title == nil {
                        XCTAssertEqual(covered(item.other, keys), Set(keys), "\(p.id) → \(item.id)：对方每种形式都要有例句")
                    }
                }
            }
        }
    }

    func testAmariHasThreeForms() throws {
        let lib = GrammarLibrary(language: .zhHans)
        let item = try XCTUnwrap(lib.contrasts(for: "amari-nai")?.groups.flatMap(\.items).first { $0.id == "amari-ni" })
        if item.title == nil {
            XCTAssertGreaterThanOrEqual(item.other.count, 3, "あまり／あまりに／あまりの 应各有一句例句")
        }
    }

    func testMultiSentenceTranslationsAlign() {
        let base = GrammarLibrary(language: .zhHans)
        for lang in ContentLanguage.allCases where lang != .zhHans {
            let lib = GrammarLibrary(language: lang)
            for p in base.points {
                guard let b = base.contrasts(for: p.id), let c = lib.contrasts(for: p.id) else { continue }
                for (bg, cg) in zip(b.groups, c.groups) {
                    for (bi, ci) in zip(bg.items, cg.items) {
                        XCTAssertEqual(bi.current.count, ci.current.count, "\(lang.rawValue) \(p.id) → \(bi.id)")
                        XCTAssertEqual(bi.other.count, ci.other.count, "\(lang.rawValue) \(p.id) → \(bi.id)")
                    }
                }
            }
        }
    }

    func testCuesJoinAdjacentSegments() {
        let s = GrammarContrasts.Sentence(ja: "今:いま|から|走:はし|っ|*たところで|、|~間:ま|~に|~合:あ|~わない|。", tag: "", tr: "")
        XCTAssertEqual(s.segments.filter(\.cue).map(\.text).joined(), "間に合わない")
    }

    func testCueRangesInExplanation() {
        let text = "看「いつか」：今天想要的 → こんな；去年結婚した。说「今」的时候"
        let ns = text as NSString
        XCTAssertEqual(RubyText.cueRanges(in: text, cues: ["いつか"]).map { ns.substring(with: $0) }, ["いつか"])
        let r = RubyText.cueRanges(in: text, cues: ["今"])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.first.map { ns.substring(with: NSRange(location: $0.location - 1, length: 3)) }, "「今」")
        XCTAssertTrue(RubyText.cueRanges(in: text, cues: ["結婚"]).isEmpty, "去年結婚した 里的 結婚 前后都是汉字，不算")
        XCTAssertTrue(RubyText.cueRanges(in: text, cues: []).isEmpty)
    }

    func testApplyMarksKeepsOtherFlags() {
        let segs = [RubySegment(text: "看"), RubySegment(text: "いつか"), RubySegment(text: "今", ruby: "いま", highlighted: true)]
        let out = RubyText.applyMarks(segs, ranges: [NSRange(location: 1, length: 3), NSRange(location: 4, length: 1)], mark: \.cue)
        XCTAssertEqual(out.map(\.text), ["看", "いつか", "今"])
        XCTAssertEqual(out.map(\.cue), [false, true, true])
        XCTAssertEqual(out.last?.highlighted, true, "加线索不能丢掉原来的高亮")
        XCTAssertEqual(out.last?.ruby, "いま")
    }

    func testEveryCueIsNamedInExplainInEveryLanguage() {
        for lang in ContentLanguage.allCases {
            let lib = GrammarLibrary(language: lang)
            for p in lib.points {
                for item in lib.contrasts(for: p.id)?.groups.flatMap(\.items) ?? [] {
                    for cue in item.cues where RubyText.cueRanges(in: item.explain, cues: [cue]).isEmpty {
                        XCTFail("\(lang.rawValue) \(p.id) → \(item.id)：「怎么分辨」没有点名线索 \(cue)")
                    }
                }
            }
        }
    }

    func testTeIruAndTaAreNotListedAsSameMeaning() {
        let lib = GrammarLibrary(language: .zhHans)
        for (a, b) in [("te-iru", "ta-form"), ("ta-form", "te-iru")] {
            let meaning = lib.contrasts(for: a)?.groups.first { $0.kind == .meaning }
            XCTAssertFalse(meaning?.items.contains { $0.id == b } ?? false, "\(a) 的「意思差不多的」里不应有 \(b)")
        }
        let ta = lib.contrasts(for: "ta-form")?.groups.first { $0.kind == .meaning }
        XCTAssertTrue(ta?.items.contains { $0.id == "masu-forms" } ?? false)
    }

    func testTameNiHasOneMeaningGroupPerSense() throws {
        for lang in ContentLanguage.allCases {
            let lib = GrammarLibrary(language: lang)
            let c = try XCTUnwrap(lib.contrasts(for: "tame-ni"), lang.rawValue)
            let meaning = c.groups.filter { $0.kind == .meaning }
            XCTAssertTrue(c.splitsMeaningBySense, lang.rawValue)
            XCTAssertEqual(meaning.map(\.sense), [1, 2], lang.rawValue)
            XCTAssertEqual(meaning.map { $0.items.map(\.id) }, [["ni-wa-purpose"], ["kara-from"]], lang.rawValue)
            XCTAssertFalse(meaning.flatMap(\.items).contains { $0.id == "you-na-example" }, "\(lang.rawValue)：〜ような 那一页讲比喻，不该出现在「为了」组")
            XCTAssertEqual(Set(meaning.map(\.note)).count, 2, "\(lang.rawValue)：两组说明应各写一个意思")
        }
        let zh = GrammarLibrary(language: .zhHans).contrasts(for: "tame-ni")?.groups.filter { $0.kind == .meaning }.map(\.note)
        XCTAssertEqual(zh, ["都表示「为了」", "都表示「因为」"])
    }

    func testSingleMeaningGroupDoesNotSplit() throws {
        let c = try XCTUnwrap(GrammarLibrary(language: .zhHans).contrasts(for: "you-ni-naru"))
        XCTAssertLessThanOrEqual(c.groups.filter { $0.kind == .meaning }.count, 1)
        XCTAssertFalse(c.splitsMeaningBySense)
    }

    func testGroupWithoutSenseDecodes() throws {
        let json = #"{"points":[{"id":"x","groups":[{"kind":"meaning","note":"n","items":[]}]}]}"#
        let file = try JSONDecoder().decode(GrammarContrasts.File.self, from: Data(json.utf8))
        XCTAssertNil(file.points.first?.groups.first?.sense)
        XCTAssertEqual(file.points.first?.splitsMeaningBySense, false)
    }
}
