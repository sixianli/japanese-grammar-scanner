import XCTest
@testable import JapaneseGrammarScanner

final class GrammarLibraryTests: XCTestCase {
    let library = GrammarLibrary.shared

    func testLibraryLoadsAllLevels() {
        XCTAssertGreaterThan(library.points.count, 50)
        for level in [JLPTLevel.n5, .n4, .n3, .n2] {
            XCTAssertFalse(library.points(for: level).isEmpty, "\(level.rawValue) 没有语法点")
        }
        XCTAssertEqual(Set(library.points.map(\.id)).count, library.points.count, "id 重复")
    }

    /// 与 Python 校验脚本不同，这里用 iOS 实际使用的 ICU 正则引擎验证。
    func testAllPatternsCompileWithICU() {
        for p in library.points {
            for pattern in p.patterns {
                XCTAssertNoThrow(try NSRegularExpression(pattern: pattern), "\(p.id): \(pattern)")
            }
        }
    }

    func testEveryExampleIsRecognizedByItsOwnPatterns() {
        for p in library.points {
            let regexes = p.patterns.compactMap { try? NSRegularExpression(pattern: $0) }
            for ex in p.allExamples {
                let range = NSRange(location: 0, length: (ex.ja as NSString).length)
                let hit = regexes.contains { $0.firstMatch(in: ex.ja, range: range) != nil }
                XCTAssertTrue(hit, "\(p.id) 例句未被识别: \(ex.ja)")
            }
        }
    }

    func testSimilarReferencesExist() {
        for p in library.points {
            for s in p.similar {
                if let id = s.id { XCTAssertNotNil(library.point(id: id), "\(p.id) → \(id)") }
            }
            for id in p.subsumes ?? [] { XCTAssertNotNil(library.point(id: id), "\(p.id) subsumes \(id)") }
        }
    }

    func testSearch() {
        XCTAssertFalse(library.search("てしまう").isEmpty)
        XCTAssertFalse(library.search("〜てしまう").isEmpty)
        XCTAssertTrue(library.search("N5").contains { $0.level == .n5 })
    }
}

final class GrammarMatcherTests: XCTestCase {
    let matcher = GrammarLibrary.shared.matcher

    func testRecognizesCommonGrammar() {
        let ids = Set(matcher.matches(in: "宿題を忘れてしまったので、先生に叱られました。").map(\.grammarID))
        XCTAssertTrue(ids.contains("te-shimau"), "\(ids)")
        XCTAssertTrue(ids.contains("node"), "\(ids)")
    }

    func testSubsumesSuppressesInnerMatch() {
        let matches = matcher.matches(in: "明日までにレポートを出さなければならない。")
        let ids = Set(matches.map(\.grammarID))
        XCTAssertTrue(ids.contains("nakereba-naranai"), "\(ids)")
        XCTAssertFalse(ids.contains("ba-conditional"), "なければ 中的 ば 不应单独识别: \(ids)")
    }

    func testEmptyText() {
        XCTAssertTrue(matcher.matches(in: "").isEmpty)
    }

    func testClustersMergeOverlaps() {
        let matches = [
            GrammarMatch(grammarID: "a", range: NSRange(location: 0, length: 4)),
            GrammarMatch(grammarID: "b", range: NSRange(location: 2, length: 4)),
            GrammarMatch(grammarID: "c", range: NSRange(location: 10, length: 2)),
        ]
        let clusters = GrammarMatcher.clusters(from: matches)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].range, NSRange(location: 0, length: 6))
        XCTAssertEqual(clusters[0].grammarIDs, ["a", "b"])
        XCTAssertEqual(clusters[1].grammarIDs, ["c"])
    }
}

