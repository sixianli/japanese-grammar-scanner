import Foundation
import StoreKit
#if CLOUD_FEEDBACK
import CloudKit
#endif

/// 匿名使用统计：有多少人在用（日活 / 周活 / 月活、新用户）、来自哪些国家 / 地区、什么时段在用、查得最多的语法点和等级。
///
/// 不使用任何能识别个人或设备的编号：每台设备每天只上报一条「当天的使用汇总」，
/// 并在手机本地记住「本周 / 本月是否已经报过」，据此打上「本周第一次」「本月第一次」标记——
/// 周活 = 一周内带「本周第一次」标记的记录数，月活同理；累计「新安装」标记即总用户数。
/// 数据存进开发者的 iCloud（CloudKit 公共数据库），由 .github/workflows/usage-report.yml 每周汇总发邮件。
/// 用户可在「设置 → 匿名使用统计」关闭；关闭后不再记录，也不再上报。
@MainActor
final class UsageStats: ObservableObject {
    static let shared = UsageStats()

    struct Day: Codable, Equatable {
        var day: String            // 当地日期 yyyy-MM-dd
        var week: String           // ISO 周 yyyy-Www
        var month: String          // yyyy-MM
        var recordName: String     // 这一天这条记录在云端的名字（随机，不对应任何设备信息）
        var newInstall = false
        var firstInWeek = false
        var firstInMonth = false
        var sessions = 0
        var hours = [Int](repeating: 0, count: 24)
        var grammar: [String: Int] = [:]
        var levels: [String: Int] = [:]
        var country = ""
        var language = ""
        var appVersion = ""
        var uploaded = false
    }

    private let defaults: UserDefaults
    private enum Key {
        static let enabled = "usageStats.enabled"
        static let days = "usageStats.days"
        static let installed = "usageStats.installed"
        static let lastWeek = "usageStats.lastWeek"
        static let lastMonth = "usageStats.lastMonth"
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.enabled)
            if !isEnabled { days = []; save() }
        }
    }

    /// 还没上报（或今天还会更新）的每日汇总，最多保留 30 天
    private(set) var days: [Day] = []
    /// 单元测试里关掉 e2e / 演示模式的判断
    var ignoresDemoMode = false
    private var uploadTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        if let data = defaults.data(forKey: Key.days), let saved = try? JSONDecoder().decode([Day].self, from: data) {
            days = saved
        }
    }

    // MARK: 记录

    /// App 进入前台
    func appBecameActive(now: Date = Date()) {
        guard isEnabled, ignoresDemoMode || (!DemoMode.e2e && DemoMode.screen == nil) else { return }
        var d = today(now)
        d.sessions += 1
        d.hours[Calendar.current.component(.hour, from: now)] += 1
        update(d)
        if !ignoresDemoMode { Task { await self.fillCountry() } }
    }

    /// 打开了一个语法点的讲解
    func grammarViewed(_ id: String, level: JLPTLevel, now: Date = Date()) {
        guard isEnabled, ignoresDemoMode || (!DemoMode.e2e && DemoMode.screen == nil) else { return }
        var d = today(now)
        d.grammar[id, default: 0] += 1
        d.levels[level.rawValue, default: 0] += 1
        update(d)
    }

    /// 进入后台时上报（今天的记录之后还会更新，覆盖同一条）
    func appMovedToBackground() {
        guard isEnabled else { return }
        upload()
    }

    // MARK: 内部

    private func today(_ now: Date) -> Day {
        let key = Self.dayKey(now)
        if let d = days.last, d.day == key { return d }
        var d = Day(day: key, week: Self.weekKey(now), month: Self.monthKey(now), recordName: UUID().uuidString)
        if !defaults.bool(forKey: Key.installed) {
            d.newInstall = true
            defaults.set(true, forKey: Key.installed)
        }
        if defaults.string(forKey: Key.lastWeek) != d.week {
            d.firstInWeek = true
            defaults.set(d.week, forKey: Key.lastWeek)
        }
        if defaults.string(forKey: Key.lastMonth) != d.month {
            d.firstInMonth = true
            defaults.set(d.month, forKey: Key.lastMonth)
        }
        d.language = AppLanguage.effectiveIdentifier
        d.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        days.append(d)
        if days.count > 30 { days.removeFirst(days.count - 30) }
        return d
    }

    private func update(_ d: Day) {
        var d = d
        d.uploaded = false
        if let i = days.lastIndex(where: { $0.day == d.day }) { days[i] = d } else { days.append(d) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: Key.days) }
    }

    /// App Store 的国家 / 地区（和用户付款的商店一致，以后按国家定价时直接参考）
    private func fillCountry() async {
        guard let code = await Storefront.current?.countryCode,
              let i = days.indices.last, days[i].country != code else { return }
        days[i].country = code
        save()
    }

    private func upload() {
        #if CLOUD_FEEDBACK
        uploadTask?.cancel()
        let pending = days.filter { !$0.uploaded }
        guard !pending.isEmpty, let bundleID = Bundle.main.bundleIdentifier else { return }
        uploadTask = Task {
            let container = CKContainer(identifier: "iCloud." + bundleID)
            guard (try? await container.accountStatus()) == .available else { return }
            let records = pending.map(Self.record(for:))
            do {
                _ = try await container.publicCloudDatabase.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
                let done = Set(pending.map(\.recordName))
                for i in days.indices where done.contains(days[i].recordName) { days[i].uploaded = true }
                // 只保留今天（今天的记录还会继续更新）和没传上去的
                let todayKey = Self.dayKey(Date())
                days.removeAll { $0.uploaded && $0.day != todayKey }
                save()
            } catch {
                // 下次进入后台再试
            }
        }
        #endif
    }

    #if CLOUD_FEEDBACK
    private static func record(for d: Day) -> CKRecord {
        let r = CKRecord(recordType: "UsageDay", recordID: CKRecord.ID(recordName: d.recordName))
        r["day"] = d.day
        r["week"] = d.week
        r["month"] = d.month
        r["newInstall"] = d.newInstall ? 1 : 0
        r["firstInWeek"] = d.firstInWeek ? 1 : 0
        r["firstInMonth"] = d.firstInMonth ? 1 : 0
        r["sessions"] = d.sessions
        r["hours"] = (try? String(data: JSONEncoder().encode(d.hours), encoding: .utf8)) ?? "[]"
        r["grammar"] = (try? String(data: JSONEncoder().encode(d.grammar), encoding: .utf8)) ?? "{}"
        r["levels"] = (try? String(data: JSONEncoder().encode(d.levels), encoding: .utf8)) ?? "{}"
        r["country"] = d.country
        r["language"] = d.language
        r["appVersion"] = d.appVersion
        return r
    }
    #endif

    // MARK: 日期键（用户当地时间）

    static func dayKey(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func monthKey(_ d: Date) -> String { String(dayKey(d).prefix(7)) }

    static func weekKey(_ d: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }
}
