import XCTest
@testable import JapaneseGrammarScanner

final class WordPickTests: XCTestCase {
    private let sentence = "宿題を全部やってしまった。"

    func testPressOnKanjiCompoundPicksTheWholeCompound() {
        XCTAssertEqual(WordPick.range(in: sentence, at: 4), NSRange(location: 3, length: 2), "按在「部」上，框出「全部」")
        XCTAssertEqual(WordPick.range(in: sentence, at: 0), NSRange(location: 0, length: 2), "按在「宿」上，框出「宿題」")
    }

    func testPressOnKatakanaPicksTheWholeWord() {
        XCTAssertEqual(WordPick.range(in: "ケーキを食べた", at: 1), NSRange(location: 0, length: 3), "按在长音上，框出「ケーキ」")
    }

    func testPressOnParticlePicksOnlyTheParticle() {
        XCTAssertEqual(WordPick.range(in: sentence, at: 2), NSRange(location: 2, length: 1))
    }

    func testPressOnPunctuationPicksThatMark() {
        XCTAssertEqual(WordPick.range(in: sentence, at: 12), NSRange(location: 12, length: 1))
    }

    func testWordWithFuriganaIsNeverCutInHalf() {
        let picked = WordPick.range(in: "ケーキを", unbreakable: [NSRange(location: 0, length: 4)], at: 0)
        XCTAssertEqual(picked, NSRange(location: 0, length: 4), "带注音的一组字要么整组框住，要么不框")
    }

    func testUnrelatedFuriganaGroupIsLeftAlone() {
        let picked = WordPick.range(in: sentence, unbreakable: [NSRange(location: 3, length: 2)], at: 0)
        XCTAssertEqual(picked, NSRange(location: 0, length: 2))
    }

    func testPressOutsideTheTextPicksNothing() {
        XCTAssertNil(WordPick.range(in: sentence, at: 13))
        XCTAssertNil(WordPick.range(in: sentence, at: -1))
        XCTAssertNil(WordPick.range(in: "", at: 0))
    }
}
