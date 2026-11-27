import XCTest
import UIKit
@testable import JapaneseGrammarScanner

final class SakuraTests: XCTestCase {
    private let row = CGSize(width: 360, height: 52)

    func testDriftHasBigFlowersAndPetalsAndLastsAboutThreeAndAHalfSeconds() {
        let flowers = SakuraDrift.particles.filter { $0.kind == .flower }.map(\.size)
        let petals = SakuraDrift.particles.filter { $0.kind == .petal }.map(\.size)
        XCTAssertEqual(flowers, [27, 20, 23, 17], "樱花再大一点（Build 25 反馈 6）")
        XCTAssertEqual(petals, [14, 12, 15, 12], "花瓣画大一点（Build 25 反馈 6）")
        XCTAssertEqual(SakuraDrift.duration, 3.42, accuracy: 0.05)
    }

    func testDriftIsTwentyPercentFasterThanBefore() {
        XCTAssertEqual(SakuraDrift.travel, 2.17, accuracy: 0.01, "飘过一行原来要 2.6 秒，提速 20% 后约 2.17 秒")
    }

    func testFirstFlowerDriftsInTogetherWithNumberRoll() {
        XCTAssertEqual(SakuraDrift.particles.map(\.delay).min(), 0, "樱花和数字滚动同时开始，不等数字滚完")
        let row = CGSize(width: 360, height: 64)
        let first = SakuraDrift.particles[0]
        XCTAssertNotNil(SakuraDrift.state(first, elapsed: 0.1, in: row), "数字刚开始滚时第一朵樱花已经出现")
        XCTAssertLessThan(ReviewNudge.shownCount(target: 25, elapsed: 0.1), 25, "这时数字还在滚")
    }

    func testDriftGoesLeftToRightAndEnds() {
        for p in SakuraDrift.particles {
            XCTAssertNil(SakuraDrift.state(p, elapsed: p.delay - 0.01, in: row), "出发前不显示")
            let begin = try! XCTUnwrap(SakuraDrift.state(p, elapsed: p.delay, in: row))
            let mid = try! XCTUnwrap(SakuraDrift.state(p, elapsed: p.delay + SakuraDrift.travel / 2, in: row))
            let end = try! XCTUnwrap(SakuraDrift.state(p, elapsed: p.delay + SakuraDrift.travel, in: row))
            XCTAssertLessThan(begin.x, 0, "从左边外面进来")
            XCTAssertGreaterThan(end.x, row.width, "飘出右边")
            XCTAssertGreaterThan(mid.x, begin.x)
            XCTAssertEqual(begin.opacity, 0, accuracy: 0.01, "进来时淡入")
            XCTAssertEqual(mid.opacity, 1, accuracy: 0.01)
            XCTAssertTrue((-10...row.height + 10).contains(mid.y), "在这一行的高度范围里")
            XCTAssertNil(SakuraDrift.state(p, elapsed: SakuraDrift.duration + 0.01, in: row), "飘完就不再显示")
        }
    }

    func testDecorativeMotionSwitch() {
        XCTAssertTrue(DecorativeMotion.enabled(reduceMotion: false, arguments: []))
        XCTAssertFalse(DecorativeMotion.enabled(reduceMotion: true, arguments: []))
        XCTAssertFalse(DecorativeMotion.enabled(reduceMotion: false, arguments: ["-e2e"]))
        XCTAssertTrue(DecorativeMotion.enabled(reduceMotion: false, arguments: ["-e2e", "-playAnimations"]))
        XCTAssertFalse(DecorativeMotion.enabled(reduceMotion: true, arguments: ["-e2e", "-playAnimations"]))
    }

    func testNudgePlaysOnColdLaunchButNotWhenComingBackToHome() {
        let schedule = ReviewNudgeSchedule()
        XCTAssertTrue(schedule.takeTurn(), "打开 App 时提醒一次")
        XCTAssertFalse(schedule.takeTurn(), "从别的页面返回首页不再提醒")
    }

    func testNudgeDoesNotReplayAfterShortTimeInBackground() {
        let schedule = ReviewNudgeSchedule()
        _ = schedule.takeTurn()
        let left = Date(timeIntervalSince1970: 1_000_000)
        schedule.sceneChanged(to: .inactive, now: left)
        schedule.sceneChanged(to: .background, now: left)
        schedule.sceneChanged(to: .inactive, now: left.addingTimeInterval(29 * 60))
        schedule.sceneChanged(to: .active, now: left.addingTimeInterval(29 * 60))
        XCTAssertFalse(schedule.takeTurn(), "离开不到 30 分钟切回来不提醒")
    }

    func testNudgeReplaysOnceAfterThirtyMinutesInBackground() {
        let schedule = ReviewNudgeSchedule()
        _ = schedule.takeTurn()
        let left = Date(timeIntervalSince1970: 1_000_000)
        schedule.sceneChanged(to: .background, now: left)
        schedule.sceneChanged(to: .active, now: left.addingTimeInterval(30 * 60))
        XCTAssertTrue(schedule.takeTurn(), "离开 30 分钟后切回来提醒一次")
        XCTAssertFalse(schedule.takeTurn(), "只提醒一次")
    }

