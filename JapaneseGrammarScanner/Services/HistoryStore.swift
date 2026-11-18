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

    private static let viewedKey = "recentGrammarIDs"
    private static let maxViewed = 30
    private static let maxScans = 12

    @Published private(set) var recentGrammarIDs: [String]
    @Published private(set) var scans: [ScanRecord] = []

    private let defaults: UserDefaults
    private let directory: URL

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentGrammarIDs = defaults.stringArray(forKey: Self.viewedKey) ?? []
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

    func recordViewed(_ id: String) {
        recentGrammarIDs.removeAll { $0 == id }
        recentGrammarIDs.insert(id, at: 0)
        if recentGrammarIDs.count > Self.maxViewed { recentGrammarIDs.removeLast(recentGrammarIDs.count - Self.maxViewed) }
        defaults.set(recentGrammarIDs, forKey: Self.viewedKey)
    }

    func clearViewed() {
        recentGrammarIDs = []
        defaults.removeObject(forKey: Self.viewedKey)
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
