import ImageIO
import UIKit

@MainActor
final class HistoryStore: ObservableObject {
    struct ScanRecord: Codable, Identifiable, Hashable {
        let id: UUID
        let date: Date
        var grammarIDs: [String]
        let imageFile: String
    }

    struct ViewRecord: Codable, Hashable {
        let id: String
        var firstViewed: Date
        var lastViewed: Date
        var stage: Int
        var viewCount: Int? = nil
        var memory: FSRS.Memory? = nil
        var lastReview: Date? = nil
    }

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
    private var thumbnails: [String: UIImage] = [:]

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScanHistory", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard, directory: URL = HistoryStore.defaultDirectory) {
        self.defaults = defaults
        self.directory = directory
        let recentIDs = defaults.stringArray(forKey: Self.viewedKey) ?? []
        recentGrammarIDs = recentIDs
        if let data = defaults.data(forKey: Self.recordsKey),
           let records = try? JSONDecoder().decode([String: ViewRecord].self, from: data) {
            viewRecords = records
        } else {
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

    func recordViewed(_ id: String, now: Date = Date()) {
        if var r = viewRecords[id] {
            r.lastViewed = now
            r.viewCount = (r.viewCount ?? 1) + 1
            viewRecords[id] = r
        } else {
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

    nonisolated static let reviewThreshold = FSRS.targetRetention

    nonisolated static func memory(_ r: ViewRecord) -> FSRS.Memory {
        if let m = r.memory { return m }
        return FSRS.Memory(stability: legacyIntervals[min(max(r.stage, 0), legacyIntervals.count - 1)], difficulty: 5)
    }

    nonisolated static func lastReview(_ r: ViewRecord) -> Date { r.lastReview ?? r.lastViewed }

    nonisolated static func retention(_ r: ViewRecord, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(lastReview(r)) / 86_400)
        return FSRS.retrievability(elapsedDays: days, stability: memory(r).stability)
    }

    nonisolated static func isDue(_ r: ViewRecord, now: Date) -> Bool {
        retention(r, now: now) <= reviewThreshold + 1e-9
    }

    func isDue(_ id: String, now: Date = Date()) -> Bool {
        viewRecords[id].map { Self.isDue($0, now: now) } ?? false
    }

    func rate(_ id: String, _ grade: FSRS.Grade, now: Date = Date()) {
        guard var r = viewRecords[id] else { return }
        let days = max(0, now.timeIntervalSince(Self.lastReview(r)) / 86_400)
        r.memory = FSRS.review(Self.memory(r), elapsedDays: days, grade: grade)
        r.lastReview = now
        r.lastViewed = now
        viewRecords[id] = r
        saveRecords()
    }

    func nextReview(of id: String) -> Date? {
        guard let r = viewRecords[id] else { return nil }
        return Self.lastReview(r).addingTimeInterval(FSRS.interval(stability: Self.memory(r).stability) * 86_400)
    }

    struct ReviewItem: Hashable {
        let id: String
        let retention: Double
    }

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

    func viewCount(of id: String) -> Int {
        guard let r = viewRecords[id] else { return 0 }
        return r.viewCount ?? 1
    }

    func retention(of id: String, now: Date = Date()) -> Double? {
        viewRecords[id].map { Self.retention($0, now: now) }
    }

    func scanCount(of id: String) -> Int {
        scans.reduce(0) { $0 + ($1.grammarIDs.contains(id) ? 1 : 0) }
    }

    var learnedIDs: Set<String> { Set(viewRecords.keys) }

    func frequentUnlearned(limit: Int = 5) -> [(id: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in scans { for id in Set(s.grammarIDs) { counts[id, default: 0] += 1 } }
        let learned = learnedIDs
        return counts.filter { !learned.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { (id: $0.key, count: $0.value) }
    }

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

    @discardableResult
    func recordScan(image: UIImage, grammarIDs: [String]) -> UUID? {
        let id = UUID()
        let file = "\(id.uuidString).jpg"
        let url = directory.appendingPathComponent(file)
        scans.insert(ScanRecord(id: id, date: Date(), grammarIDs: grammarIDs, imageFile: file), at: 0)
        while scans.count > Self.maxScans {
            let removed = scans.removeLast()
            thumbnails[removed.imageFile] = nil
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(removed.imageFile))
        }
        pendingWrites[file] = Task.detached(priority: .utility) {
            let data = image.normalizedForOCR(maxDimension: 2000).jpegData(compressionQuality: 0.8)
            let written = (try? data?.write(to: url, options: .atomic)) != nil
            let thumb = written ? Self.downsampled(url) : nil
            await self.finishWrite(file: file, written: written, thumbnail: thumb)
        }
        return id
    }

    private var pendingWrites: [String: Task<Void, Never>] = [:]

    private func finishWrite(file: String, written: Bool, thumbnail: UIImage?) {
        pendingWrites[file] = nil
        if written {
            thumbnails[file] = thumbnail
            saveIndex()
            objectWillChange.send()
        } else {
            scans.removeAll { $0.imageFile == file }
        }
    }

    func waitForPendingWrites() async {
        for task in pendingWrites.values { await task.value }
    }

    nonisolated static func downsampled(_ url: URL, maxPixel: Int = 320) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    func updateScan(_ id: UUID, grammarIDs: [String]) {
        guard let i = scans.firstIndex(where: { $0.id == id }) else { return }
        scans[i].grammarIDs = grammarIDs
        saveIndex()
    }

    func image(for record: ScanRecord) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(record.imageFile).path)
    }

    func thumbnail(for record: ScanRecord) -> UIImage? {
        if let cached = thumbnails[record.imageFile] { return cached }
        guard pendingWrites[record.imageFile] == nil,
              let thumb = Self.downsampled(directory.appendingPathComponent(record.imageFile)) else { return nil }
        thumbnails[record.imageFile] = thumb
        return thumb
    }

    func clearScans() {
        for s in scans { try? FileManager.default.removeItem(at: directory.appendingPathComponent(s.imageFile)) }
        thumbnails = [:]
        scans = []
        saveIndex()
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(scans) { try? data.write(to: indexURL, options: .atomic) }
    }
}
