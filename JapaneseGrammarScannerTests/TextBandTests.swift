import CoreGraphics
import XCTest
@testable import JapaneseGrammarScanner

/// 弯曲书页：整行四边形很高，文字只占其中一条带子，框要收紧到那条带子上
final class TextBandTests: XCTestCase {
    /// 400×200 的白图，在 y = 60（原点左上）画一行 20 个 14px 的黑块当作字
    private func page(glyphY: CGFloat) -> CGImage {
        let w = 400, h = 200
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 0, alpha: 1)
        for i in 0..<20 {
            let x = 20 + CGFloat(i) * 18 + 2
            ctx.fill(CGRect(x: x, y: CGFloat(h) - glyphY - 7, width: 14, height: 14))
        }
        return ctx.makeImage()!
    }

    /// 整行四边形：x 20…380，y 40…120（原点左上），转成 Vision 坐标
    private func tallLine() -> RecognizedLine {
        func v(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 400, y: 1 - y / 200) }
        let quad = [v(20, 40), v(380, 40), v(380, 120), v(20, 120)]
        return RecognizedLine(rangeInText: NSRange(location: 0, length: 20), text: String(repeating: "あ", count: 20),
                              boundingBox: CGRect(x: 0.05, y: 0.4, width: 0.9, height: 0.4),
                              boxForRange: { _ in nil }, quad: quad, quadForRange: { _ in nil })
    }

    func testBandFollowsTheInk() {
        var lines = [tallLine()]
        TextBandFinder.refine(&lines, image: page(glyphY: 60))
        let band = try! XCTUnwrap(lines[0].band)
        // 字在四边形上边往下 (60 - 40) / 80 = 0.25 处
        for t in [0.1, 0.5, 0.9] as [CGFloat] {
            XCTAssertEqual(band.center(at: t), 0.25, accuracy: 0.06)
        }
        XCTAssertEqual(band.glyph, 18.0 / 80.0, accuracy: 0.03)
    }

    func testBoxIsTightenedToTheBand() {
        var lines = [tallLine()]
        TextBandFinder.refine(&lines, image: page(glyphY: 60))
        // 第 6～8 个字
        let q = ScanAnalyzer.substringQuad(line: lines[0], local: NSRange(location: 5, length: 3))
        let topY = (1 - q[0].y) * 200, bottomY = (1 - q[3].y) * 200
        XCTAssertEqual((topY + bottomY) / 2, 60, accuracy: 6, "框的中心应在字上")
        XCTAssertLessThan(bottomY - topY, 30, "框高应接近字高（约 1.2 倍），而不是整行四边形的 80")
    }

    func testTightLineIsLeftAlone() {
        func v(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 400, y: 1 - y / 200) }
        let quad = [v(20, 50), v(380, 50), v(380, 70), v(20, 70)]
        var lines = [RecognizedLine(rangeInText: NSRange(location: 0, length: 20), text: String(repeating: "あ", count: 20),
                                    boundingBox: CGRect(x: 0.05, y: 0.65, width: 0.9, height: 0.1),
                                    boxForRange: { _ in nil }, quad: quad, quadForRange: { _ in nil })]
        TextBandFinder.refine(&lines, image: page(glyphY: 60))
        XCTAssertNil(lines[0].band)
    }
}
