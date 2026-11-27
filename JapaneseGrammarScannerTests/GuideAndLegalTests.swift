import XCTest
@testable import JapaneseGrammarScanner

final class GuideAndLegalTests: XCTestCase {
    private let languages = ["en", "ko", "es", "vi", "my", "zh-Hant"]

    private func bundle(_ lang: String) -> Bundle? {
        Bundle.main.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private func translated(_ key: String, _ lang: String) -> Bool {
        guard let b = bundle(lang) else { return false }
        let v = b.localizedString(forKey: key, value: "\u{0}", table: nil)
        if v == "\u{0}" { return false }
        if lang == "zh-Hant" { return true }
        return v != key
    }

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

    func testEveryTabBelongsToAFeature() {
        for tab in AppTab.all {
            XCTAssertNotNil(AppTab.feature(of: tab), "标签 \(tab) 没有归到任何功能")
        }
    }

    func testTermsFollowPaymentSetting() {
        let ids = LegalContent.termsSections.map(\.id)
        XCTAssertEqual(ids.contains("purchase"), Features.paymentsEnabled, "开启购买时条款里要有购买条目，没开就不能有")
        XCTAssertTrue(ids.contains("eula") && ids.contains("content"))
    }

    func testPrivacySectionsMatchBuild() {
        let ids = Set(LegalContent.privacySections.map(\.id))
        XCTAssertEqual(ids.contains("usage-stats"), FeedbackSender.isAvailable, "不上报的版本不能写匿名使用统计")
        XCTAssertEqual(ids.contains("feedback"), FeedbackSender.isAvailable)
        XCTAssertEqual(ids.contains("feedback-offline"), !FeedbackSender.isAvailable)
        XCTAssertEqual(ids.contains("purchase"), Features.paymentsEnabled)
        XCTAssertTrue(ids.isSuperset(of: ["summary", "camera", "local", "lookup", "contact"]), "长按日文可以用系统翻译，隐私政策要写明")
        XCTAssertNotEqual(LegalContent.privacyInventoryHash, "PENDING")
    }

    func testPrivacyAndTermsTranslated() {
        for lang in languages {
            XCTAssertTrue(translated("隐私", lang), "\(lang) 缺少「隐私」")
            XCTAssertTrue(translated("一句话说明", lang), "\(lang) 缺少隐私政策翻译")
            XCTAssertTrue(translated("收藏、浏览与复习记录", lang), "\(lang) 缺少隐私政策翻译")
        }
    }

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
