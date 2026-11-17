import CoreGraphics
import Foundation

/// 把 OCR 结果和语法识别结果结合起来，算出文本高亮和图片上的高亮框。
enum ScanAnalyzer {
    static func analyze(text: String, lines: [RecognizedLine], matcher: GrammarMatcher) -> ScanResult {
        let matches = matcher.matches(in: text)
        let clusters = GrammarMatcher.clusters(from: matches)

        var boxes: [HighlightBox] = []
        for cluster in clusters {
            for line in lines {
                let overlap = NSIntersectionRange(cluster.range, line.rangeInText)
                guard overlap.length > 0 else { continue }
                let local = NSRange(location: overlap.location - line.rangeInText.location, length: overlap.length)
                let visionRect = line.boxForRange(local) ?? estimatedBox(line: line, local: local)
                boxes.append(HighlightBox(clusterID: cluster.id, rect: flip(visionRect)))
            }
        }
        return ScanResult(text: text, matches: matches, clusters: clusters, boxes: boxes)
    }

    /// Vision 拿不到子串框时，按字符比例在整行框里估算（横排）。
    private static func estimatedBox(line: RecognizedLine, local: NSRange) -> CGRect {
        let total = max((line.text as NSString).length, 1)
        let box = line.boundingBox
        let isVertical = box.height > box.width * 1.5
        if isVertical {
            let unit = box.height / CGFloat(total)
            // 竖排：从上往下读，Vision 坐标原点在左下
            let top = box.maxY - CGFloat(local.location) * unit
            return CGRect(x: box.minX, y: top - CGFloat(local.length) * unit, width: box.width, height: CGFloat(local.length) * unit)
        } else {
            let unit = box.width / CGFloat(total)
            return CGRect(x: box.minX + CGFloat(local.location) * unit, y: box.minY, width: CGFloat(local.length) * unit, height: box.height)
        }
    }

    /// Vision 归一化坐标（左下原点） → 左上原点。
    private static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }
}
