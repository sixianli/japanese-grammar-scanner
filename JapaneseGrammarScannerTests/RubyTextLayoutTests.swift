import XCTest
@testable import JapaneseGrammarScanner

final class RubyTextLayoutTests: XCTestCase {
    func testRubyFitsInsideTheLineGapSoRubyLinesAreNotTaller() {
        let style = RubyText.Style(font: .body, rubySize: 8, lineSpacing: 4)
        XCTAssertGreaterThanOrEqual(RubyText.lineGap(style), RubyText.rubyLine(style), "注音放在行间空隙里，有注音的行不另外加高")
    }

    func testWideLineSpacingIsKept() {
        let style = RubyText.Style(font: .body, rubySize: 8, lineSpacing: 30)
        XCTAssertEqual(RubyText.lineGap(style), 30, "行距本来就比注音高时保持原来的行距")
    }

    func testBiggerRubyGetsBiggerGap() {
        let small = RubyText.Style(font: .body, rubySize: 8, lineSpacing: 2)
        let big = RubyText.Style(font: .body, rubySize: 12, lineSpacing: 2)
        XCTAssertGreaterThan(RubyText.lineGap(big), RubyText.lineGap(small))
    }
}