    func testNudgeIgnoresControlCenterAndNotifications() {
        let schedule = ReviewNudgeSchedule()
        _ = schedule.takeTurn()
        let now = Date(timeIntervalSince1970: 1_000_000)
        schedule.sceneChanged(to: .inactive, now: now)
        schedule.sceneChanged(to: .active, now: now.addingTimeInterval(3600))
        XCTAssertFalse(schedule.takeTurn(), "只是拉下控制中心，没有进后台，不提醒")
    }

    func testNumberRollsFromZeroToCount() {
        XCTAssertEqual(ReviewNudge.shownCount(target: 25, elapsed: -0.3), 0, "开始前显示 0")
        XCTAssertEqual(ReviewNudge.shownCount(target: 25, elapsed: 0), 0)
        let mid = ReviewNudge.shownCount(target: 25, elapsed: 0.3)
        XCTAssertTrue((1...24).contains(mid), "滚动中途在 0 和 25 之间：\(mid)")
        XCTAssertEqual(ReviewNudge.shownCount(target: 25, elapsed: 0.8), 25)
        XCTAssertEqual(ReviewNudge.shownCount(target: 25, elapsed: .infinity), 25, "不播放时直接显示数量")
    }

    func testGlowHoldsThenFadesOut() {
        XCTAssertEqual(ReviewNudge.glowOpacity(elapsed: -0.1), 0)
        XCTAssertEqual(ReviewNudge.glowOpacity(elapsed: 0.3), 1)
        XCTAssertEqual(ReviewNudge.glowOpacity(elapsed: 1.35), 0.5, accuracy: 0.01)
        XCTAssertEqual(ReviewNudge.glowOpacity(elapsed: 2.0), 0, "约 2 秒后完全消失")
    }

    func testReduceMotionKeepsOnlyHaptic() {
        XCTAssertEqual(ReviewNudge.plan(reduceMotion: true, arguments: []), .init(haptic: true, motion: false))
        XCTAssertEqual(ReviewNudge.plan(reduceMotion: false, arguments: []), .init(haptic: true, motion: true))
    }

    func testReviewMotionStartsAfterLaunchTransition() {
        XCTAssertGreaterThanOrEqual(SakuraDrift.appearDelay, 0.5)
    }

