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
                boxes.append(HighlightBox(clusterID: cluster.id, rect: flip(substringBox(line: line, local: local))))
            }
        }
        return ScanResult(text: text, matches: matches, clusters: clusters, boxes: boxes)
    }

    /// 一行中某段文字的框。
    /// 印刷的日文是等宽排版（全角字等宽、半角字约一半宽），按字在行中的位置估算的框很可靠；
    /// Vision 给出的逐字框在部分设备上会偏移，所以只在它和估算结果一致时才采用，并且高度始终取整行的高度，
    /// 保证框不会上下漂移到别的行。
    static func substringBox(line: RecognizedLine, local: NSRange) -> CGRect {
        let estimate = estimatedBox(line: line, local: local)
        guard let vision = line.boxForRange(local) else { return estimate }
        let box = line.boundingBox
        let isVertical = box.height > box.width * 1.5
        let ns = line.text as NSString
        let unit = (isVertical ? box.height : box.width) / max(weightedLength(ns, NSRange(location: 0, length: ns.length)), 1)
        if isVertical {
            guard abs(vision.maxY - estimate.maxY) < unit * 0.6, abs(vision.height - estimate.height) < unit * 0.8 else { return estimate }
            return CGRect(x: box.minX, y: vision.minY, width: box.width, height: vision.height)
        } else {
            guard abs(vision.minX - estimate.minX) < unit * 0.6, abs(vision.width - estimate.width) < unit * 0.8 else { return estimate }
            return CGRect(x: vision.minX, y: box.minY, width: vision.width, height: box.height)
        }
    }

    /// 按字符宽度（全角 1、半角 0.5）在整行框里估算一段文字的位置。
    static func estimatedBox(line: RecognizedLine, local: NSRange) -> CGRect {
        let ns = line.text as NSString
        let total = max(weightedLength(ns, NSRange(location: 0, length: ns.length)), 1)
        let before = weightedLength(ns, NSRange(location: 0, length: local.location))
        let length = weightedLength(ns, local)
        let box = line.boundingBox
        let isVertical = box.height > box.width * 1.5
        if isVertical {
            let unit = box.height / total
            // 竖排：从上往下读，Vision 坐标原点在左下
            let top = box.maxY - before * unit
            return CGRect(x: box.minX, y: top - length * unit, width: box.width, height: length * unit)
        } else {
            let unit = box.width / total
            return CGRect(x: box.minX + before * unit, y: box.minY, width: length * unit, height: box.height)
        }
    }

    /// 全角字算 1，半角字（ASCII、半角片假名）算 0.5。
    static func weightedLength(_ s: NSString, _ range: NSRange) -> CGFloat {
        guard range.length > 0, NSMaxRange(range) <= s.length else { return 0 }
        var w: CGFloat = 0
        for i in range.location..<NSMaxRange(range) {
            let c = s.character(at: i)
            w += (c < 0x0100 || (0xFF61...0xFF9F).contains(c)) ? 0.5 : 1
        }
        return w
    }

    /// Vision 归一化坐标（左下原点） → 左上原点。
    private static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }
}
