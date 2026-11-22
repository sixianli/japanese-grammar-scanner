import XCTest
import UIKit
@testable import JapaneseGrammarScanner

final class SakuraTests: XCTestCase {
    private let row = CGSize(width: 360, height: 52)

    func testDriftHasFlowersAndPetalsAndLastsAboutFourSeconds() {
        let kinds = SakuraDrift.particles.map(\.kind)
        XCTAssertEqual(kinds.filter { $0 == .flower }.count, 4)
        XCTAssertEqual(kinds.filter { $0 == .petal }.count, 4)
        XCTAssertEqual(SakuraDrift.duration, 4, accuracy: 0.5)
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

    func testBellRingsFirstThenStops() {
        XCTAssertNotEqual(SakuraDrift.bellAngle(elapsed: 0.06), 0)
        XCTAssertEqual(SakuraDrift.bellAngle(elapsed: 1.0), 0)
        XCTAssertEqual(SakuraDrift.bellAngle(elapsed: -1), 0, "没在播放时铃铛不动")
        XCTAssertGreaterThan(SakuraDrift.particles.map(\.delay).min() ?? 0, 0.2)
    }

    func testDecorativeMotionSwitch() {
        XCTAssertTrue(DecorativeMotion.enabled(reduceMotion: false, arguments: []))
        XCTAssertFalse(DecorativeMotion.enabled(reduceMotion: true, arguments: []))
        XCTAssertFalse(DecorativeMotion.enabled(reduceMotion: false, arguments: ["-e2e"]))
        XCTAssertTrue(DecorativeMotion.enabled(reduceMotion: false, arguments: ["-e2e", "-playAnimations"]))
        XCTAssertFalse(DecorativeMotion.enabled(reduceMotion: true, arguments: ["-e2e", "-playAnimations"]))
    }

    func testReviewMotionReplaysWhenAppComesBackFromBackground() {
        var replay = ForegroundReplay()
        XCTAssertFalse(replay.shouldReplay(on: .inactive))
        XCTAssertFalse(replay.shouldReplay(on: .background))
        XCTAssertFalse(replay.shouldReplay(on: .inactive))
        XCTAssertTrue(replay.shouldReplay(on: .active))
        XCTAssertFalse(replay.shouldReplay(on: .active))
    }

    func testReviewMotionDoesNotReplayForControlCenterOrNotifications() {
        var replay = ForegroundReplay()
        XCTAssertFalse(replay.shouldReplay(on: .inactive))
        XCTAssertFalse(replay.shouldReplay(on: .active))
    }

    func testReviewMotionStartsAfterLaunchTransition() {
        XCTAssertGreaterThanOrEqual(SakuraDrift.appearDelay, 0.5)
        XCTAssertEqual(SakuraDrift.bellAngle(elapsed: -SakuraDrift.appearDelay / 2), 0)
    }

    func testFlowerShapeFitsItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        let b = SakuraFlowerShape().path(in: rect).boundingRect
        XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(b), "樱花不应超出方框：\(b)")
        XCTAssertGreaterThan(b.width, 30)
    }

    // MARK: 收藏时樱花飘进「收藏」标签

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

    func testPouchTurnsPinkOnlyAfterFlowerArrives() {
        let flower = FlightPath.particles(.intoPouch).first { $0.kind == .flower }!
        XCTAssertGreaterThan(FlightPath.arrival(.intoPouch) - 0.15, flower.delay + flower.duration * 0.9, "樱花快落进袋子时袋子才变粉")
        XCTAssertGreaterThan(FlightPath.glow, 0.5)
        XCTAssertEqual(FlightPath.total(.intoPouch), FlightPath.arrival(.intoPouch) + FlightPath.glow, accuracy: 0.001)
    }

    func testReviewFlightFloatsAwayFromButtonWithoutTabBar() {
        let parts = FlightPath.particles(.away)
        XCTAssertEqual(parts.filter { $0.kind == .flower }.count, 1)
        XCTAssertEqual(parts.filter { $0.kind == .petal }.count, 2)
        XCTAssertEqual(FlightPath.total(.away), FlightPath.arrival(.away), "复习页没有标签栏，不等袋子变粉")
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
        let pink = try XCTUnwrap(UIImage(named: "KinchakuPink"))
        XCTAssertEqual(pink.size, icon.size, "变粉的图标和原图标一样大，换图时不跳动")
    }

    func testOnlyFavoritingLaunches() {
        XCTAssertTrue(FavoriteFlight.shouldLaunch(wasFavorite: false, reduceMotion: false, arguments: []))
        XCTAssertFalse(FavoriteFlight.shouldLaunch(wasFavorite: true, reduceMotion: false, arguments: []))
        XCTAssertFalse(FavoriteFlight.shouldLaunch(wasFavorite: false, reduceMotion: true, arguments: []))
    }
}
