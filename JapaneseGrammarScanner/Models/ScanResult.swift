import CoreGraphics
import Foundation

/// 文本中命中一个语法点的位置。
struct GrammarMatch: Hashable {
    let grammarID: String
    /// 在整段文本（NSString / UTF-16）中的范围。
    let range: NSRange
}

/// 重叠在一起的若干命中合并成一个“高亮块”。点击高亮块时，如果包含多个语法点，就让用户选择。
struct HighlightCluster: Identifiable, Hashable {
    let id: Int
    /// 所有显示片段的总范围
    let range: NSRange
    let grammarIDs: [String]
    /// 实际要框出来的片段。跨度很长的语法（如「や……など」）只框关键部分（「や」「など」），不把中间整段框进去。
    var ranges: [NSRange] = []
    /// 每个语法点命中的原文（用于选择列表里显示、讲解页定位到对应用法）
    var matchedTexts: [String: String] = [:]

    init(id: Int, range: NSRange, grammarIDs: [String], ranges: [NSRange] = [], matchedTexts: [String: String] = [:]) {
        self.id = id
        self.range = range
        self.grammarIDs = grammarIDs
        self.ranges = ranges.isEmpty ? [range] : ranges
        self.matchedTexts = matchedTexts
    }

    /// 选择列表里显示的原文片段：太长时只留头尾（「店や…店など」）
    func excerpt(for id: String) -> String? {
        guard let t = matchedTexts[id]?.replacingOccurrences(of: "\n", with: "") else { return nil }
        guard t.count > 12 else { return t }
        return String(t.prefix(5)) + "…" + String(t.suffix(5))
    }
}

/// OCR 识别出的一行文字，及其在整段文本中的位置。
struct RecognizedLine {
    /// 在整段文本中的 UTF-16 范围（不含行间插入的换行符）。
    let rangeInText: NSRange
    let text: String
    /// Vision 归一化坐标（原点在左下角）的整行包围框。
    let boundingBox: CGRect
    /// 给定行内 UTF-16 范围，返回该子串的归一化包围框。
    let boxForRange: (NSRange) -> CGRect?
    /// 整行的四个角（Vision 坐标，原点左下）：左上、右上、右下、左下。斜拍时是倾斜的四边形。
    var quad: [CGPoint] = []
    /// 子串的四个角（同上），跟着文字倾斜
    var quadForRange: (NSRange) -> [CGPoint]? = { _ in nil }
}

/// 图片 / 相机帧上需要绘制的高亮框。
struct HighlightBox: Identifiable, Hashable {
    /// 相机实时取景时，同一个框在前后帧之间保持同一个 id（见 LiveResultStabilizer），位置变化时平滑移动而不是闪一下
    let id: UUID
    let clusterID: Int
    /// 归一化坐标，原点在**左上角**（已从 Vision 坐标系翻转），方便 SwiftUI 绘制。四边形的外接矩形。
    let rect: CGRect
    /// 贴着文字的四边形（左上、右上、右下、左下；归一化、原点左上）。斜拍时跟文字一起倾斜，不会比文字高出一截。
    let quad: [CGPoint]

    init(id: UUID = UUID(), clusterID: Int, rect: CGRect, quad: [CGPoint]? = nil) {
        self.id = id
        self.clusterID = clusterID
        self.rect = rect
        self.quad = quad ?? [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                             CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
    static func == (a: HighlightBox, b: HighlightBox) -> Bool {
        a.id == b.id && a.clusterID == b.clusterID && a.rect == b.rect && a.quad == b.quad
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(clusterID)
    }
}

/// 一次扫描（一张图片或一帧相机画面）的完整结果。
struct ScanResult {
    let text: String
    let matches: [GrammarMatch]
    let clusters: [HighlightCluster]
    let boxes: [HighlightBox]

    static let empty = ScanResult(text: "", matches: [], clusters: [], boxes: [])

    /// 某个语法点第一次命中的原文
    func matchedText(for id: String) -> String? {
        guard let m = matches.first(where: { $0.grammarID == id }), NSMaxRange(m.range) <= (text as NSString).length else { return nil }
        return (text as NSString).substring(with: m.range)
    }

    /// 去重后的语法点 id，按在文中首次出现的顺序。
    var orderedGrammarIDs: [String] {
        var seen = Set<String>()
        return matches.sorted { $0.range.location < $1.range.location }
            .compactMap { seen.insert($0.grammarID).inserted ? $0.grammarID : nil }
    }
}
