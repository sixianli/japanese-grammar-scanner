import XCTest
@testable import JapaneseGrammarScanner

final class HomeAndLibraryLayoutTests: XCTestCase {
    func testSampleLinkOnlyBeforeFirstScan() {
        XCTAssertTrue(HomeLayout.showsSampleLink(scanCount: 0))
        XCTAssertFalse(HomeLayout.showsSampleLink(scanCount: 1))
        XCTAssertFalse(HomeLayout.showsSampleLink(scanCount: 40))
    }

    func testLevelFilterFollowsPullDownLikeSearchField() {
        XCTAssertEqual(LibraryHeader.pullOffset(scrolled: -40), 40, "往下拉 40 pt，筛选条跟着搜索框一起往下 40 pt")
        XCTAssertEqual(LibraryHeader.pullOffset(scrolled: 0), 0, "不拉时在原位")
        XCTAssertEqual(LibraryHeader.pullOffset(scrolled: 300), 0, "往上滑时固定在顶部，不跟着走")
    }
}
