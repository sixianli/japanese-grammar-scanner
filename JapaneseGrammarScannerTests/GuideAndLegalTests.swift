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

    /// 使用指南只讲核心功能（Build 17 反馈 3）：每个核心功能一张卡片（标题 + 一句话），其它功能没有卡片
    func testCoreFeaturesHaveGuideCards() {
        XCTAssertEqual(AppFeature.core, [.scan, .scanResult, .detail, .contrast, .review])
        for f in AppFeature.allCases {
            if AppFeature.core.contains(f) {
                let c = f.card
                XCTAssertNotNil(c, "核心功能 \(f) 缺少指南卡片")
                XCTAssertFalse(c?.title.isEmpty ?? true, "\(f) 缺少卡片标题")
                XCTAssertFalse(c?.line.isEmpty ?? true, "\(f) 缺少一句话说明")
                XCTAssertLessThanOrEqual(c?.line.count ?? 0, 30, "\(f) 的说明要一句话说完")
            } else {
                XCTAssertNil(f.card, "非核心功能 \(f) 不放进使用指南")
            }
        }
    }

    func testGuideIsTranslatedIntoEveryLanguage() {
        var keys: [String] = ["使用指南"]
        for f in AppFeature.core {
            if let c = f.card { keys += [c.title, c.line] }
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
