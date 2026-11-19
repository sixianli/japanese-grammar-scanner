import CoreGraphics
import Foundation

/// 相机实时取景时让识别结果「稳住」：
/// 每 0.6 秒识别一帧，单帧结果会因为手抖、对焦、光线而时有时无、位置来回跳。这里在帧与帧之间做跟踪：
/// - 一个框要连续两帧都识别到才显示；显示后连续 3 帧（约 2 秒）没识别到才消失；
/// - 前后帧的同一个框保持同一个 id，位置只有明显移动时才更新（交给界面做平滑移动），微小抖动忽略；
/// - 顶部语法点标签按首次出现的顺序排列，新出现的排在后面，已有的不换位置。
final class LiveResultStabilizer {
    private struct Track {
        let id: UUID
        var grammarIDs: [String]
        var rect: CGRect
        var hits: Int
        var misses: Int
        var shown: Bool
    }

    static let hitsToShow = 2
    static let missesToHide = 3
    /// 中心移动小于这个距离（归一化坐标）视为抖动，不更新位置
    static let jitter: CGFloat = 0.012

    private var tracks: [Track] = []
    private var order: [String] = []

    func reset() {
        tracks = []
        order = []
    }

    func update(_ frame: ScanResult) -> ScanResult {
        let clustersByID = Dictionary(uniqueKeysWithValues: frame.clusters.map { ($0.id, $0) })
        var matched = Set<Int>()

        for box in frame.boxes {
            guard let cluster = clustersByID[box.clusterID] else { continue }
            let ids = cluster.grammarIDs
            // 同一个语法点、位置最近的已有框
            var best: (index: Int, distance: CGFloat)?
            for (i, t) in tracks.enumerated() where !matched.contains(i) {
                guard !Set(t.grammarIDs).isDisjoint(with: ids) else { continue }
                let d = Self.distance(t.rect, box.rect)
                let limit = max(0.06, max(t.rect.width, t.rect.height))
                if d < limit, d < (best?.distance ?? .infinity) { best = (i, d) }
            }
            if let best {
                matched.insert(best.index)
                var t = tracks[best.index]
                t.grammarIDs = ids
                if Self.distance(t.rect, box.rect) > Self.jitter
                    || abs(t.rect.width - box.rect.width) > Self.jitter
                    || abs(t.rect.height - box.rect.height) > Self.jitter {
                    t.rect = box.rect
                }
                t.hits += 1
                t.misses = 0
                if t.hits >= Self.hitsToShow { t.shown = true }
                tracks[best.index] = t
            } else {
                tracks.append(Track(id: UUID(), grammarIDs: ids, rect: box.rect, hits: 1, misses: 0, shown: false))
                matched.insert(tracks.count - 1)
            }
        }

        // 本帧没识别到的框
        for i in tracks.indices where !matched.contains(i) {
            tracks[i].misses += 1
            if !tracks[i].shown { tracks[i].hits = 0 }
        }
        tracks.removeAll { $0.misses >= ($0.shown ? Self.missesToHide : 1) }

        // 输出：只含已显示的框；语法点按首次出现的顺序
        let shown = tracks.filter(\.shown)
        var shownIDs = Set<String>()
        for t in shown.sorted(by: { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }) {
            for id in t.grammarIDs where shownIDs.insert(id).inserted && !order.contains(id) {
                order.append(id)
            }
        }
        order.removeAll { !shownIDs.contains($0) }

        var clusters: [HighlightCluster] = []
        var boxes: [HighlightBox] = []
        for (i, t) in shown.enumerated() {
            clusters.append(HighlightCluster(id: i, range: NSRange(location: 0, length: 0), grammarIDs: t.grammarIDs))
            boxes.append(HighlightBox(id: t.id, clusterID: i, rect: t.rect))
        }
        let matches = order.enumerated().map { GrammarMatch(grammarID: $1, range: NSRange(location: $0, length: 1)) }
        return ScanResult(text: frame.text, matches: matches, clusters: clusters, boxes: boxes)
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }
}
