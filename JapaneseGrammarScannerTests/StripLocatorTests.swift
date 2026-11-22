import CoreGraphics
import XCTest
@testable import JapaneseGrammarScanner

/// 分条识别重新定位：在竖条的识别结果里找同一段文字
final class StripLocatorTests: XCTestCase {
    private let size = CGSize(width: 1000, height: 1000)

    /// 一行横排文字：每个字 20×20 像素，左上角在 (x, top)（像素，原点左上），换算成 Vision 坐标
    private func line(_ text: String, x: CGFloat, top: CGFloat, x0: CGFloat = 0, x1: CGFloat = 1) -> StripLocator.Line {
        let n = CGFloat(text.utf16.count)
        func p(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: px / 1000, y: 1 - py / 1000) }
        return StripLocator.Line(
            utf16: Array(text.utf16),
            quad: [p(x, top), p(x + 20 * n, top), p(x + 20 * n, top + 20), p(x, top + 20)],
            quadFor: { r in
                let a = x + 20 * CGFloat(r.location), b = a + 20 * CGFloat(r.length)
                return [p(a, top), p(b, top), p(b, top + 20), p(a, top + 20)]
            },
            looseness: 1.2, x0: x0, x1: x1)
    }

    private func centerPixel(_ q: [CGPoint]) -> CGPoint {
        let c = StripLocator.center(q)
        return CGPoint(x: c.x * 1000, y: (1 - c.y) * 1000)
    }

    /// 同一段文字在相邻两行都出现时，按前后文选对的那一行（即使原来的框更靠近另一行）
    func testContextPicksTheRightLine() {
        let text = Array("疲れたという声を聞くことも少なく".utf16)
        let range = NSRange(location: 10, length: 2)  // こと
        let pool = [
            line("毎日やることがたくさんある", x: 300, top: 100),   // こと 在第 3 个字
            line("という声を聞くことも少なく", x: 200, top: 130),
        ]
        // 原来的框落在上一行（第一行的 こと 附近）
        let prior = CGPoint(x: 0.35, y: 1 - 0.11)
        let q = StripLocator.bestCandidate(text, range, prior: prior, in: pool, size: size)
        XCTAssertNotNil(q)
        XCTAssertEqual(centerPixel(q!.quad).y, 140, accuracy: 0.5, "应选前后文一致的第二行")
    }

    /// 前后文太少的短片段不重新定位（可能是别处的同一个词）
    func testShortKeyWithoutContextIsRejected() {
        let text = Array("ことも".utf16)
        let pool = [line("やることが", x: 300, top: 100)]
        let q = StripLocator.bestCandidate(text, NSRange(location: 0, length: 2), prior: CGPoint(x: 0.35, y: 0.89), in: pool, size: size)
        XCTAssertNil(q)
    }

    /// 离原来的框太远（超过 3.5 个字高）的不用
    func testFarAwayMatchIsRejected() {
        let text = Array("という声を聞くことも少なく".utf16)
        let pool = [line("という声を聞くことも少なく", x: 200, top: 600)]
        let q = StripLocator.bestCandidate(text, NSRange(location: 7, length: 2), prior: CGPoint(x: 0.35, y: 0.86), in: pool, size: size)
        XCTAssertNil(q)
    }

    /// OCR 两次读得不一样（错了一个字）时，4 个字以上的片段仍能找到
    func testOneMisreadCharacterIsTolerated() {
        let text = Array("グルメ番組で紹がされています。".utf16)
        let range = NSRange(location: 7, length: 7)  // がされています
        let pool = [line("グルメ番組で紹介されています。", x: 100, top: 300)]
        let prior = CGPoint(x: (100 + 20 * 10.5) / 1000, y: 1 - 0.312)
        let q = StripLocator.bestCandidate(text, range, prior: prior, in: pool, size: size)
        XCTAssertNotNil(q)
    }

    /// 被竖条边界切到的字不用
    func testCharactersAtStripEdgeAreIgnored() {
        let text = Array("という声を聞くことも少なく".utf16)
        // 竖条右边界在 こと 的右边缘
        let l = line("という声を聞くこと", x: 200, top: 300, x0: 0.1, x1: 0.38)
        let q = StripLocator.bestCandidate(text, NSRange(location: 7, length: 2), prior: CGPoint(x: 0.36, y: 0.69), in: [l], size: size)
        XCTAssertNil(q)
    }
}
