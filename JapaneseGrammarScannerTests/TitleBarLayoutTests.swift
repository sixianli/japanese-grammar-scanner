import XCTest
@testable import JapaneseGrammarScanner

final class TitleBarLayoutTests: XCTestCase {
    private let safeTop: CGFloat = 103
    private let oneLine: CGFloat = 56
    private let twoLines: CGFloat = 100

    private func state(_ scrolled: CGFloat, title: CGFloat = 56) -> TitleBarLayout.State {
        TitleBarLayout.state(scrolled: scrolled, titleHeight: title, safeTop: safeTop)
    }

    private var pinnedScroll: CGFloat {
        (1...600).map(CGFloat.init).first { state($0).progress >= 1 } ?? .infinity
    }

    func testAtRestTitleIsFullSizeBelowBarAndGlassHidden() {
        let s = state(0)
        XCTAssertEqual(s.titleTop, safeTop + TitleBarLayout.topPadding)
        XCTAssertEqual(s.scale, 1)
        XCTAssertEqual(s.levelOpacity, 0)
        XCTAssertEqual(s.glassOpacity, 0)
    }

    func testTitleFollowsFingerOneToOneUntilPinned() {
        let end = pinnedScroll
        for scrolled in stride(from: CGFloat(0), to: end, by: 2) {
            XCTAssertEqual(state(scrolled).titleTop, safeTop + TitleBarLayout.topPadding - scrolled, accuracy: 0.001)
        }
    }

    func testTitleShrinksGraduallyWhileMovingUp() {
        let end = pinnedScroll
        var last = state(0).scale
        var distinct = Set<Int>()
        for scrolled in stride(from: CGFloat(1), through: end, by: 1) {
            let s = state(scrolled).scale
            XCTAssertLessThanOrEqual(s, last, "滑得越多标题越小，不回弹")
            distinct.insert(Int(s * 1000))
            last = s
        }
        XCTAssertGreaterThan(distinct.count, 10, "缩小是渐进的，不是一下子跳过去")
        XCTAssertEqual(last, TitleBarLayout.pinnedScale, accuracy: 0.001)
    }

    func testPinnedTitleAndLevelSitCenteredInNavBarRow() {
        let s = state(400)
        let group = oneLine * TitleBarLayout.pinnedScale + TitleBarLayout.levelGap + TitleBarLayout.levelHeight
        let barCenter = safeTop - TitleBarLayout.navBarHeight / 2
        let expectedTop = max(safeTop - TitleBarLayout.navBarHeight + 2, barCenter - group / 2)
        XCTAssertEqual(s.titleTop, expectedTop, accuracy: 0.5, "标题和等级在导航栏那一行居中，太高时贴着状态栏下沿")
        XCTAssertLessThanOrEqual(abs(s.titleTop + group / 2 - barCenter), 4, "停住的位置离导航栏正中不超过几 pt")
        XCTAssertEqual(s.levelTop, s.titleTop + oneLine * TitleBarLayout.pinnedScale + TitleBarLayout.levelGap, accuracy: 0.001)
        XCTAssertEqual(s.levelOpacity, 1)
        XCTAssertEqual(s.glassOpacity, 1)
        XCTAssertEqual(state(800).titleTop, s.titleTop, "停住以后再往下滑，标题不再移动")
    }

    func testGlassCoversPinnedTitleAndLevel() {
        for title in [oneLine, twoLines] {
            let s = state(600, title: title)
            XCTAssertGreaterThanOrEqual(s.glassBottom, s.levelTop + TitleBarLayout.levelHeight, "毛玻璃要盖住标题和等级")
            XCTAssertGreaterThanOrEqual(s.glassBottom, safeTop, "毛玻璃至少盖到导航栏下沿")
            XCTAssertGreaterThanOrEqual(s.titleTop, safeTop - TitleBarLayout.navBarHeight, "两行标题也不顶进状态栏")
        }
    }

    func testPullDownBounceKeepsTitleFullSizeAndFollowing() {
        let s = state(-40)
        XCTAssertEqual(s.scale, 1)
        XCTAssertEqual(s.titleTop, safeTop + TitleBarLayout.topPadding + 40)
        XCTAssertEqual(s.glassOpacity, 0)
        XCTAssertEqual(s.levelOpacity, 0)
    }

    func testLevelFadesInOnlyNearTheEnd() {
        let end = pinnedScroll
        XCTAssertEqual(state(end * 0.5).levelOpacity, 0, "滑到一半时等级还不出现（页面上已有等级标签）")
        XCTAssertGreaterThan(state(end * 0.9).levelOpacity, 0)
    }
}
