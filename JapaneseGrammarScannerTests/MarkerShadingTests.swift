import XCTest
@testable import JapaneseGrammarScanner

/// 荧光笔样式：挨在一起的两段语法用不同深浅；离得远的不受影响；两端收进一点留缝
final class MarkerShadingTests: XCTestCase {
    /// 一行字里横向的一段：x 从 x0 到 x1（归一化），y 0.50…0.52
    private func box(_ cluster: Int, _ x0: CGFloat, _ x1: CGFloat, y: CGFloat = 0.5) -> HighlightBox {
        let quad = [CGPoint(x: x0, y: y), CGPoint(x: x1, y: y), CGPoint(x: x1, y: y + 0.02), CGPoint(x: x0, y: y + 0.02)]
        return HighlightBox(clusterID: cluster, rect: CGRect(x: x0, y: y, width: x1 - x0, height: 0.02), quad: quad)
    }

    private func result(_ boxes: [HighlightBox]) -> ScanResult {
        ScanResult(text: "", matches: [], clusters: [], boxes: boxes)
    }

    func testAdjacentClustersAlternate() {
        // 0 和 1 紧挨着，1 和 2 紧挨着，3 在别的行
        let r = result([box(0, 0.10, 0.20), box(1, 0.20, 0.30), box(2, 0.305, 0.40), box(3, 0.10, 0.20, y: 0.80)])
        let shades = MarkerShading.shades(for: r, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertNotEqual(shades[0], shades[1])
        XCTAssertNotEqual(shades[1], shades[2])
        XCTAssertEqual(shades[3], 0, "不挨着别的块，用默认的主题色")
    }

    func testShortenedLeavesGap() {
        let p = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 20), CGPoint(x: 0, y: 20)]
        let s = MarkerShading.shortened(p)
        XCTAssertEqual(s[0].x, 2.8, accuracy: 0.01)   // 0.14 × 字高 20
        XCTAssertEqual(s[1].x, 97.2, accuracy: 0.01)
        XCTAssertEqual(s[2].y, 20, accuracy: 0.01)
    }
}
