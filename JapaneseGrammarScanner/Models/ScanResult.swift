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
    let range: NSRange
    let grammarIDs: [String]
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
}

/// 图片 / 相机帧上需要绘制的高亮框。
struct HighlightBox: Identifiable, Hashable {
    let id = UUID()
    let clusterID: Int
    /// 归一化坐标，原点在**左上角**（已从 Vision 坐标系翻转），方便 SwiftUI 绘制。
    let rect: CGRect
}

/// 一次扫描（一张图片或一帧相机画面）的完整结果。
struct ScanResult {
    let text: String
    let matches: [GrammarMatch]
    let clusters: [HighlightCluster]
    let boxes: [HighlightBox]

    static let empty = ScanResult(text: "", matches: [], clusters: [], boxes: [])

    /// 去重后的语法点 id，按在文中首次出现的顺序。
    var orderedGrammarIDs: [String] {
        var seen = Set<String>()
        return matches.sorted { $0.range.location < $1.range.location }
            .compactMap { seen.insert($0.grammarID).inserted ? $0.grammarID : nil }
    }
}
