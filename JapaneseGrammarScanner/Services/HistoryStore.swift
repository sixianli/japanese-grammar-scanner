import UIKit

/// 本地学习记录：最近查看的语法点、最近的扫描（图片 + 识别到的语法点）。只保存在本机。
@MainActor
final class HistoryStore: ObservableObject {
    struct ScanRecord: Codable, Identifiable, Hashable {
        let id: UUID
        let date: Date
        var grammarIDs: [String]
        let imageFile: String
    }

    /// 一个语法点的学习记录（用于“最近查看”“快要忘了”“学习进度”）。
    struct ViewRecord: Codable, Hashable {
        let id: String
        var firstViewed: Date
        var lastViewed: Date
        /// 旧版复习阶段（0,1,2…，对应间隔 1/3/7/14/30 天）。只用于把旧记录换算成 FSRS 的初始状态
        var stage: Int
        /// 查看次数（旧版本没有记录，视为 1）
        var viewCount: Int? = nil
        /// FSRS 记忆状态（旧版本没有，按 stage 换算）
        var memory: FSRS.Memory? = nil
        /// 上一次复习（第一次看、或自评）的时间：遗忘曲线从这里开始算。只是打开看看、没有自评，不会重新计时
        var lastReview: Date? = nil
    }

    /// 旧版的复习间隔（天）：旧记录按所处阶段换算 FSRS 的记忆稳定度
    nonisolated static let legacyIntervals: [Double] = [1, 3, 7, 14, 30, 60]

    private static let viewedKey = "recentGrammarIDs"
    private static let recordsKey = "grammarViewRecords"
    private static let maxViewed = 30
    private static let maxScans = 12

    @Published private(set) var recentGrammarIDs: [String]
    @Published private(set) var viewRecords: [String: ViewRecord] = [:]
    @Published private(set) var scans: [ScanRecord] = []