final class ScanAnalyzerTests: XCTestCase {
    func testBoxesSpanLinesAndAreFlipped() {
        // 两行文本：「忘れてし」「まった。」——语法跨行
        let line1 = RecognizedLine(
            rangeInText: NSRange(location: 0, length: 4), text: "忘れてし",
            boundingBox: CGRect(x: 0, y: 0.8, width: 0.4, height: 0.1), boxForRange: { _ in nil })
        let line2 = RecognizedLine(
            rangeInText: NSRange(location: 4, length: 4), text: "まった。",
            boundingBox: CGRect(x: 0, y: 0.6, width: 0.4, height: 0.1), boxForRange: { _ in nil })
        let result = ScanAnalyzer.analyze(text: "忘れてしまった。", lines: [line1, line2], matcher: GrammarLibrary.shared.matcher)
        let cluster = result.clusters.first { c in c.grammarIDs.contains("te-shimau") }
        XCTAssertNotNil(cluster)
        let boxes = result.boxes.filter { $0.clusterID == cluster?.id }
        XCTAssertEqual(boxes.count, 2, "跨行命中应在两行各画一个框")
        for b in boxes {
            XCTAssertTrue(b.rect.minY >= 0 && b.rect.maxY <= 1)
            XCTAssertLessThan(b.rect.minY, 0.5, "坐标应已翻转为左上原点")
        }
    }
}

@MainActor
final class FavoritesStoreTests: XCTestCase {
    func testToggleAndPersist() {
        let defaults = UserDefaults(suiteName: "FavoritesStoreTests")!
        defaults.removePersistentDomain(forName: "FavoritesStoreTests")
        let store = FavoritesStore(defaults: defaults)
        XCTAssertFalse(store.isFavorite("tai"))
        store.toggle("tai")
        store.toggle("te-shimau")
        XCTAssertEqual(store.ids, ["te-shimau", "tai"])
        XCTAssertEqual(FavoritesStore(defaults: defaults).ids, ["te-shimau", "tai"])
        store.toggle("tai")
        XCTAssertFalse(store.isFavorite("tai"))
    }
}

final class LocalizationTests: XCTestCase {
    func testLanguageDetection() {
        XCTAssertEqual(ContentLanguage.from(identifier: "zh-Hans"), .zhHans)
        XCTAssertEqual(ContentLanguage.from(identifier: "zh-Hant-TW"), .zhHant)
        XCTAssertEqual(ContentLanguage.from(identifier: "zh-HK"), .zhHant)
        XCTAssertEqual(ContentLanguage.from(identifier: "ko-KR"), .ko)
        XCTAssertEqual(ContentLanguage.from(identifier: "es-MX"), .es)
        XCTAssertEqual(ContentLanguage.from(identifier: "vi"), .vi)
        XCTAssertEqual(ContentLanguage.from(identifier: "en-GB"), .en)
        XCTAssertEqual(ContentLanguage.from(identifier: "fr"), .en, "不支持的语言回退到英语")
    }

    /// 每种语言的讲解都必须完整覆盖所有语法点（不能回退显示简体中文）。
    func testEveryLanguageLocalizesEveryPoint() {
        let base = GrammarLibrary(language: .zhHans)
        for lang in ContentLanguage.allCases where lang != .zhHans {
            let lib = GrammarLibrary(language: lang)
            XCTAssertEqual(lib.points.count, base.points.count, "\(lang)")
            for p in lib.points {
                guard let b = base.point(id: p.id) else { continue }
                // 繁体中文由简体自动转换，个别句子恰好没有需要转换的字，可能与简体完全相同
                if lang != .zhHant {
                    XCTAssertNotEqual(p.meaning, b.meaning, "\(lang.rawValue) 缺少 \(p.id) 的讲解")
                    XCTAssertNotEqual(p.etymology, b.etymology, "\(lang.rawValue) 缺少 \(p.id) 的词源")
                }
                XCTAssertEqual(p.allExamples.map(\.ja), b.allExamples.map(\.ja), "日语例句不应被翻译")
                if lang != .zhHant {
                    XCTAssertNotEqual(p.allExamples.first?.translation, b.allExamples.first?.translation, "\(lang.rawValue) \(p.id) 例句未翻译")
                }
            }
        }
    }
}

