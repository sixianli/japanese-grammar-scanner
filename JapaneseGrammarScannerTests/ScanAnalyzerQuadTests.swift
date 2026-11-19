import XCTest
@testable import JapaneseGrammarScanner

/// 斜拍时 Vision 给的单段框太高：框的高度要沿用整行四边形，左右位置沿用 Vision
final class ScanAnalyzerQuadTests: XCTestCase {
    /// 一行向右上倾斜的文字（Vision 坐标，原点左下）：左端底边 y=0.50，右端底边 y=0.60，字高 0.02
    private func slantedLine(vision: [CGPoint]) -> RecognizedLine {
        let quad = [CGPoint(x: 0.1, y: 0.52), CGPoint(x: 0.9, y: 0.62), CGPoint(x: 0.9, y: 0.60), CGPoint(x: 0.1, y: 0.50)]
        return RecognizedLine(rangeInText: NSRange(location: 0, length: 10), text: "あいうえおかきくけこ",
                              boundingBox: CGRect(x: 0.1, y: 0.50, width: 0.8, height: 0.12),
                              boxForRange: { _ in nil }, quad: quad, quadForRange: { _ in vision })
    }

    func testTallVisionQuadIsFittedToLineHeight() {
        // Vision 给的「かき」（第 6、7 个字）：左右位置对，但高度 0.06，是字高的 3 倍
        let tall = [CGPoint(x: 0.5, y: 0.60), CGPoint(x: 0.66, y: 0.62), CGPoint(x: 0.66, y: 0.56), CGPoint(x: 0.5, y: 0.54)]
        let line = slantedLine(vision: tall)
        let q = ScanAnalyzer.substringQuad(line: line, local: NSRange(location: 5, length: 2))
        XCTAssertEqual(q.count, 4)
        // 左右边的高度 = 整行字高 0.02
        XCTAssertEqual(q[0].y - q[3].y, 0.02, accuracy: 0.002)
        XCTAssertEqual(q[1].y - q[2].y, 0.02, accuracy: 0.002)
        // 左右位置沿用 Vision
        XCTAssertEqual(q[0].x, 0.5, accuracy: 0.005)
        XCTAssertEqual(q[1].x, 0.66, accuracy: 0.005)
        // 跟着行倾斜：x=0.5 处底边 y = 0.50 + 0.1 × 0.5 = 0.55
        XCTAssertEqual(q[3].y, 0.55, accuracy: 0.003)
    }

    func testVerticalLineKeepsVisionQuad() {
        let quad = [CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.52, y: 0.9), CGPoint(x: 0.52, y: 0.1), CGPoint(x: 0.5, y: 0.1)]
        let line = RecognizedLine(rangeInText: NSRange(location: 0, length: 10), text: "あいうえおかきくけこ",
                                  boundingBox: CGRect(x: 0.5, y: 0.1, width: 0.02, height: 0.8),
                                  boxForRange: { _ in nil }, quad: quad, quadForRange: { _ in nil })
        XCTAssertNil(ScanAnalyzer.fittedToLine(quad, line: line))
    }

    /// 超过五分之一的正文行「一个行框里夹着两三行字」时，判断为书页弯曲较大
    func testCurvedPageDetection() {
        func line(curved: Bool) -> RecognizedLine {
            var l = RecognizedLine(rangeInText: NSRange(location: 0, length: 10), text: "あいうえおかきくけこ",
                                   boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.05),
                                   boxForRange: { _ in nil })
            if curved {
                l.band = TextBand(glyph: 0.3, ts: [0.25, 0.75], centers: [0.5, 0.5], raw: [0.5, 0.5])
            }
            return l
        }
        let flat = (0..<10).map { _ in line(curved: false) }
        XCTAssertFalse(ScanAnalyzer.pageIsCurved(flat))
        XCTAssertFalse(ScanAnalyzer.pageIsCurved(flat.prefix(9) + [line(curved: true)]), "十行里一行弯不算")
        XCTAssertTrue(ScanAnalyzer.pageIsCurved(flat.prefix(7) + (0..<3).map { _ in line(curved: true) }))
    }
}
