import XCTest
@testable import JapaneseGrammarScanner

/// 「必考」标签（Build 17 反馈 4）：只给出题频率最高一档的语法显示。
/// 频率资料里明显标错的几条（について 等 N3 常考语法被标成「低」）修正后不能再回去。
final class MustKnowTests: XCTestCase {
    func testCommonlyTestedN3GrammarIsMustKnow() {
        let lib = GrammarLibrary(language: .zhHans)
        for id in ["ni-tsuite", "kara-ni-kakete", "wo-chuushin-ni", "dake-de-naku"] {
            XCTAssertEqual(lib.point(id: id)?.frequency, .high, "\(id) 是常考语法，应显示「必考」")
        }
        for id in ["kke", "tatte", "ttara"] {
            XCTAssertEqual(lib.point(id: id)?.frequency, .medium, "\(id) 不该标成很少考")
        }
    }

    /// 「必考」只占一部分：不是所有语法都显示（否则标签就没有意义了）
    func testOnlyAPartOfGrammarIsMustKnow() {
        let lib = GrammarLibrary(language: .zhHans)
        let high = lib.points.filter { $0.frequency == .high }.count
        XCTAssertGreaterThan(high, 0)
        XCTAssertLessThan(Double(high) / Double(lib.points.count), 0.5, "「必考」不应超过一半的语法")
    }
}
