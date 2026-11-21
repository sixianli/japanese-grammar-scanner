import XCTest
@testable import JapaneseGrammarScanner

/// 讲解页标题飞进导航栏的几何。Build 16 反馈：途中出现两个标题（大标题和导航栏小标题交叉淡入），不够跟手。
/// 现在始终只有一个标题，位置只由它在滚动视图里的位置决定（每帧直接算，不依赖上一帧的状态）。
final class FlyingTitleLayoutTests: XCTestCase {
    // iPhone 竖屏：导航栏下沿 106，标题在其下 8pt；标题 220×52
    let restY: CGFloat = 114
    let size = CGSize(width: 220, height: 52)
    let width: CGFloat = 402
    let margin: CGFloat = 20

    private func t(scrolled: CGFloat) -> FlyingTitleLayout.TitleTransform {
        FlyingTitleLayout.titleTransform(minY: restY - scrolled, restY: restY, size: size, width: width, margin: margin)
    }

    func testAtRestTitleIsUntouched() {
        XCTAssertEqual(t(scrolled: 0), .init(offsetX: 0, offsetY: 0, scale: 1, progress: 0))
        // 下拉回弹：不缩放、不平移，跟着内容往下走
        let pulled = t(scrolled: -30)
        XCTAssertEqual(pulled.scale, 1)
        XCTAssertEqual(pulled.offsetY, 0)
    }

    /// 跟手：到达导航栏之前，标题的屏幕位置随滚动连续变化，没有跳变
    func testMovesContinuouslyWithScroll() {
        var lastY = CGFloat.infinity, lastScale: CGFloat = 1.01
        for s in stride(from: CGFloat(0), through: 200, by: 1) {
            let r = t(scrolled: s)
            let screenY = (restY - s) + r.offsetY
            XCTAssertLessThanOrEqual(screenY, lastY + 0.001, "往上滚时标题不应往下跳（滚动 \(s)）")
            XCTAssertLessThanOrEqual(r.scale, lastScale + 0.001)
            if lastY.isFinite { XCTAssertLessThanOrEqual(lastY - screenY, 1.001, "每滚 1pt 标题最多移动 1pt（滚动 \(s)）") }
            lastY = screenY
            lastScale = r.scale
        }
    }

    /// 停在导航栏正中：水平居中、垂直中线对齐导航栏中线，之后继续滚也不动
    func testEndsCenteredInNavigationBarAndStays() {
        let end = FlyingTitleLayout.endScale(size: size, width: width)
        for s: CGFloat in [150, 400, 2000] {
            let r = t(scrolled: s)
            XCTAssertEqual(r.progress, 1)
            XCTAssertEqual(r.scale, end, accuracy: 0.0001)
            let left = margin + r.offsetX
            XCTAssertEqual(left + size.width * end / 2, width / 2, accuracy: 0.5, "应水平居中")
            let top = (restY - s) + r.offsetY
            let barCenter = restY - FlyingTitleLayout.topPadding - FlyingTitleLayout.barHeight / 2
            XCTAssertEqual(top + size.height * end / 2, barCenter, accuracy: 0.5, "应对齐导航栏中线")
        }
    }

    /// 太长的标题缩得更小，给左右按钮留出位置
    func testLongTitleLeavesRoomForButtons() {
        let long = CGSize(width: 900, height: 52)
        let end = FlyingTitleLayout.endScale(size: long, width: width)
        XCTAssertLessThanOrEqual(long.width * end, width - 150 + 0.5)
    }

    /// 导航栏底色固定在屏幕顶端，标题开始进入导航栏时淡入
    func testBarBackgroundPinnedAndFadesIn() {
        XCTAssertEqual(FlyingTitleLayout.barTransform(minY: restY, restY: restY).opacity, 0)
        let mid = FlyingTitleLayout.barTransform(minY: restY - 20, restY: restY)
        XCTAssertEqual(mid.offsetY, -(restY - 20), "底色抵消滚动，固定在顶端")
        XCTAssertGreaterThan(mid.opacity, 0)
        XCTAssertEqual(FlyingTitleLayout.barTransform(minY: restY - 80, restY: restY).opacity, 1)
    }
}
