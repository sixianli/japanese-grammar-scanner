import XCTest
@testable import JapaneseGrammarScanner

final class TitleBarLayoutTests: XCTestCase {
    private let safeTop: CGFloat = 103
    private let width: CGFloat = 390
    private let shortLine = CGSize(width: 150, height: 56)
    private let longLine = CGSize(width: 900, height: 56)
    private let restTags: CGFloat = 30

    private func state(_ scrolled: CGFloat, line: CGSize? = nil, width: CGFloat? = nil) -> TitleBarLayout.State {
        TitleBarLayout.state(scrolled: scrolled, lineSize: line ?? shortLine, restTagsHeight: restTags, viewWidth: width ?? self.width, safeTop: safeTop)
    }

    private func pinnedScroll(line: CGSize? = nil) -> CGFloat {
        (1...600).map(CGFloat.init).first { state($0, line: line).progress >= 1 } ?? .infinity
    }

    private var contentWidth: CGFloat { width - 2 * Theme.margin }
    private var barSpace: CGFloat { width - 2 * TitleBarLayout.barSideInset }

    func testAtRestShortTitleIsFullSizeBelowBarAndGlassHidden() {
        let s = state(0)
        XCTAssertEqual(s.titleTop, safeTop + TitleBarLayout.topPadding)
        XCTAssertEqual(s.scale, 1)
        XCTAssertEqual(s.tagsScale, 1, "没滚动时标签是页面上的大小")
        XCTAssertEqual(s.tagsTop, s.titleTop + shortLine.height + 10, accuracy: 0.001, "标签就在页面标题下方原来的位置")
        XCTAssertEqual(s.glassOpacity, 0)
    }

    func testAtRestLongTitleShrinksToOneLineInsideThePageMargins() {
        let s = state(0, line: longLine)
        XCTAssertLessThan(s.scale, 1, "太长的标题在页面上也要缩小，不折行")
        XCTAssertEqual(longLine.width * s.scale, contentWidth, accuracy: 0.5, "在一行放得下的前提下尽量大，正好占满页边距之间的宽度")
        XCTAssertLessThanOrEqual(longLine.width * s.scale, contentWidth + 0.001)
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

    func testLongTitleShrinksToFitBetweenButtonsWhenPinned() {
        let s = state(600, line: longLine)
        XCTAssertLessThan(s.scale, TitleBarLayout.maxPinnedScale, "太长的标题收进顶栏后要再缩小")
        XCTAssertEqual(longLine.width * s.scale, barSpace, accuracy: 0.5, "在一行放得下的前提下尽量大，正好占满两个圆按钮之间的宽度")
        XCTAssertLessThanOrEqual(longLine.width * s.scale, barSpace + 0.001)
        XCTAssertEqual(s.tagsTop, s.titleTop + longLine.height * s.scale + TitleBarLayout.tagsGap, accuracy: 0.001,
                       "标签行紧跟在一行标题下面，顶栏不因为标题长而变高")
    }

    func testEveryRealWorldWidthFitsOnOneLineInBothStates() {
        for lineWidth in stride(from: CGFloat(100), through: 1200, by: 50) {
            for viewWidth in [320, 375, 390, 430, 744] as [CGFloat] {
                let line = CGSize(width: lineWidth, height: 56)
                let rest = state(0, line: line, width: viewWidth)
                let pinned = state(800, line: line, width: viewWidth)
                XCTAssertLessThanOrEqual(lineWidth * rest.scale, viewWidth - 2 * Theme.margin + 0.001, "展开时一行宽度不超过页边距之间：\(lineWidth) / \(viewWidth)")
                XCTAssertLessThanOrEqual(lineWidth * pinned.scale, viewWidth - 2 * TitleBarLayout.barSideInset + 0.001, "收起时一行宽度不超过两个圆按钮之间：\(lineWidth) / \(viewWidth)")
                XCTAssertLessThanOrEqual(pinned.scale, rest.scale, "收起后不会比展开时大")
            }
        }
    }

    func testPinnedTitleAndTagsSitCenteredInNavBarRow() {
        let s = state(400)
        let group = shortLine.height * TitleBarLayout.maxPinnedScale + TitleBarLayout.tagsGap + TitleBarLayout.tagsHeight
        let barCenter = safeTop - TitleBarLayout.navBarHeight / 2
        let expectedTop = max(safeTop - TitleBarLayout.navBarHeight + 2, barCenter - group / 2)
        XCTAssertEqual(s.titleTop, expectedTop, accuracy: 0.5, "标题和标签行在导航栏那一行居中，太高时贴着状态栏下沿")
        XCTAssertLessThanOrEqual(abs(s.titleTop + group / 2 - barCenter), 5, "停住的位置离导航栏正中不超过几 pt")
        XCTAssertEqual(s.tagsTop, s.titleTop + shortLine.height * TitleBarLayout.maxPinnedScale + TitleBarLayout.tagsGap, accuracy: 0.001)
        XCTAssertEqual(restTags * s.tagsScale, TitleBarLayout.tagsHeight, accuracy: 0.001, "收进顶栏后标签缩到顶栏标签行的高度")
        XCTAssertEqual(s.glassOpacity, 1)
        XCTAssertEqual(state(800).titleTop, s.titleTop, "停住以后再往下滑，标题不再移动")
    }

    func testGlassCoversPinnedTitleAndTags() {
        for line in [shortLine, longLine] {
            let s = state(600, line: line)
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
        XCTAssertEqual(s.tagsScale, 1)
    }

    func testTagsShrinkTogetherWithTitleAsOneSet() {
        let end = pinnedScroll()
        var lastScale = state(0).tagsScale
        var distinct = Set<Int>()
        for scrolled in stride(from: CGFloat(1), through: end, by: 1) {
            let s = state(scrolled)
            let titleBottom = s.titleTop + shortLine.height * s.scale
            XCTAssertLessThanOrEqual(s.tagsScale, lastScale, "标签跟着标题一起越滑越小")
            XCTAssertGreaterThanOrEqual(s.tagsTop, titleBottom + TitleBarLayout.tagsGap - 0.001, "标签始终在标题下面，不和标题重叠")
            XCTAssertLessThanOrEqual(s.tagsTop, titleBottom + 10 + 0.001, "标签紧跟标题，不落在后面")
            distinct.insert(Int(s.tagsScale * 1000))
            lastScale = s.tagsScale
        }
        XCTAssertGreaterThan(distinct.count, 10, "标签是渐渐缩小的，不是换成另一组")
    }

    func testBeforeMeasuringTitleKeepsDefaults() {
        XCTAssertEqual(TitleBarLayout.expandedScale(lineWidth: 0, contentWidth: 350), 1)
        XCTAssertEqual(TitleBarLayout.pinnedScale(lineWidth: 0, viewWidth: 390), TitleBarLayout.maxPinnedScale)
        XCTAssertEqual(TitleBarLayout.pinnedTagsScale(restTagsHeight: 0), 1)
    }
}
