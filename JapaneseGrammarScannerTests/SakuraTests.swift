import XCTest
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

    func testFlightIsOneShortArc() {
        let kinds = FlightPath.particles.map(\.kind)
        XCTAssertEqual(kinds.filter { $0 == .flower }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == .petal }.count, 3)
        XCTAssertEqual(FlightPath.arrival, 1.2, accuracy: 0.2)
        XCTAssertLessThan(FlightPath.total, 1.8)
    }

    func testFlightStartsAtButtonAndEndsInPouch() {
        for p in FlightPath.particles {
            let a = try! XCTUnwrap(FlightPath.state(p, elapsed: p.delay, from: from, to: to))
            let b = try! XCTUnwrap(FlightPath.state(p, elapsed: p.delay + FlightPath.flight, from: from, to: to))
            XCTAssertEqual(a.point.x, from.x, accuracy: 0.5)
            XCTAssertEqual(a.point.y, from.y, accuracy: 0.5)
            XCTAssertEqual(b.point.x, to.x, accuracy: 0.5)
            XCTAssertEqual(b.point.y, to.y, accuracy: 0.5)
            var lastY = -CGFloat.infinity
            for k in 0...20 {
                let e = p.delay + FlightPath.flight * Double(k) / 20
                let s = try! XCTUnwrap(FlightPath.state(p, elapsed: e, from: from, to: to))
                XCTAssertGreaterThanOrEqual(s.point.y, lastY - 0.5, "一直往下飘，不往回走")
                lastY = s.point.y
            }
            XCTAssertLessThan(b.scale, a.scale, "越接近袋子越小")
            XCTAssertNil(FlightPath.state(p, elapsed: p.delay + FlightPath.flight + 0.01, from: from, to: to), "到了就消失")
        }
    }

    func testPouchPuffsOnArrival() {
        XCTAssertNil(FlightPath.puffScale(elapsed: 0.2), "还没到时不鼓")
        let peak = (0...40).compactMap { FlightPath.puffScale(elapsed: FlightPath.arrival - 0.2 + Double($0) * 0.01) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.15)
        XCTAssertNil(FlightPath.puffScale(elapsed: FlightPath.total + 0.1), "鼓完就不显示")
    }

    func testOnlyFavoritingLaunches() {
        XCTAssertTrue(FavoriteFlight.shouldLaunch(wasFavorite: false, reduceMotion: false, arguments: []))
        XCTAssertFalse(FavoriteFlight.shouldLaunch(wasFavorite: true, reduceMotion: false, arguments: []))
        XCTAssertFalse(FavoriteFlight.shouldLaunch(wasFavorite: false, reduceMotion: true, arguments: []))
    }
}
