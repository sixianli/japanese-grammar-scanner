import XCTest
@testable import JapaneseGrammarScanner

/// 新版「相近语法」对比资料：能加载、引用的语法点存在、例句都标出了语法、每种语言都有翻译。
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
                    for s in [item.current, item.other] {
                        XCTAssertTrue(s.segments.contains { $0.highlighted }, "\(id) → \(item.id) 例句没有标出语法：\(s.plain)")
                        XCTAssertFalse(s.plain.contains("|") || s.plain.contains("*"), "\(id) → \(item.id) 标记没有去掉")
                    }
                }
            }
        }
        // 没有新版资料的语法点仍用旧版列表
        XCTAssertNil(lib.contrasts(for: "te-shimau"))
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
            // 日语例句不翻译
            XCTAssertEqual(first.current.plain, bFirst.current.plain, lang.rawValue)
            if lang != .zhHant {
                XCTAssertNotEqual(first.diff, bFirst.diff, "\(lang.rawValue) 缺少翻译")
                XCTAssertNotEqual(first.explain, bFirst.explain, "\(lang.rawValue) 缺少翻译")
                XCTAssertNotEqual(first.current.tr, bFirst.current.tr, "\(lang.rawValue) 缺少翻译")
            }
        }
    }
}
