import CoreGraphics
import Foundation

/// 把 OCR 结果和语法识别结果结合起来，算出文本高亮和图片上的高亮框。
enum ScanAnalyzer {
    static func analyze(text: String, lines: [RecognizedLine], matcher: GrammarMatcher) -> ScanResult {
        let matches = matcher.matches(in: text)
        let clusters = GrammarMatcher.clusters(from: matches, text: text)

        var boxes: [HighlightBox] = []
        for cluster in clusters {
            for segment in cluster.ranges {
                for line in lines {
                    let overlap = NSIntersectionRange(segment, line.rangeInText)
                    guard overlap.length > 0 else { continue }
                    let local = NSRange(location: overlap.location - line.rangeInText.location, length: overlap.length)
                    let quad = flip(substringQuad(line: line, local: local))
                    boxes.append(HighlightBox(clusterID: cluster.id, rect: bounds(of: quad), quad: quad))
                }
            }
        }
        return ScanResult(text: text, matches: matches, clusters: clusters, boxes: boxes)
    }

    /// 一行中某段文字的框。
    /// 优先采用 Vision 给出的逐字框（斜拍、弯曲的照片上它最贴合文字）；
    /// 但部分设备上 Vision 的逐字框会偏移或变形，所以先检查是否合理：中心离所在行不超过一个字、
    /// （横排时）长度与按字数估算的相差不超过 0.4～2.5 倍。不合理时改用按字数估算的框。
    static func substringBox(line: RecognizedLine, local: NSRange) -> CGRect {
        let estimate = estimatedBox(line: line, local: local)
        guard let vision = line.boxForRange(local), plausible(vision, in: line.boundingBox, estimate: estimate) else { return estimate }
        return vision
    }

    static func plausible(_ r: CGRect, in line: CGRect, estimate: CGRect) -> Bool {
        guard r.width > 0, r.height > 0 else { return false }
        let isVertical = line.height > line.width * 1.5
        // 一个字大约多宽（横排看行高，竖排看行宽）
        let glyph = isVertical ? line.width : min(line.height, max(estimate.width, 1e-6))
        let tol = glyph
        // 位置偏了：框的中心离这一行超过一个字
        guard r.midX >= line.minX - tol, r.midX <= line.maxX + tol,
              r.midY >= line.minY - tol, r.midY <= line.maxY + tol else { return false }
        // 横排：长度与按字数估算的相差过大（例如给成了整行，或只剩一条细线）
        // 竖排的行在照片里多半是 Vision 把几行的开头误连成一列，此时按字数的估算反而不可靠，不做长度比较
        if !isVertical, estimate.width > 0 {
            let ratio = r.width / estimate.width
            guard ratio > 0.4, ratio < 2.5 else { return false }
        }
        return true
    }

    /// 一段文字贴着文字方向的四边形（Vision 坐标）。优先用 Vision 的逐字四边形，不合理时按字数沿整行四边形插值。
    /// 斜拍、弯曲的页面上，四边形跟文字一起倾斜；外接矩形会比文字高出一截，并压到上下行。
    static func substringQuad(line: RecognizedLine, local: NSRange) -> [CGPoint] {
        let estimate = estimatedQuad(line: line, local: local)
        guard let vision = line.quadForRange(local), vision.count == 4,
              plausible(bounds(of: vision), in: line.boundingBox, estimate: bounds(of: estimate)) else {
            return estimate
        }
        return fittedToLine(vision, line: line) ?? vision
    }

    /// Vision 给的单段框左右位置准，但斜拍时高度常常是字高的两倍多（盖到上下行、和别的框重叠）。
    /// 所以只取它在行方向上的起止位置，高度和倾斜沿用整行四边形（整行四边形贴着字）。
    static func fittedToLine(_ vision: [CGPoint], line: RecognizedLine) -> [CGPoint]? {
        let q = line.quad
        let box = line.boundingBox
        guard q.count == 4, box.height <= box.width * 1.5 else { return nil }  // 竖排保持原样
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let m0 = mid(q[0], q[3]), m1 = mid(q[1], q[2])
        let dx = m1.x - m0.x, dy = m1.y - m0.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return nil }
        func param(_ p: CGPoint) -> CGFloat {
            min(max(((p.x - m0.x) * dx + (p.y - m0.y) * dy) / len2, 0), 1)
        }
        let t0 = param(mid(vision[0], vision[3]))
        let t1 = param(mid(vision[1], vision[2]))
        guard t1 - t0 > 0.001 else { return nil }
        return [lerp(q[0], q[1], t0), lerp(q[0], q[1], t1), lerp(q[3], q[2], t1), lerp(q[3], q[2], t0)]
    }

    /// 按字数在整行四边形里插值（行没有四边形时用整行矩形）
    static func estimatedQuad(line: RecognizedLine, local: NSRange) -> [CGPoint] {
        let box = line.boundingBox
        let q = line.quad.count == 4 ? line.quad
            : [CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
               CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.minY)]
        let ns = line.text as NSString
        let total = max(weightedLength(ns, NSRange(location: 0, length: ns.length)), 1)
        let t0 = weightedLength(ns, NSRange(location: 0, length: local.location)) / total
        let t1 = t0 + weightedLength(ns, local) / total
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let isVertical = box.height > box.width * 1.5
        if isVertical {
            // 竖排：从上往下读，沿左右两条边插值
            return [lerp(q[0], q[3], t0), lerp(q[1], q[2], t0), lerp(q[1], q[2], t1), lerp(q[0], q[3], t1)]
        }
        return [lerp(q[0], q[1], t0), lerp(q[0], q[1], t1), lerp(q[3], q[2], t1), lerp(q[3], q[2], t0)]
    }

    static func bounds(of quad: [CGPoint]) -> CGRect {
        let xs = quad.map(\.x), ys = quad.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Vision 坐标（左下原点） → 左上原点；角点顺序保持左上、右上、右下、左下
    private static func flip(_ q: [CGPoint]) -> [CGPoint] {
        q.map { CGPoint(x: $0.x, y: 1 - $0.y) }
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