final class FuriganaTests: XCTestCase {
    /// 所有含汉字的日语例句都必须有注音数据。
    func testAllExamplesHaveFurigana() {
        let kanji = try! NSRegularExpression(pattern: "[\\u3400-\\u9fff々]")
        for p in GrammarLibrary(language: .zhHans).points {
            let sentences = p.allExamples.map(\.ja) + (p.scenes.daily + p.scenes.work).map(\.example.ja)
            for ja in sentences where kanji.firstMatch(in: ja, range: NSRange(location: 0, length: (ja as NSString).length)) != nil {
                XCTAssertTrue(FuriganaStore.shared.hasRuby(ja), "\(p.id) 缺少注音: \(ja)")
                XCTAssertEqual(FuriganaStore.shared.segments(for: ja).map(\.base).joined(), ja, "注音片段拼接后应等于原文")
            }
        }
    }
}

final class EntitlementTests: XCTestCase {
    func testTrialAndUnlockStates() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        typealias S = EntitlementStore
        XCTAssertEqual(S.access(purchases: [:], now: start), .notStarted)
        if case .trial = S.access(purchases: [S.ProductID.trial: start], now: start.addingTimeInterval(6 * 86_400)) {} else {
            XCTFail("第 6 天应仍在试用期")
        }
        XCTAssertEqual(S.access(purchases: [S.ProductID.trial: start], now: start.addingTimeInterval(8 * 86_400)), .trialExpired)
        XCTAssertEqual(S.access(purchases: [S.ProductID.trial: start, S.ProductID.lifetime: start], now: start.addingTimeInterval(30 * 86_400)), .unlocked)
        XCTAssertEqual(S.access(purchases: [S.ProductID.lifetime: start], now: start), .unlocked)
    }
}

final class ContentRulesTests: XCTestCase {
    let library = GrammarLibrary(language: .zhHans)

    /// 相近语法必须都能跳转到语法库中的语法点，且不能指向自己。
    func testEverySimilarIsLinkable() {
        for p in library.points {
            for s in p.similar {
                let target = s.id.flatMap { library.point(id: $0) }
                XCTAssertNotNil(target, "\(p.id) 的相近语法「\(s.title)」无法跳转")
                XCTAssertNotEqual(target?.id, p.id, "\(p.id) 的相近语法指向了自己")
            }
        }
    }

    func testFormationAndNotesPresent() {
        for p in library.points {
            XCTAssertFalse(p.formation.isEmpty, "\(p.id) 缺少组词逻辑")
            XCTAssertFalse(p.notes.isEmpty, "\(p.id) 缺少注意")
        }
    }

    /// 汉字写法可以搜索到。
    func testKanjiFormIsSearchable() {
        for p in library.points {
            guard let k = p.kanji else { continue }
            XCTAssertTrue(library.search(k).contains(p), "用「\(k)」搜不到 \(p.id)")
        }
    }

    func testTitleParts() {
        guard let p = library.point(id: "sou-da-hearsay") else { return XCTFail() }
        XCTAssertEqual(p.titleNote, "（传闻）")
        XCTAssertEqual(p.titleForm, "〜そうだ")
    }
}

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testSpacedReview() {
        let defaults = UserDefaults(suiteName: "HistoryStoreTests")!
        defaults.removePersistentDomain(forName: "HistoryStoreTests")
        let store = HistoryStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.recordViewed("te-shimau", now: t0)
        XCTAssertTrue(store.dueForReview(now: t0.addingTimeInterval(3600)).isEmpty, "刚看过不需要复习")
        XCTAssertEqual(store.dueForReview(now: t0.addingTimeInterval(86_400 + 1)), ["te-shimau"], "1 天后需要复习")
        store.recordViewed("te-shimau", now: t0.addingTimeInterval(86_400 + 1))
        XCTAssertTrue(store.dueForReview(now: t0.addingTimeInterval(2 * 86_400)).isEmpty, "复习后进入 3 天间隔")
        XCTAssertEqual(store.dueForReview(now: t0.addingTimeInterval(5 * 86_400)), ["te-shimau"])
        XCTAssertTrue(store.learnedIDs.contains("te-shimau"))
        store.clearViewed()
    }
}
