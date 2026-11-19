import XCTest
@testable import JapaneseGrammarScanner

final class TextAssemblyTests: XCTestCase {
    func testForeignDetection() {
        XCTAssertTrue(JapaneseText.isForeign("night market"))
        XCTAssertTrue(JapaneseText.isForeign("야시장"))
        XCTAssertTrue(JapaneseText.isForeign("表示以某物为基准的上、下、里、外。日语必须加"), "中文整句没有假名")
        XCTAssertFalse(JapaneseText.isForeign("日本語を勉強する"))
        XCTAssertFalse(JapaneseText.isForeign("4 〜とは限らない"))
        XCTAssertFalse(JapaneseText.isForeign("夜市"), "很短的汉字词无法区分中日文，保留")
        XCTAssertFalse(JapaneseText.isForeign("123"))
    }

    func testMaskKeepsPositions() {
        let line = "夜市：night market／夜市／야시장"
        let masked = JapaneseText.maskForeignSegments(line)
        XCTAssertEqual((masked as NSString).length, (line as NSString).length, "替换后长度不变，框的位置才不会错")
        XCTAssertTrue(masked.hasPrefix("夜市："))
        XCTAssertFalse(masked.contains("night"))
        XCTAssertFalse(masked.contains("야"))
    }

    func testContinuation() {
        // Vision 坐标：原点左下。两行相邻、上一行写满 → 折行续写
        let p = CGRect(x: 0.1, y: 0.60, width: 0.8, height: 0.03)
        XCTAssertTrue(TextRecognizer.isContinuation(previous: p, next: CGRect(x: 0.1, y: 0.56, width: 0.5, height: 0.03)))
        // 上一行很短（标题）→ 不相连
        let heading = CGRect(x: 0.1, y: 0.60, width: 0.2, height: 0.03)
        XCTAssertFalse(TextRecognizer.isContinuation(previous: heading, next: CGRect(x: 0.1, y: 0.56, width: 0.8, height: 0.03)))
        // 隔得很远 → 不相连
        XCTAssertFalse(TextRecognizer.isContinuation(previous: p, next: CGRect(x: 0.1, y: 0.40, width: 0.8, height: 0.03)))
    }

    func testCutOffNeighborLine() {
        // 贴着左边缘、字比正文大很多：邻页入镜
        XCTAssertTrue(TextRecognizer.isCutOffNeighbor(CGRect(x: 0, y: 0.9, width: 0.1, height: 0.06), bodyHeight: 0.025))
        // 贴边但字号与正文相同：正文被截断的一行，保留
        XCTAssertFalse(TextRecognizer.isCutOffNeighbor(CGRect(x: 0, y: 0.5, width: 0.6, height: 0.026), bodyHeight: 0.025))
        // 不贴边：保留
        XCTAssertFalse(TextRecognizer.isCutOffNeighbor(CGRect(x: 0.2, y: 0.5, width: 0.3, height: 0.06), bodyHeight: 0.025))
    }
}
