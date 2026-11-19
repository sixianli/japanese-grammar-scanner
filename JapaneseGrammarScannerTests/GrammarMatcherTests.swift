import SwiftUI
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

    /// 长跨度的语法（や……など）只框「や」「など」，中间的别的语法不会被合并进来
    func testLongSpanMatchesOnlyBoxKeyParts() {
        let text = "写真が撮れる店やアニメに出てきた料理が食べられる店などができた"
        let ns = text as NSString
        let yaNado = GrammarMatch(grammarID: "ya-nado", range: NSRange(location: ns.range(of: "や").location,
                                                                         length: NSMaxRange(ns.range(of: "など")) - ns.range(of: "や").location))
        let teKuru = GrammarMatch(grammarID: "te-kuru", range: ns.range(of: "てき"))
        let rareru = GrammarMatch(grammarID: "rareru", range: ns.range(of: "られる"))
        let clusters = GrammarMatcher.clusters(from: [yaNado, teKuru, rareru], text: text)
        XCTAssertEqual(clusters.count, 3, "や…など 不应把中间的 てくる、られる 合并成一个框")
        let ya = clusters.first { $0.grammarIDs == ["ya-nado"] }
        XCTAssertEqual(ya?.ranges.map { ns.substring(with: $0) }, ["や", "など"])
        XCTAssertEqual(ya?.matchedTexts["ya-nado"]?.hasPrefix("や"), true)
    }

    /// 从扫描进入讲解时，「がきっかけで」应对应「〜をきっかけに」的用法②
    func testBestSenseForScannedText() {
        guard let p = GrammarLibrary.shared.point(id: "wo-kikkake-ni") ?? GrammarLibrary.shared.points.first(where: { $0.title.contains("きっかけ") }) else {
            return XCTFail("找不到「〜をきっかけに」")
        }
        let i = GrammarDetailView.bestSense(for: "がきっかけで", in: p)
        XCTAssertNotNil(i)
        if let i { XCTAssertTrue(p.senses[i].connection.contains("がきっかけ"), "应定位到「がきっかけで」那个用法") }
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
        XCTAssertEqual(ContentLanguage.from(identifier: "my-MM"), .my)
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
        if case .trial = S.access(purchases: [S.ProductID.trial: start], now: start.addingTimeInterval(13 * 86_400)) {} else {
            XCTFail("第 13 天应仍在试用期")
        }
        XCTAssertEqual(S.access(purchases: [S.ProductID.trial: start], now: start.addingTimeInterval(15 * 86_400)), .trialExpired)
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

    /// 同形语法已合并：旧 id 仍能找到合并后的语法点；标题不带中文说明，也不再有同名语法点。
    func testMergedSameFormGrammar() {
        guard let p = library.point(id: "sou-da-hearsay") else { return XCTFail() }
        XCTAssertEqual(p.id, "sou-da-appearance")
        XCTAssertEqual(p.titleForm, "〜そうだ")
        XCTAssertGreaterThanOrEqual(p.senses.count, 2)
        let titles = library.points.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count, "有重复的语法标题")
        for t in titles {
            XCTAssertNil(t.range(of: "（[^）ぁ-んァ-ヶ]*[一-龥][^）ぁ-んァ-ヶ]*）", options: .regularExpression), "标题带中文说明: \(t)")
        }
        // 「〜まで」：N5 和 N3 的义项都在，N3 列表里也能找到它
        guard let made = library.point(id: "made-even") else { return XCTFail() }
        XCTAssertEqual(made.level, .n5)
        XCTAssertTrue(made.levels.contains(.n3))
        XCTAssertTrue(library.points(for: .n3).contains(made))
    }

    /// 搜索按相关度：语法形式命中优先，例句里出现不算。
    func testSearchRelevance() {
        let areba = library.search("あれば")
        XCTAssertEqual(areba.first?.id, "to-areba")
        for unrelated in ["nari-nari", "nari-tomo", "ba-koso"] {
            XCTAssertFalse(areba.contains { $0.id == unrelated }, "「あれば」不应搜到 \(unrelated)")
        }
        XCTAssertEqual(library.search("にもかかわらず").first?.id, "ni-mo-kakawarazu")
        XCTAssertEqual(library.search("にも関わらず").first?.id, "ni-mo-kakawarazu")
        XCTAssertEqual(library.search("ニモカカワラズ").first?.id, "ni-mo-kakawarazu")
        XCTAssertFalse(library.search("尽管").isEmpty)
        // 按意思搜索：近义说法也能找到；讲解正文里顺带出现的不算
        let notSo = library.search("不那么").map(\.id)
        XCTAssertEqual(notSo.first, "amari-nai")
        XCTAssertFalse(notSo.contains("kamoshirenai"), "「不那么」不应搜到〜かもしれない")
        XCTAssertEqual(library.search("てしまう").first?.id, "te-shimau")
    }

    /// 「识别到 N 个语法点」与列表条目数一致：旧 id 换新、去重、只保留库里有的。
    func testDisplayableIDs() {
        let ids = library.displayableIDs(["te-shimau", "sou-da-hearsay", "sou-da-appearance", "no-such-id", "te-shimau"])
        XCTAssertEqual(ids, ["te-shimau", "sou-da-appearance"])
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
        XCTAssertEqual(store.dueForReview(now: t0.addingTimeInterval(86_400 + 1)).map(\.id), ["te-shimau"], "1 天后需要复习")
        store.recordViewed("te-shimau", now: t0.addingTimeInterval(86_400 + 1))
        XCTAssertTrue(store.dueForReview(now: t0.addingTimeInterval(2 * 86_400)).isEmpty, "复习后进入 3 天间隔")
        XCTAssertEqual(store.dueForReview(now: t0.addingTimeInterval(5 * 86_400)).map(\.id), ["te-shimau"])
        XCTAssertTrue(store.learnedIDs.contains("te-shimau"))
        XCTAssertEqual(store.viewCount(of: "te-shimau"), 2)
        XCTAssertEqual(store.viewCount(of: "never-seen"), 0)
        store.clearViewed()
    }

    /// 遗忘越多（保持率越低）的排在越前面
    func testReviewPrioritizesLowestRetention() {
        let defaults = UserDefaults(suiteName: "HistoryStoreTests2")!
        defaults.removePersistentDomain(forName: "HistoryStoreTests2")
        let store = HistoryStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.recordViewed("tai", now: t0)                              // 看过 10 天
        store.recordViewed("nagara", now: t0.addingTimeInterval(8 * 86_400)) // 看过 2 天
        let due = store.dueForReview(now: t0.addingTimeInterval(10 * 86_400))
        XCTAssertEqual(due.map(\.id), ["tai", "nagara"])
        XCTAssertLessThan(due[0].retention, due[1].retention)
        XCTAssertEqual(HistoryStore.retention(.init(id: "x", firstViewed: t0, lastViewed: t0, stage: 0), now: t0.addingTimeInterval(86_400)), 0.9, accuracy: 1e-9)
        store.clearViewed()
    }
}


