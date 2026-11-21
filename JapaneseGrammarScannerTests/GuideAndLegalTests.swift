import XCTest
@testable import JapaneseGrammarScanner

/// 硬门槛：使用指南覆盖每个主要功能、所有语言都有翻译；使用条款、隐私政策、开源许可与代码一致。
/// （页面入口必须归到某个功能，由 AppFeature.swift 里没有 default 的 switch 在编译时保证。）
final class GuideAndLegalTests: XCTestCase {
    private let languages = ["en", "ko", "es", "vi", "my", "zh-Hant"]

    private func bundle(_ lang: String) -> Bundle? {
        Bundle.main.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// 某个界面文字在 lang 里有翻译（缺翻译时系统会原样返回中文）
    private func translated(_ key: String, _ lang: String) -> Bool {
        guard let b = bundle(lang) else { return false }
        let v = b.localizedString(forKey: key, value: "\u{0}", table: nil)
        if v == "\u{0}" { return false }
        if lang == "zh-Hant" { return true }
        return v != key
    }

    func testEveryFeatureHasGuide() {
        for f in AppFeature.allCases {
            let g = f.guide
            XCTAssertFalse(g.title.isEmpty, "\(f) 缺少指南标题")
            XCTAssertFalse(g.summary.isEmpty, "\(f) 缺少一句话说明")
            XCTAssertGreaterThanOrEqual(g.steps.count, 2, "\(f) 的使用指南至少两步")
            for s in g.steps {
                XCTAssertTrue(s.keys.allSatisfy { !$0.isEmpty }, "\(f) 有空的步骤")
                XCTAssertNotNil(UIImage(systemName: s.symbol), "\(f) 的步骤图标 \(s.symbol) 不存在")
            }
        }
        // 核心功能都在，且排在前面
        XCTAssertEqual(AppFeature.core, [.scan, .scanResult, .detail, .contrast, .review])
        XCTAssertEqual(Set(AppFeature.core + AppFeature.more), Set(AppFeature.allCases))
    }

    func testGuideIsTranslatedIntoEveryLanguage() {
        var keys: [String] = ["使用指南", "核心功能", "更多功能", "再看一遍入门引导"]
        for f in AppFeature.allCases {
            let g = f.guide
            keys += [g.title, g.summary] + g.steps.flatMap(\.keys) + (g.tip.map { [$0] } ?? [])
        }
        for lang in languages {
            let missing = keys.filter { !translated($0, lang) }
            XCTAssertTrue(missing.isEmpty, "\(lang) 缺少使用指南翻译：\(missing.prefix(5))")
        }
    }

    /// 每个标签页都归到某个有指南的功能
    func testEveryTabBelongsToAFeature() {
        for tab in AppTab.all {
            XCTAssertNotNil(AppTab.feature(of: tab), "标签 \(tab) 没有归到任何功能")
        }
    }

    // MARK: 使用条款：功能相关的事实取自代码

    func testTermsFollowPaymentSetting() {
        let ids = LegalContent.termsSections.map(\.id)
        XCTAssertEqual(ids.contains("purchase"), Features.paymentsEnabled, "开启购买时条款里要有购买条目，没开就不能有")
        XCTAssertTrue(ids.contains("eula") && ids.contains("content"))
    }

    // MARK: 隐私政策：只显示与当前版本相符的小节

    func testPrivacySectionsMatchBuild() {
        let ids = Set(LegalContent.privacySections.map(\.id))
        XCTAssertEqual(ids.contains("usage-stats"), FeedbackSender.isAvailable, "不上报的版本不能写匿名使用统计")
        XCTAssertEqual(ids.contains("feedback"), FeedbackSender.isAvailable)
        XCTAssertEqual(ids.contains("feedback-offline"), !FeedbackSender.isAvailable)
        XCTAssertEqual(ids.contains("purchase"), Features.paymentsEnabled)
        XCTAssertTrue(ids.isSuperset(of: ["summary", "camera", "local", "contact"]))
        XCTAssertNotEqual(LegalContent.privacyInventoryHash, "PENDING")
    }

    func testPrivacyAndTermsTranslated() {
        // 小节文字是 LocalizedStringKey，取不出原文；这里抽查标题的翻译（全部文字由 make_strings.py 生成时检查）
        for lang in languages {
            XCTAssertTrue(translated("隐私", lang), "\(lang) 缺少「隐私」")
            XCTAssertTrue(translated("一句话说明", lang), "\(lang) 缺少隐私政策翻译")
            XCTAssertTrue(translated("收藏、浏览与复习记录", lang), "\(lang) 缺少隐私政策翻译")
        }
    }

    // MARK: 开源许可

    func testLicensesLoadFromBundle() {
        let items = LicensesView.items
        XCTAssertGreaterThanOrEqual(items.count, 4)
        XCTAssertTrue(items.contains { $0.name.contains("Sudachi") })
        for i in items {
            XCTAssertNotNil(URL(string: i.url), i.name)
            XCTAssertFalse(i.license.isEmpty, i.name)
        }
    }
}
