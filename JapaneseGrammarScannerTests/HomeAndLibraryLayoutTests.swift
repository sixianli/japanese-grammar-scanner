import XCTest
@testable import JapaneseGrammarScanner

final class HomeAndLibraryLayoutTests: XCTestCase {
    func testSampleLinkOnlyBeforeFirstScan() {
        XCTAssertTrue(HomeLayout.showsSampleLink(scanCount: 0))
        XCTAssertFalse(HomeLayout.showsSampleLink(scanCount: 1))
        XCTAssertFalse(HomeLayout.showsSampleLink(scanCount: 40))
    }

    func testLibraryHeaderGlassAppearsOnlyAfterScrolling() {
        XCTAssertEqual(LibraryHeader.glassOpacity(scrolled: 0), 0)
        XCTAssertEqual(LibraryHeader.glassOpacity(scrolled: -30), 0, "下拉回弹时不出现")
        XCTAssertEqual(LibraryHeader.glassOpacity(scrolled: LibraryHeader.glassFadeDistance / 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(LibraryHeader.glassOpacity(scrolled: 500), 1)
    }
}
