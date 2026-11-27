import XCTest
@testable import JapaneseGrammarScanner

final class LineSelectionTests: XCTestCase {
    private func flatQuad(y: CGFloat, height: CGFloat = 20, x0: CGFloat = 0, x1: CGFloat = 300) -> [CGPoint] {
        [CGPoint(x: x0, y: y), CGPoint(x: x1, y: y), CGPoint(x: x1, y: y + height), CGPoint(x: x0, y: y + height)]
    }

    private var threeLines: [[CGPoint]] {
        [flatQuad(y: 100), flatQuad(y: 130), flatQuad(y: 160)]
    }

    func testTapInsideALineSelectsThatLine() {
        let quads = threeLines

        let hit = LineSelection.line(at: CGPoint(x: 150, y: 140), quads: quads, slack: 12)

        XCTAssertEqual(hit, 1)
    }

    func testTapInTheGapPicksTheCloserLine() {
        let quads = threeLines

        let nearUpper = LineSelection.line(at: CGPoint(x: 150, y: 123), quads: quads, slack: 12)
        let nearLower = LineSelection.line(at: CGPoint(x: 150, y: 128), quads: quads, slack: 12)

        XCTAssertEqual(nearUpper, 0)
        XCTAssertEqual(nearLower, 1)
    }

    func testTapFarFromEveryLineSelectsNothing() {
        let quads = threeLines

        let hit = LineSelection.line(at: CGPoint(x: 150, y: 400), quads: quads, slack: 12)

        XCTAssertNil(hit)
    }

    func testDragFarBelowTheLastLineStillReachesIt() {
        let quads = threeLines

        let hit = LineSelection.line(at: CGPoint(x: 150, y: 400), quads: quads, slack: .infinity)

        XCTAssertEqual(hit, 2)
    }

    func testTapOnASlantedLineFollowsItsTilt() {
        let slanted = [CGPoint(x: 0, y: 140), CGPoint(x: 300, y: 80), CGPoint(x: 300, y: 100), CGPoint(x: 0, y: 160)]
        let flatBelow = flatQuad(y: 110)

        let hit = LineSelection.line(at: CGPoint(x: 290, y: 92), quads: [slanted, flatBelow], slack: 12)

        XCTAssertEqual(hit, 0)
    }

    func testEmptyPageSelectsNothing() {
        XCTAssertNil(LineSelection.line(at: CGPoint(x: 10, y: 10), quads: [], slack: .infinity))
    }

    func testDragSpanCoversEveryLineBetweenStartAndFinger() {
        XCTAssertEqual(LineSelection.span(from: 4, to: 2), [2, 3, 4])
        XCTAssertEqual(LineSelection.span(from: 2, to: 4), [2, 3, 4])
        XCTAssertEqual(LineSelection.span(from: 3, to: 3), [3])
    }

    func testNeighbouringSelectedLinesShareOneOutline() {
        let outlines = LineSelection.outlines(selected: [0, 1, 2], quads: threeLines, pad: 0)

        XCTAssertEqual(outlines.count, 1)
        let xs = outlines[0].map(\.x), ys = outlines[0].map(\.y)
        XCTAssertEqual(xs.min()!, 0, accuracy: 0.001)
        XCTAssertEqual(xs.max()!, 300, accuracy: 0.001)
        XCTAssertEqual(ys.min()!, 100, accuracy: 0.001)
        XCTAssertEqual(ys.max()!, 180, accuracy: 0.001)
    }

    func testLinesInDifferentColumnsGetSeparateOutlines() {
        let leftColumnEnd = flatQuad(y: 500, x0: 0, x1: 140)
        let rightColumnStart = flatQuad(y: 100, x0: 160, x1: 300)

        let outlines = LineSelection.outlines(selected: [0, 1], quads: [leftColumnEnd, rightColumnStart], pad: 0)

        XCTAssertEqual(outlines.count, 2)
    }

    func testSkippedLineSplitsTheOutline() {
        let outlines = LineSelection.outlines(selected: [0, 2], quads: threeLines, pad: 0)

        XCTAssertEqual(outlines.count, 2)
    }

