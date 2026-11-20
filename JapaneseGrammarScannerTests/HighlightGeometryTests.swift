import XCTest
@testable import JapaneseGrammarScanner

/// 高亮虚线框的几何：四周略放宽；同一行挨着的两个框之间留出固定的细缝；不在同一行的不受影响。
final class HighlightGeometryTests: XCTestCase {
    /// 横排的一段文字：x 从 x0 到 x1，y 从 y 到 y+20（视图坐标）
    private func quad(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat = 100) -> [CGPoint] {
        [CGPoint(x: x0, y: y), CGPoint(x: x1, y: y), CGPoint(x: x1, y: y + 20), CGPoint(x: x0, y: y + 20)]
    }

    func testSingleBoxIsPaddedSlightly() {
        let out = HighlightGeometry.layout([quad(10, 60)])[0]
        XCTAssertEqual(out[0].x, 8, accuracy: 0.01)
        XCTAssertEqual(out[0].y, 98, accuracy: 0.01)
        XCTAssertEqual(out[2].x, 62, accuracy: 0.01)
        XCTAssertEqual(out[2].y, 122, accuracy: 0.01)
    }

    func testTouchingBoxesKeepAGap() {
        // 两段紧挨着（60 处相接）
        let out = HighlightGeometry.layout([quad(10, 60), quad(60, 120)])
        let gap = out[1][0].x - out[0][1].x
        XCTAssertEqual(gap, 3, accuracy: 0.01, "相邻两个框之间应留 3pt 的缝")
        XCTAssertEqual(out[0][1].x, out[0][2].x, accuracy: 0.01, "右边两个角一起移动，边仍是直的")
        XCTAssertEqual(out[1][0].x, out[1][3].x, accuracy: 0.01)
        // 外侧的边不受影响
        XCTAssertEqual(out[0][0].x, 8, accuracy: 0.01)
        XCTAssertEqual(out[1][1].x, 122, accuracy: 0.01)
    }

    func testGapScalesWhenZoomed() {
        let out = HighlightGeometry.layout([quad(10, 60), quad(60, 120)], unit: 0.5)
        XCTAssertEqual(out[1][0].x - out[0][1].x, 1.5, accuracy: 0.01)
    }

    func testBoxesOnDifferentLinesAreUntouched() {
        let out = HighlightGeometry.layout([quad(10, 60, y: 100), quad(60, 120, y: 200)])
        XCTAssertEqual(out[0][1].x, 62, accuracy: 0.01)
        XCTAssertEqual(out[1][0].x, 58, accuracy: 0.01)
    }

    func testFarApartBoxesAreUntouched() {
        let out = HighlightGeometry.layout([quad(10, 60), quad(100, 150)])
        XCTAssertEqual(out[0][1].x, 62, accuracy: 0.01)
        XCTAssertEqual(out[1][0].x, 98, accuracy: 0.01)
    }
}
