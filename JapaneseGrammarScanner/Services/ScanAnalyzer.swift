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
    /// 优先采用 Vision 给出的逐字框（斜拍、弯曲的照片上它最贴合文字）；
    /// 但部分设备上 Vision 的逐字框会整体偏移，所以先检查它是否「落在这一行里」：
    /// 竖直方向中心要在行框内、水平方向不能超出行框、宽度与按字数估算的宽度相差不大。不合理时改用按字数估算的框。
    static func substringBox(line: RecognizedLine, local: NSRange) -> CGRect {
        let estimate = estimatedBox(line: line, local: local)
        guard let vision = line.boxForRange(local), plausible(vision, in: line.boundingBox, estimate: estimate) else { return estimate }
        return vision
    }

    static func plausible(_ r: CGRect, in line: CGRect, estimate: CGRect) -> Bool {
        guard r.width > 0, r.height > 0 else { return false }
        let isVertical = line.height > line.width * 1.5
        // 一个字大约多宽（横排看高度，竖排看宽度）
        let glyph = isVertical ? line.width : min(line.height, max(estimate.width, 1e-6))
        let tol = glyph * 0.6
        // 中心必须在行框里
        guard r.midX >= line.minX - tol, r.midX <= line.maxX + tol,
              r.midY >= line.minY - tol, r.midY <= line.maxY + tol else { return false }
        // 不能明显超出行框
        guard r.minX >= line.minX - tol, r.maxX <= line.maxX + tol,
              r.minY >= line.minY - tol, r.maxY <= line.maxY + tol else { return false }
        // 长度与按字数估算的差不多（0.5～2 倍）
        let (a, b) = isVertical ? (r.height, estimate.height) : (r.width, estimate.width)
        guard b > 0, a / b > 0.5, a / b < 2 else { return false }
        // 横排：框的高度不应超过行高的 1.3 倍（斜拍时行框本身就高，所以只限制不能比行框还高）
        if !isVertical, r.height > line.height * 1.3 { return false }
        return true
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
