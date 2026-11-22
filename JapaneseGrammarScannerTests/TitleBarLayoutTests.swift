import XCTest
@testable import JapaneseGrammarScanner

final class TitleBarLayoutTests: XCTestCase {
    private let safeTop: CGFloat = 103
    private let width: CGFloat = 390
    private let oneLine = CGSize(width: 200, height: 56)
    private let longLine = CGSize(width: 900, height: 56)

    private func state(_ scrolled: CGFloat, title: CGFloat = 56, line: CGSize? = nil, width: CGFloat? = nil) -> TitleBarLayout.State {
        TitleBarLayout.state(scrolled: scrolled, titleHeight: title, lineSize: line ?? oneLine,
                             containerWidth: width ?? self.width, safeTop: safeTop)
    }

    private func pinnedScroll(line: CGSize? = nil) -> CGFloat {
        (1...600).map(CGFloat.init).first { state($0, line: line).progress >= 1 } ?? .infinity
    }

    private var barSpace: CGFloat { width - 2 * TitleBarLayout.barSideInset }

    func testAtRestTitleIsFullSizeBelowBarAndGlassHidden() {
        let s = state(0)
        XCTAssertEqual(s.titleTop, safeTop + TitleBarLayout.topPadding)
        XCTAssertEqual(s.scale, 1)
        XCTAssertEqual(s.tagsOpacity, 0)
        XCTAssertEqual(s.glassOpacity, 0)
    }

    func testTitleFollowsFingerOneToOneUntilPinned() {
        let end = pinnedScroll()
        for scrolled in stride(from: CGFloat(0), to: end, by: 2) {
            XCTAssertEqual(state(scrolled).titleTop, safeTop + TitleBarLayout.topPadding - scrolled, accuracy: 0.001)
        }
    }

    func testTitleShrinksGraduallyWhileMovingUp() {
        let end = pinnedScroll()
        var last = state(0).scale
        var distinct = Set<Int>()
        for scrolled in stride(from: CGFloat(1), through: end, by: 1) {
            let s = state(scrolled).scale
            XCTAssertLessThanOrEqual(s, last, "滑得越多标题越小，不回弹")
            distinct.insert(Int(s * 1000))
            last = s
        }
        XCTAssertGreaterThan(distinct.count, 10, "缩小是渐进的，不是一下子跳过去")
        XCTAssertEqual(last, TitleBarLayout.maxPinnedScale, accuracy: 0.001)
    }

    func testShortTitleKeepsUsualPinnedSize() {
        XCTAssertEqual(state(400).scale, TitleBarLayout.maxPinnedScale, accuracy: 0.001, "放得下一行的标题，顶栏里还是原来的大小")
    }

    func testLongTitleShrinksToFitOneLineBetweenButtons() {
        let s = state(600, title: 112, line: longLine)
        XCTAssertLessThan(s.scale, TitleBarLayout.maxPinnedScale, "太长的标题要再缩小")
        XCTAssertLessThanOrEqual(longLine.width * s.scale, barSpace + 0.001, "缩小后一行宽度不超过两个圆按钮之间的空间")
        XCTAssertEqual(longLine.width * s.scale, barSpace, accuracy: 0.5, "在一行放得下的前提下尽量大")
        XCTAssertEqual(s.lineOpacity, 1, "收进顶栏后只显示一行的标题")
        XCTAssertEqual(s.tagsTop, s.titleTop + longLine.height * s.scale + TitleBarLayout.tagsGap, accuracy: 0.001,
                       "标签行紧跟在一行标题下面，顶栏不因为标题长而变高")
    }

    func testWrappedTitleCrossFadesToOneLine() {
        XCTAssertEqual(state(0, title: 112, line: longLine).lineOpacity, 0, "页面上折成两行时，开始只显示两行的大标题")
        XCTAssertEqual(state(600, title: 112, line: longLine).lineOpacity, 1)
        XCTAssertEqual(state(0).lineOpacity, 1, "本来就是一行的标题不用换")
    }

    func testPinnedTitleAndTagsSitCenteredInNavBarRow() {
        let s = state(400)
        let group = oneLine.height * TitleBarLayout.maxPinnedScale + TitleBarLayout.tagsGap + TitleBarLayout.tagsHeight
        let barCenter = safeTop - TitleBarLayout.navBarHeight / 2
        let expectedTop = max(safeTop - TitleBarLayout.navBarHeight + 2, barCenter - group / 2)
        XCTAssertEqual(s.titleTop, expectedTop, accuracy: 0.5, "标题和标签行在导航栏那一行居中，太高时贴着状态栏下沿")
        XCTAssertLessThanOrEqual(abs(s.titleTop + group / 2 - barCenter), 5, "停住的位置离导航栏正中不超过几 pt")
        XCTAssertEqual(s.tagsTop, s.titleTop + oneLine.height * TitleBarLayout.maxPinnedScale + TitleBarLayout.tagsGap, accuracy: 0.001)
        XCTAssertEqual(s.tagsOpacity, 1)
        XCTAssertEqual(s.glassOpacity, 1)
        XCTAssertEqual(state(800).titleTop, s.titleTop, "停住以后再往下滑，标题不再移动")
    }

    func testGlassCoversPinnedTitleAndTags() {
        for line in [oneLine, longLine] {
            let s = state(600, title: 112, line: line)
            XCTAssertGreaterThanOrEqual(s.glassBottom, s.tagsTop + TitleBarLayout.tagsHeight, "毛玻璃要盖住标题和标签行")
            XCTAssertGreaterThanOrEqual(s.glassBottom, safeTop, "毛玻璃至少盖到导航栏下沿")
            XCTAssertGreaterThanOrEqual(s.titleTop, safeTop - TitleBarLayout.navBarHeight, "标题不顶进状态栏")
        }
    }

    func testPullDownBounceKeepsTitleFullSizeAndFollowing() {
        let s = state(-40)
        XCTAssertEqual(s.scale, 1)
        XCTAssertEqual(s.titleTop, safeTop + TitleBarLayout.topPadding + 40)
        XCTAssertEqual(s.glassOpacity, 0)
        XCTAssertEqual(s.tagsOpacity, 0)
    }

    func testTagsFadeInOnlyNearTheEnd() {
        let end = pinnedScroll()
        XCTAssertEqual(state(end * 0.5).tagsOpacity, 0, "滑到一半时顶栏里的标签还不出现（页面上已有标签）")
        XCTAssertGreaterThan(state(end * 0.9).tagsOpacity, 0)
    }
}