    private let defaults: UserDefaults
    private let directory: URL

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ScanHistory", isDirectory: true)
        let recentIDs = defaults.stringArray(forKey: Self.viewedKey) ?? []
        recentGrammarIDs = recentIDs
        if let data = defaults.data(forKey: Self.recordsKey),
           let records = try? JSONDecoder().decode([String: ViewRecord].self, from: data) {
            viewRecords = records
        } else {
            // 旧版本只记录了 id 列表：迁移为今天查看过
            let now = Date()
            var migrated: [String: ViewRecord] = [:]
            for id in recentIDs { migrated[id] = ViewRecord(id: id, firstViewed: now, lastViewed: now, stage: 0) }
            viewRecords = migrated
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([ScanRecord].self, from: data) {
            scans = list.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.imageFile).path) }
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    // MARK: 最近查看

    func recordViewed(_ id: String, now: Date = Date()) {
        if var r = viewRecords[id] {
            // 只是打开看看：不改变记忆状态（要靠「快要忘了」里的自评来更新）
            r.lastViewed = now
            r.viewCount = (r.viewCount ?? 1) + 1
            viewRecords[id] = r
        } else {
            // 第一次看：只是读过、没有测过记没记住，按「有点模糊」作为初始状态（约 1 天后第一次复习）
            viewRecords[id] = ViewRecord(id: id, firstViewed: now, lastViewed: now, stage: 0, viewCount: 1,
                                         memory: FSRS.initial(.hard), lastReview: now)
        }
        saveRecords()
        recentGrammarIDs.removeAll { $0 == id }
        recentGrammarIDs.insert(id, at: 0)
        if recentGrammarIDs.count > Self.maxViewed { recentGrammarIDs.removeLast(recentGrammarIDs.count - Self.maxViewed) }
        defaults.set(recentGrammarIDs, forKey: Self.viewedKey)
    }

    func clearViewed() {
        recentGrammarIDs = []
        viewRecords = [:]
        defaults.removeObject(forKey: Self.viewedKey)
        defaults.removeObject(forKey: Self.recordsKey)
    }

    /// 复习阈值：估计的记住率降到 90% 以下就该复习
    nonisolated static let reviewThreshold = FSRS.targetRetention

    /// 记忆状态：新记录直接用保存的 FSRS 状态；旧记录按旧阶段换算（旧阶段的间隔正好是记住率降到 90% 的天数，即 FSRS 的稳定度）
    nonisolated static func memory(_ r: ViewRecord) -> FSRS.Memory {
        if let m = r.memory { return m }
        return FSRS.Memory(stability: legacyIntervals[min(max(r.stage, 0), legacyIntervals.count - 1)], difficulty: 5)
    }

    nonisolated static func lastReview(_ r: ViewRecord) -> Date { r.lastReview ?? r.lastViewed }

    /// FSRS 遗忘曲线估算的当前记住率（按真实经过的时间）
    nonisolated static func retention(_ r: ViewRecord, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(lastReview(r)) / 86_400)
        return FSRS.retrievability(elapsedDays: days, stability: memory(r).stability)
    }

    /// 是否到了复习时间
    nonisolated static func isDue(_ r: ViewRecord, now: Date) -> Bool {
        retention(r, now: now) <= reviewThreshold + 1e-9
    }

    /// 某个语法点现在是否该复习（没看过的不算）
    func isDue(_ id: String, now: Date = Date()) -> Bool {
        viewRecords[id].map { Self.isDue($0, now: now) } ?? false
    }

    /// 复习时的自评：按 FSRS 更新记忆状态，下次复习时间随之改变
    func rate(_ id: String, _ grade: FSRS.Grade, now: Date = Date()) {
        guard var r = viewRecords[id] else { return }
        let days = max(0, now.timeIntervalSince(Self.lastReview(r)) / 86_400)
        r.memory = FSRS.review(Self.memory(r), elapsedDays: days, grade: grade)
        r.lastReview = now
        r.lastViewed = now
        viewRecords[id] = r
        saveRecords()
    }

    /// 下一次该复习的时间
    func nextReview(of id: String) -> Date? {
        guard let r = viewRecords[id] else { return nil }
        return Self.lastReview(r).addingTimeInterval(FSRS.interval(stability: Self.memory(r).stability) * 86_400)
    }

    struct ReviewItem: Hashable {
        let id: String
        /// 估计的记忆保持率 0~1
        let retention: Double
    }

    /// 今天该复习的语法点：按“最快要忘掉”优先（保持率越低越靠前），
    /// 同时按重要性加权（在扫描材料中出现次数、是否收藏）。
    func dueForReview(now: Date = Date(), limit: Int = 5, importance: (String) -> Double = { _ in 1 }) -> [ReviewItem] {
        viewRecords.values
            .filter { Self.isDue($0, now: now) }
            .map { r -> (ReviewItem, Double) in
                let ret = Self.retention(r, now: now)
                return (ReviewItem(id: r.id, retention: ret), (1 - ret) * importance(r.id))
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
            .prefix(limit)
            .map { $0.0 }
    }

    /// 查看次数（没看过为 0）
    func viewCount(of id: String) -> Int {
        guard let r = viewRecords[id] else { return 0 }
        return r.viewCount ?? 1
    }

    /// 估计的当前记忆保持率；没看过返回 nil
    func retention(of id: String, now: Date = Date()) -> Double? {
        viewRecords[id].map { Self.retention($0, now: now) }
    }

    /// 某个语法点出现在多少次扫描中
    func scanCount(of id: String) -> Int {
        scans.reduce(0) { $0 + ($1.grammarIDs.contains(id) ? 1 : 0) }
    }

    /// 学过（看过讲解）的语法点
    var learnedIDs: Set<String> { Set(viewRecords.keys) }

    /// 在扫描记录里出现过、但还没看过讲解的语法点，按出现在多少次扫描中排序
    func frequentUnlearned(limit: Int = 5) -> [(id: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in scans { for id in Set(s.grammarIDs) { counts[id, default: 0] += 1 } }
        let learned = learnedIDs
        return counts.filter { !learned.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { (id: $0.key, count: $0.value) }
    }

    /// 同形语法合并后，把记录里的旧 id 换成新 id：同一语法点保留最近一次查看、较高的阶段。
    func migrate(aliases: [String: String]) {
        let needs = recentGrammarIDs.contains { aliases[$0] != nil }
            || viewRecords.keys.contains { aliases[$0] != nil }
            || scans.contains { $0.grammarIDs.contains { aliases[$0] != nil } }
        guard needs else { return }
        var seen = Set<String>()
        recentGrammarIDs = recentGrammarIDs.map { aliases[$0] ?? $0 }.filter { seen.insert($0).inserted }
        defaults.set(recentGrammarIDs, forKey: Self.viewedKey)
        var merged: [String: ViewRecord] = [:]
        for (oldID, r) in viewRecords {
            let id = aliases[oldID] ?? oldID
            if let existing = merged[id] {
                let newer = Self.lastReview(r) > Self.lastReview(existing) ? r : existing
                merged[id] = ViewRecord(id: id, firstViewed: min(existing.firstViewed, r.firstViewed),
                                        lastViewed: max(existing.lastViewed, r.lastViewed), stage: max(existing.stage, r.stage),
                                        viewCount: (existing.viewCount ?? 1) + (r.viewCount ?? 1),
                                        memory: newer.memory, lastReview: newer.lastReview)
            } else {
                merged[id] = ViewRecord(id: id, firstViewed: r.firstViewed, lastViewed: r.lastViewed, stage: r.stage, viewCount: r.viewCount,
                                        memory: r.memory, lastReview: r.lastReview)
            }
        }
        viewRecords = merged
        saveRecords()
        for i in scans.indices {
            var s = Set<String>()
            scans[i].grammarIDs = scans[i].grammarIDs.map { aliases[$0] ?? $0 }.filter { s.insert($0).inserted }
        }
        saveIndex()
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(viewRecords) { defaults.set(data, forKey: Self.recordsKey) }
    }

    // MARK: 最近扫描

    /// 保存一次扫描，返回记录 id。
    @discardableResult
    func recordScan(image: UIImage, grammarIDs: [String]) -> UUID? {
        let id = UUID()
        let file = "\(id.uuidString).jpg"
        let scaled = image.normalizedForOCR(maxDimension: 2000)
        guard let data = scaled.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        } catch {
            return nil
        }
        scans.insert(ScanRecord(id: id, date: Date(), grammarIDs: grammarIDs, imageFile: file), at: 0)
        while scans.count > Self.maxScans {
            let removed = scans.removeLast()
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(removed.imageFile))
        }
        saveIndex()
        return id
    }

    /// 用户修正文本后更新该次扫描识别到的语法点。
    func updateScan(_ id: UUID, grammarIDs: [String]) {
        guard let i = scans.firstIndex(where: { $0.id == id }) else { return }
        scans[i].grammarIDs = grammarIDs
        saveIndex()
    }

    func image(for record: ScanRecord) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(record.imageFile).path)
    }

    func thumbnail(for record: ScanRecord) -> UIImage? {
        image(for: record)?.preparingThumbnail(of: CGSize(width: 240, height: 320))
    }

    func clearScans() {
        for s in scans { try? FileManager.default.removeItem(at: directory.appendingPathComponent(s.imageFile)) }
        scans = []
        saveIndex()
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(scans) { try? data.write(to: indexURL, options: .atomic) }
    }
}
