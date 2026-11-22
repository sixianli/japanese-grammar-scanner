import XCTest
@testable import JapaneseGrammarScanner

@MainActor
final class UsageStatsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "UsageStatsTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func make() -> UsageStats {
        let s = UsageStats(defaults: defaults)
        s.ignoresDemoMode = true
        return s
    }

    private func date(_ s: String, hour: Int = 10) -> Date {
        var c = DateComponents()
        let p = s.split(separator: "-").map { Int($0)! }
        c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    func testDateKeys() {
        XCTAssertEqual(UsageStats.dayKey(date("2026-11-19")), "2026-11-19")
        XCTAssertEqual(UsageStats.monthKey(date("2026-11-19")), "2026-11")
        XCTAssertEqual(UsageStats.weekKey(date("2026-11-19")), "2026-W47")
        // ISO 周跨年：2027-01-01 属于 2026 年第 53 周
        XCTAssertEqual(UsageStats.weekKey(date("2027-01-01")), "2026-W53")
    }

    func testFirstDayFlags() {
        let s = make()
        s.appBecameActive(now: date("2026-11-19", hour: 9))
        s.appBecameActive(now: date("2026-11-19", hour: 21))
        XCTAssertEqual(s.days.count, 1)
        let d = s.days[0]
        XCTAssertTrue(d.newInstall)
        XCTAssertTrue(d.firstInWeek)
        XCTAssertTrue(d.firstInMonth)
        XCTAssertEqual(d.sessions, 2)
        XCTAssertEqual(d.hours[9], 1)
        XCTAssertEqual(d.hours[21], 1)
        XCTAssertFalse(d.recordName.isEmpty)
    }

    func testLaterDaysOnlyFlagNewPeriods() {
        let s = make()
        s.appBecameActive(now: date("2026-11-19"))   // 周四
        s.appBecameActive(now: date("2026-11-20"))   // 同一周、同一月
        s.appBecameActive(now: date("2026-11-23"))   // 下一周、同一月
        s.appBecameActive(now: date("2026-12-01"))   // 下一月
        XCTAssertEqual(s.days.map(\.day), ["2026-11-19", "2026-11-20", "2026-11-23", "2026-12-01"])
        XCTAssertEqual(s.days.map(\.newInstall), [true, false, false, false])
        XCTAssertEqual(s.days.map(\.firstInWeek), [true, false, true, true])
        XCTAssertEqual(s.days.map(\.firstInMonth), [true, false, false, true])
        // 每天一条记录，名字互不相同（不能由此串起同一台设备）
        XCTAssertEqual(Set(s.days.map(\.recordName)).count, 4)
    }

    func testGrammarAndLevels() {
        let s = make()
        let now = date("2026-11-19")
        s.grammarViewed("te-iru", level: .n5, now: now)
        s.grammarViewed("te-iru", level: .n5, now: now)
        s.grammarViewed("ni-yotte", level: .n3, now: now)
        XCTAssertEqual(s.days.last?.grammar, ["te-iru": 2, "ni-yotte": 1])
        XCTAssertEqual(s.days.last?.levels, ["N5": 2, "N3": 1])
    }

    func testPersistsAcrossLaunches() {
        make().appBecameActive(now: date("2026-11-19"))
        let again = make()
        XCTAssertEqual(again.days.count, 1)
        again.appBecameActive(now: date("2026-11-19"))
        XCTAssertEqual(again.days.first?.sessions, 2)
        XCTAssertFalse(again.days.first?.newInstall == false, "同一天的记录保留「新安装」标记")
    }

    func testDisablingStopsRecordingAndClears() {
        let s = make()
        s.appBecameActive(now: date("2026-11-19"))
        s.isEnabled = false
        XCTAssertTrue(s.days.isEmpty)
        s.appBecameActive(now: date("2026-11-19"))
        s.grammarViewed("te-iru", level: .n5, now: date("2026-11-19"))
        XCTAssertTrue(s.days.isEmpty)
        XCTAssertFalse(make().isEnabled, "关闭状态要保存下来")
    }

    func testKeepsAtMostThirtyDays() {
        let s = make()
        let start = date("2026-09-01")
        for i in 0..<40 {
            s.appBecameActive(now: Calendar.current.date(byAdding: .day, value: i, to: start)!)
        }
        XCTAssertEqual(s.days.count, 30)
    }
}