    func testNoSelectionHasNoOutline() {
        XCTAssertTrue(LineSelection.outlines(selected: [], quads: threeLines, pad: 4).isEmpty)
    }

    func testLineQuadsUseTopLeftOrigin() {
        let line = RecognizedLine(rangeInText: NSRange(location: 0, length: 3), text: "あいう",
                                  boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1),
                                  boxForRange: { _ in nil })

        let quad = LineSelection.lineQuads([line])[0]

        XCTAssertEqual(quad[0].x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(quad[0].y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(quad[2].x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(quad[2].y, 0.3, accuracy: 0.0001)
    }

    private func pageLines() -> (text: String, lines: [RecognizedLine]) {
        let first = "地図を見ながら歩いていたら、道に迷って"
        let second = "しまった。"
        let third = "東京大阪"
        let text = first + second + "\n" + third
        func line(_ s: String, at location: Int, y: CGFloat) -> RecognizedLine {
            RecognizedLine(rangeInText: NSRange(location: location, length: (s as NSString).length), text: s,
                           boundingBox: CGRect(x: 0.1, y: y, width: 0.8, height: 0.04), boxForRange: { _ in nil })
        }
        let firstLength = (first as NSString).length
        let secondLength = (second as NSString).length
        return (text, [line(first, at: 0, y: 0.8), line(second, at: firstLength, y: 0.74),
                       line(third, at: firstLength + secondLength + 1, y: 0.68)])
    }

    func testSelectingOneLineKeepsGrammarOnThatLineAndGrammarRunningIntoTheNext() {
        let page = pageLines()
        let full = ScanAnalyzer.analyze(text: page.text, lines: page.lines, matcher: GrammarLibrary.shared.matcher)

        let firstLine = Set(full.limited(toLines: [0], of: page.lines).orderedGrammarIDs)

        XCTAssertTrue(firstLine.contains("nagara"), "\(firstLine)")
        XCTAssertTrue(firstLine.contains("te-shimau"), "跨到下一行的「てしまう」也算在第一行里：\(firstLine)")
    }

    func testSelectingTheNextLineDropsGrammarThatIsOnlyOnTheFirstLine() {
        let page = pageLines()
        let full = ScanAnalyzer.analyze(text: page.text, lines: page.lines, matcher: GrammarLibrary.shared.matcher)

        let secondLine = Set(full.limited(toLines: [1], of: page.lines).orderedGrammarIDs)

        XCTAssertTrue(secondLine.contains("te-shimau"), "\(secondLine)")
        XCTAssertFalse(secondLine.contains("nagara"), "\(secondLine)")
    }

    func testSelectingALineWithoutGrammarGivesNothing() {
        let page = pageLines()
        let full = ScanAnalyzer.analyze(text: page.text, lines: page.lines, matcher: GrammarLibrary.shared.matcher)

        let third = full.limited(toLines: [2], of: page.lines)

        XCTAssertTrue(third.matches.isEmpty, "\(third.orderedGrammarIDs)")
        XCTAssertTrue(third.clusters.isEmpty)
        XCTAssertTrue(third.boxes.isEmpty)
    }

    func testBoxesAreOnlyDrawnOnTheSelectedLines() {
        let page = pageLines()
        let full = ScanAnalyzer.analyze(text: page.text, lines: page.lines, matcher: GrammarLibrary.shared.matcher)
        XCTAssertTrue(full.boxes.contains { $0.source?.line == 1 }, "整页结果里第二行有框（「しまっ」）")

        let firstLine = full.limited(toLines: [0], of: page.lines)

        XCTAssertFalse(firstLine.boxes.isEmpty)
        XCTAssertTrue(firstLine.boxes.allSatisfy { $0.source?.line == 0 })
    }

    func testPhotosWithOneOrTwoLinesAreAnalyzedRightAway() {
        XCTAssertTrue(LineSelection.analyzesRightAway(lineCount: 1))
        XCTAssertTrue(LineSelection.analyzesRightAway(lineCount: 2))
    }

    func testPhotosWithThreeOrMoreLinesWaitForTheUserToChoose() {
        XCTAssertFalse(LineSelection.analyzesRightAway(lineCount: 3))
        XCTAssertFalse(LineSelection.analyzesRightAway(lineCount: 30))
    }
}
