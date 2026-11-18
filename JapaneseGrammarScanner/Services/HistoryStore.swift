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

    /// 一个语法点的学习记录（用于“最近查看”“今日复习”“学习进度”）。
    struct ViewRecord: Codable, Hashable {
        let id: String
        var firstViewed: Date
        var lastViewed: Date
        /// 复习阶段：0,1,2…，对应间隔 1/3/7/14/30 天
        var stage: Int
    }

    /// 间隔复习的间隔（天）
    static let reviewIntervals: [Double] = [1, 3, 7, 14, 30]

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
        recentGrammarIDs = defaults.stringArray(forKey: Self.viewedKey) ?? []
        if let data = defaults.data(forKey: Self.recordsKey),
           let records = try? JSONDecoder().decode([String: ViewRecord].self, from: data) {
            viewRecords = records
        } else {
            // 旧版本只记录了 id 列表：迁移为今天查看过
            let now = Date()
            for id in recentGrammarIDs { viewRecords[id] = ViewRecord(id: id, firstViewed: now, lastViewed: now, stage: 0) }
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ScanHistory", isDirectory: true)
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
            // 到了复习时间再次查看 → 进入下一个复习阶段
            if Self.isDue(r, now: now) { r.stage = min(r.stage + 1, Self.reviewIntervals.count) }
            r.lastViewed = now
            viewRecords[id] = r
        } else {
            viewRecords[id] = ViewRecord(id: id, firstViewed: now, lastViewed: now, stage: 0)
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

    /// 是否到了复习时间（最后阶段之后不再提醒）
    nonisolated static func isDue(_ r: ViewRecord, now: Date) -> Bool {
        guard r.stage < reviewIntervals.count else { return false }
        return now.timeIntervalSince(r.lastViewed) >= reviewIntervals[r.stage] * 86_400
    }

    /// 今天该复习的语法点（最久没看的排前面）
    func dueForReview(now: Date = Date(), limit: Int = 5) -> [String] {
        viewRecords.values
            .filter { Self.isDue($0, now: now) }
            .sorted { $0.lastViewed < $1.lastViewed }
            .prefix(limit)
            .map(\.id)
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