    func testFlowerShapeFitsItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        let b = SakuraFlowerShape().path(in: rect).boundingRect
        XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(b), "樱花不应超出方框：\(b)")
        XCTAssertGreaterThan(b.width, 30)
    }

    private let from = CGPoint(x: 360, y: 60)
    private let to = CGPoint(x: 250, y: 800)

    func testPouchFlightIsOneBigFlowerWithThreePetalsAndSlow() {
        let kinds = FlightPath.particles(.intoPouch).map(\.kind)
        XCTAssertEqual(kinds.filter { $0 == .flower }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .petal }.count, 3)
        XCTAssertGreaterThanOrEqual(FlightPath.flowerSize, 36, "樱花要大到看得清是樱花（Build 19 反馈 4）")
        for p in FlightPath.particles(.intoPouch) where p.kind == .petal {
            XCTAssertGreaterThanOrEqual(p.size, 15, "花瓣也要看得清")
        }
        let flower = FlightPath.particles(.intoPouch).first { $0.kind == .flower }!
        XCTAssertGreaterThanOrEqual(flower.duration, 1.8, "落得慢一点，看得清（Build 19 反馈 4）")
        XCTAssertLessThan(FlightPath.total(.intoPouch), 4.5, "整段不能拖太久")
    }

    func testPouchFlightStartsAtButtonAndEndsInPouch() {
        for p in FlightPath.particles(.intoPouch) {
            let a = try! XCTUnwrap(FlightPath.state(p, style: .intoPouch, elapsed: p.delay, from: from, to: to))
            let b = try! XCTUnwrap(FlightPath.state(p, style: .intoPouch, elapsed: p.delay + p.duration, from: from, to: to))
            XCTAssertEqual(a.point.x, from.x, accuracy: 0.5)
            XCTAssertEqual(a.point.y, from.y, accuracy: 0.5)
            XCTAssertEqual(b.point.x, to.x, accuracy: 0.5)
            XCTAssertEqual(b.point.y, to.y, accuracy: 0.5)
            XCTAssertEqual(b.opacity, 0, accuracy: 0.001, "落进袋子时淡出")
            var lastY = -CGFloat.infinity
            for k in 0...40 {
                let e = p.delay + p.duration * Double(k) / 40
                let s = try! XCTUnwrap(FlightPath.state(p, style: .intoPouch, elapsed: e, from: from, to: to))
                XCTAssertGreaterThanOrEqual(s.point.y, lastY - 0.5, "一直往下飘，不往回走")
                lastY = s.point.y
            }
            XCTAssertNil(FlightPath.state(p, style: .intoPouch, elapsed: p.delay + p.duration + 0.01, from: from, to: to), "到了就消失")
        }
    }

    func testFlowerGrowsFromButtonSizeThenShrinksIntoPouch() {
        let flower = FlightPath.particles(.intoPouch).first { $0.kind == .flower }!
        func scale(_ f: Double) -> CGFloat {
            FlightPath.state(flower, style: .intoPouch, elapsed: flower.duration * f, from: from, to: to)!.scale
        }
        XCTAssertEqual(scale(0), FlightPath.buttonScale, accuracy: 0.001, "从按钮大小开始")
        XCTAssertEqual(scale(0.12), 1, accuracy: 0.01, "先放大到完整大小")
        XCTAssertGreaterThan(scale(0.5), 0.85, "大部分路程都保持大朵")
        XCTAssertLessThan(scale(1), 0.5, "落进袋子时变小")
    }

    func testPouchDipsOnlyAfterFlowerArrives() {
        let flower = FlightPath.particles(.intoPouch).first { $0.kind == .flower }!
        XCTAssertGreaterThan(FlightPath.arrival(.intoPouch) - 0.15, flower.delay + flower.duration * 0.9, "樱花快落进袋口时袋子才往下一沉")
        XCTAssertEqual(FlightPath.total(.intoPouch), FlightPath.arrival(.intoPouch) + FlightPath.landing, accuracy: 0.001)
    }

    func testPouchDipSquashesAboutTenPercentThenSettles() {
        let start = PouchDip.scale(progress: 0), middle = PouchDip.scale(progress: 0.5), end = PouchDip.scale(progress: 1)

        XCTAssertEqual(start.y, 1, accuracy: 0.001)
        XCTAssertEqual(middle.y, 0.9, accuracy: 0.01, "最低时压扁约 10%")
        XCTAssertGreaterThan(middle.x, 1, "压扁时横向略微变宽")
        XCTAssertEqual(end.y, 1, accuracy: 0.001, "最后回到原样")
        XCTAssertEqual(end.x, 1, accuracy: 0.001)
        XCTAssertLessThan(PouchDip.duration, 0.5, "动作要短")
    }

    func testLandingPointIsThePouchMouthNotTheIconCenter() {
        let icon = CGRect(x: 280, y: 780, width: 28, height: 28)

        let mouth = TabBarLocator.mouth(ofIcon: icon)

        XCTAssertEqual(mouth.x, 294, accuracy: 0.001, "横向对准图标正中")
        XCTAssertEqual(mouth.y, 787, accuracy: 0.001, "纵向落在图标上沿往下约 1/4，也就是袋口")
    }

    func testEstimatedMouthUsesTheFourthOfFiveTabs() {
        let bar = CGRect(x: 0, y: 761, width: 400, height: 49)

        let mouth = TabBarLocator.estimatedMouth(tabBar: bar, tabCount: 5, index: 3)

        XCTAssertEqual(mouth.x, 280, accuracy: 0.001, "5 个标签时收藏在第 4 格正中（70%），不是旧的 62%")
        XCTAssertLessThan(mouth.y, bar.midY, "落在标签图标的上半部")
    }

    func testReviewFlightFloatsAwayFromButtonWithoutTabBar() {
        let parts = FlightPath.particles(.away)
        XCTAssertEqual(parts.filter { $0.kind == .flower }.count, 1)
        XCTAssertEqual(parts.filter { $0.kind == .petal }.count, 2)
        XCTAssertEqual(FlightPath.total(.away), FlightPath.arrival(.away), "复习页没有标签栏，不等布袋接住")
        for p in parts {
            let start = try! XCTUnwrap(FlightPath.state(p, style: .away, elapsed: p.delay, from: from, to: from))
            let end = try! XCTUnwrap(FlightPath.state(p, style: .away, elapsed: p.delay + p.duration, from: from, to: from))
            XCTAssertLessThan(end.opacity, 0.01, "飘走后淡出")
            XCTAssertLessThan(hypot(start.point.x - from.x, start.point.y - from.y), 40, "从收藏按钮附近出发")
            XCTAssertGreaterThan(hypot(end.point.x - from.x, end.point.y - from.y), 80, "飘离按钮")
            XCTAssertLessThan(end.point.y, 400, "不落到屏幕下方的自评按钮上")
        }
    }

    func testPouchIconMatchesSystemTabIconHeight() throws {
        let icon = try XCTUnwrap(UIImage(named: "Kinchaku"))
        XCTAssertEqual(icon.size.height, 28, accuracy: 0.5, "巾着标签图标按系统标签图标的高度画（Build 19 反馈 1）")
        XCTAssertNil(UIImage(named: "KinchakuPink"), "收藏时布袋不再变粉")
    }

    func testOnlyFavoritingLaunches() {
        XCTAssertTrue(FavoriteFlight.shouldLaunch(wasFavorite: false, reduceMotion: false, arguments: []))
        XCTAssertFalse(FavoriteFlight.shouldLaunch(wasFavorite: true, reduceMotion: false, arguments: []))
        XCTAssertFalse(FavoriteFlight.shouldLaunch(wasFavorite: false, reduceMotion: true, arguments: []))
    }
}