/// 渲染详情页（重点覆盖合并后的语法点），确保不会卡死或崩溃、渲染不过慢。
@MainActor
final class DetailRenderTests: XCTestCase {
    func testEveryDetailPageRenders() {
        let library = GrammarLibrary(language: .zhHans)
        let suite = "DetailRenderTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let favorites = FavoritesStore(defaults: defaults)
        let history = HistoryStore(defaults: defaults)
        let entitlements = EntitlementStore(unlockedForTesting: true)
        let priority = ["made-until", "izen", "oouseru", "to-quotation", "ni-destination-target", "you-na-example"]
        // 合并后的语法点（义项多、等级多）+ 每隔 40 个抽一个，覆盖各等级又不拖慢 CI
        let merged = library.points.filter { $0.levels.count > 1 || $0.senses.count >= 7 }.map(\.id)
        let sampled = library.points.enumerated().filter { $0.offset % 40 == 0 }.map(\.element.id)
        var ids: [String] = []
        for id in priority + merged + sampled where !ids.contains(id) { ids.append(id) }
        // 先渲染一次做预热（首次加载注音表、字体等一次性开销不计入单页耗时）
        let warmup = ImageRenderer(content: GrammarDetailView(grammarID: ids[0])
            .environmentObject(library).environmentObject(favorites)
            .environmentObject(entitlements).environmentObject(history).frame(width: 430))
        warmup.proposedSize = ProposedViewSize(width: 430, height: 3000)
        _ = warmup.uiImage
        for id in ids {
            let view = GrammarDetailView(grammarID: id)
                .environmentObject(library)
                .environmentObject(favorites)
                .environmentObject(entitlements)
                .environmentObject(history)
                .frame(width: 430)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: 430, height: 3000)
            let start = Date()
            XCTAssertNotNil(renderer.uiImage, "\(id) 详情页渲染失败")
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 3, "\(id) 详情页渲染过慢: \(elapsed)s")
        }
    }
}


final class NoteParserTests: XCTestCase {
    func testSplitsWrongAndRightSentences() {
        let items = NoteParser.parse("修饰名词必须加「の」：×「日本について本」→ ○「日本についての本」（或「日本に関する本」）。")
        XCTAssertEqual(items.first, .text("修饰名词必须加「の」"))
        XCTAssertTrue(items.contains(.example(correct: false, sentence: "日本について本")))
        XCTAssertTrue(items.contains(.example(correct: true, sentence: "日本についての本")))
        XCTAssertEqual(items.last, .text("或「日本に関する本」"))
    }

    func testPlainNoteUnchanged() {
        XCTAssertEqual(NoteParser.parse("没有例句的说明。"), [.text("没有例句的说明。")])
    }
}
