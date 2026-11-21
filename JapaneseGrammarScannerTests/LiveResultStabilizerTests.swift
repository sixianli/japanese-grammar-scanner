import XCTest
@testable import JapaneseGrammarScanner

final class LiveResultStabilizerTests: XCTestCase {
    private func frame(_ items: [(String, CGRect)]) -> ScanResult {
        let clusters = items.enumerated().map { HighlightCluster(id: $0, range: NSRange(location: $0, length: 1), grammarIDs: [$1.0]) }
        let boxes = items.enumerated().map { HighlightBox(clusterID: $0, rect: $1.1) }
        let matches = items.enumerated().map { GrammarMatch(grammarID: $1.0, range: NSRange(location: $0, length: 1)) }
        return ScanResult(text: "", matches: matches, clusters: clusters, boxes: boxes)
    }

    func testAppearsAfterTwoFramesAndDisappearsAfterThreeMisses() {
        let s = LiveResultStabilizer()
        let a = CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.03)
        XCTAssertTrue(s.update(frame([("a", a)])).boxes.isEmpty, "只出现一帧不显示")
        XCTAssertEqual(s.update(frame([("a", a)])).boxes.count, 1)
        XCTAssertEqual(s.update(frame([])).boxes.count, 1, "漏识别一帧仍保留")
        XCTAssertEqual(s.update(frame([])).boxes.count, 1)
        XCTAssertTrue(s.update(frame([])).boxes.isEmpty, "连续 3 帧没识别到才消失")
    }

    func testIntermittentDetectionStillShows() {
        let s = LiveResultStabilizer()
        let a = CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.03)
        XCTAssertTrue(s.update(frame([("a", a)])).boxes.isEmpty)
        XCTAssertTrue(s.update(frame([])).boxes.isEmpty)
        XCTAssertEqual(s.update(frame([("a", a)])).boxes.count, 1, "时有时无（隔帧识别到）也稳定显示")
        XCTAssertEqual(s.update(frame([])).boxes.count, 1)
    }

    func testSameBoxKeepsIDAndIgnoresJitter() {
        let s = LiveResultStabilizer()
        let a = CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.03)
        _ = s.update(frame([("a", a)]))
        let first = s.update(frame([("a", a)])).boxes[0]
        let shaken = s.update(frame([("a", a.offsetBy(dx: 0.004, dy: -0.003))])).boxes[0]
        XCTAssertEqual(first.id, shaken.id)
        XCTAssertEqual(shaken.rect, a, "微小抖动不移动框")
        let moved = s.update(frame([("a", a.offsetBy(dx: 0.05, dy: 0))])).boxes[0]
        XCTAssertEqual(first.id, moved.id, "明显移动时仍是同一个框（平滑移动）")
        XCTAssertEqual(moved.rect.minX, 0.15, accuracy: 1e-6)
    }

    func testChipOrderStaysStable() {
        let s = LiveResultStabilizer()
        let a = CGRect(x: 0.1, y: 0.5, width: 0.1, height: 0.03)
        let b = CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.03)
        _ = s.update(frame([("a", a)]))
        XCTAssertEqual(s.update(frame([("a", a)])).orderedGrammarIDs, ["a"])
        _ = s.update(frame([("b", b), ("a", a)]))
        // b 在画面上方，但后出现：排在 a 后面，不打乱已有顺序
        XCTAssertEqual(s.update(frame([("b", b), ("a", a)])).orderedGrammarIDs, ["a", "b"])
    }
}
