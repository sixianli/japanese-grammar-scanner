import XCTest
@testable import JapaneseGrammarScanner

/// 讲解页标题栏的几何。Build 17 反馈 1：标题要在正中、字号不缩小、长标题两行、跟手地移到正中。
final class TitleBarLayoutTests: XCTestCase {
    private let oneLine = TitleBarLayout.barContentHeight(titleBlockHeight: 22 + 2 + 16)
    private let twoLines = TitleBarLayout.barContentHeight(titleBlockHeight: 44 + 2 + 16)

    func testBarIsAtLeastNavigationBarHighAndGrowsForTwoLines() {
        XCTAssertEqual(TitleBarLayout.barContentHeight(titleBlockHeight: 10), TitleBarLayout.navBarHeight)
        XCTAssertGreaterThan(twoLines, oneLine, "两行标题时标题栏要变高，而不是缩小字号")
        XCTAssertEqual(twoLines, 44 + 2 + 16 + 2 * TitleBarLayout.barVerticalPadding)
    }

    func testPageTitleStartsBelowATallerBar() {
        XCTAssertEqual(TitleBarLayout.headerTopPadding(barContentHeight: TitleBarLayout.navBarHeight), TitleBarLayout.topPadding)
        XCTAssertEqual(TitleBarLayout.headerTopPadding(barContentHeight: twoLines),
                       twoLines - TitleBarLayout.navBarHeight + TitleBarLayout.topPadding,
                       "没滚动时，页面标题不能被变高的标题栏盖住")
    }

    func testAtRestBarTitleIsHiddenBelowTheBar() {
        for bar in [oneLine, twoLines] {
            XCTAssertEqual(TitleBarLayout.titleOffset(scrolled: 0, barContentHeight: bar), bar)
            XCTAssertEqual(TitleBarLayout.titleOffset(scrolled: -40, barContentHeight: bar), bar, "下拉回弹时也不出现")
        }
        XCTAssertEqual(TitleBarLayout.dividerOpacity(scrolled: 0), 0)
    }

    /// 跟手：页面标题碰到标题栏下沿之后，每滚 1pt，标题栏里的标题上移 1pt，没有跳变
    func testFollowsScrollOneToOne() {
        let bar = twoLines
        var last = TitleBarLayout.titleOffset(scrolled: 0, barContentHeight: bar)
        for s in stride(from: CGFloat(1), through: 300, by: 1) {
            let now = TitleBarLayout.titleOffset(scrolled: s, barContentHeight: bar)
            XCTAssertLessThanOrEqual(now, last + 0.0001, "往上滚时标题不应往下走（滚动 \(s)）")
            XCTAssertLessThanOrEqual(last - now, 1.0001, "每滚 1pt 最多移动 1pt（滚动 \(s)）")
            if s > TitleBarLayout.topPadding && s <= TitleBarLayout.topPadding + bar {
                XCTAssertEqual(last - now, 1, accuracy: 0.0001, "这一段应该一比一跟手（滚动 \(s)）")
            }
            last = now
        }
    }

    /// 移到正中后停住，继续滚也不动；往回滚时按原路返回
    func testStopsCenteredAndReverses() {
        let bar = oneLine
        let end = TitleBarLayout.topPadding + bar
        for s: CGFloat in [end, end + 100, 5000] {
            XCTAssertEqual(TitleBarLayout.titleOffset(scrolled: s, barContentHeight: bar), 0)
        }
        let mid = TitleBarLayout.topPadding + bar / 2
        XCTAssertEqual(TitleBarLayout.titleOffset(scrolled: mid, barContentHeight: bar), bar / 2, accuracy: 0.0001)
        XCTAssertEqual(TitleBarLayout.dividerOpacity(scrolled: end), 1)
    }
}
