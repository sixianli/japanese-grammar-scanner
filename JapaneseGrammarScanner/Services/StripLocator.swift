import CoreGraphics
import Foundation
import Vision

/// 拍照识别后的第二步：把照片切成几条竖条重新识别，用竖条里的逐字位置重新放高亮框。
///
/// 整页识别时，Vision 给一整行一个直的四边形。书页弯曲、斜拍、行距很密时，这个四边形会把上下两三行都包进去，
/// 按它切出来的单词框常常落到相邻的行，或者整体偏上、偏下半行。
/// 竖条只有页宽的三分之一多一点，每一行在竖条里几乎是直的，Vision 给的逐字位置就准得多。
///
/// 做法：
/// 1. 三条有重叠的竖条分别识别，每条里按 TextBandFinder 找出每行真正的文字带；
/// 2. 每个高亮框，在竖条的识别结果里找同一段文字：靠前后文（左右各最多 6 个字）确认是同一处，
///    离原来的框不超过 3.5 个字高（只是纠正位置，不会跑到别处）；被竖条边界切到的字不用；
/// 3. 找到就用竖条里的位置（收紧到文字带）；竖条里这一行仍然弯得厉害时，再在框附近切一小块重新识别一次；
/// 4. 太长、跨了两条竖条的片段，拆成前后两半分别找；找不到的保持原来的框。
///
/// 在 95 张实拍照片上评测：复查时仍放错的 73 个框，绝大多数回到了正确位置（docs/ocr-eval/runs/）。
enum StripLocator {
    /// 竖条里识别出的一行（坐标已换算成整张图的 Vision 归一化坐标，原点左下）
    struct Line {
        let utf16: [UInt16]
        let quad: [CGPoint]
        /// 一段文字（行内 UTF-16 范围）的四边形，已收紧到文字带
        let quadFor: (NSRange) -> [CGPoint]?
        /// 整行四边形高度 / 字高（越接近 1 越直、越不含糊）
        let looseness: CGFloat
        /// 这块识别区域在整图里的左右范围（0～1），用来排除被切到的字
        let x0: CGFloat
        let x1: CGFloat
    }

    static let stripCount = 3
    static let contextLength = 6
    static let maxDistance: CGFloat = 3.5
    /// 竖条里的这一行仍然比字高 2.2 倍还高：在框附近再切一小块重新识别
    static let looseLimit: CGFloat = 2.2

    /// 重新定位 result 的高亮框。lines 是整页识别的行（与 result 一起由 ScanAnalyzer.analyze 得到）。
    static func refine(_ result: ScanResult, lines: [RecognizedLine], image: CGImage) -> ScanResult {
        guard !result.boxes.isEmpty else { return result }
        let size = CGSize(width: image.width, height: image.height)
        var strips: [Line] = []
        for k in 0..<stripCount {
            let width = 3 / (2 * CGFloat(stripCount) + 1)   // 相邻两条重叠 1/3 条宽
            let x0 = CGFloat(k) * width * 2 / 3
            strips += recognize(image, region: CGRect(x: x0, y: 0, width: min(width, 1 - x0), height: 1))
        }
        guard !strips.isEmpty else { return result }

        var local: [(region: CGRect, lines: [Line])] = []
        var boxes: [HighlightBox] = []
        for box in result.boxes {
            guard let source = box.source, lines.indices.contains(source.line),
                  isHorizontal(lines[source.line]) else {
                boxes.append(box)
                continue
            }
            let text = Array(lines[source.line].text.utf16)
            let prior = center(box.quad.map(flipPoint))
            var quads: [[CGPoint]] = []
            if let q = locate(text, source.range, prior: prior, in: strips, size: size, image: image, local: &local) {
                quads = [q]
            } else if source.range.length >= 4 {
                // 太长、跨了竖条：拆成前后两半分别找（两半都要找到）
                let half = source.range.length / 2
                let parts = [NSRange(location: source.range.location, length: half),
                             NSRange(location: source.range.location + half, length: source.range.length - half)]
                let found = parts.compactMap { part -> [CGPoint]? in
                    let f = (CGFloat(part.location - source.range.location) + CGFloat(part.length) / 2) / CGFloat(source.range.length)
                    let q = box.quad.map(flipPoint)
                    let top = TextBandFinder.lerp(q[0], q[1], f), bottom = TextBandFinder.lerp(q[3], q[2], f)
                    return locate(text, part, prior: TextBandFinder.mid(top, bottom), in: strips, size: size, image: image, local: &local)
                }
                if found.count == 2 { quads = found }
            }
            guard !quads.isEmpty else {
                boxes.append(box)
                continue
            }
            for (i, q) in quads.enumerated() {
                let flipped = ScanAnalyzer.flip(q)
                boxes.append(HighlightBox(id: i == 0 ? box.id : UUID(), clusterID: box.clusterID,
                                          rect: ScanAnalyzer.bounds(of: flipped), quad: flipped, source: box.source))
            }
        }
        var refined = result
        refined.boxes = boxes
        return refined
    }

    // MARK: - 识别一块区域

    /// 识别图片里的一块区域（region：整图归一化、原点左下），返回其中的行（整图坐标）
    static func recognize(_ image: CGImage, region: CGRect) -> [Line] {
        let W = CGFloat(image.width), H = CGFloat(image.height)
        // 像素坐标原点在左上
        let pixel = CGRect(x: region.minX * W, y: (1 - region.maxY) * H, width: region.width * W, height: region.height * H).integral
            .intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard pixel.width >= 16, pixel.height >= 16, let crop = image.cropping(to: pixel) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: crop, options: [:]).perform([request])) != nil else { return [] }
        let observations = request.results ?? []

        // 先在这块区域自己的坐标里找文字带（和整页识别一样）
        var recognized: [RecognizedLine] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let string = candidate.string
            return RecognizedLine(
                rangeInText: NSRange(location: 0, length: (string as NSString).length),
                text: string, boundingBox: obs.boundingBox, boxForRange: { _ in nil },
                quad: [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft],
                quadForRange: { range in
                    guard let r = Range(range, in: string), let box = try? candidate.boundingBox(for: r) else { return nil }
                    return [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft]
                })
        }
        TextBandFinder.refine(&recognized, image: crop)

        // 区域坐标（原点左下）→ 整图坐标（原点左下）
        let x0 = pixel.minX / W, sx = pixel.width / W
        let y0 = 1 - pixel.maxY / H, sy = pixel.height / H
        func toPage(_ p: CGPoint) -> CGPoint { CGPoint(x: x0 + p.x * sx, y: y0 + p.y * sy) }
        let cw = pixel.width, ch = pixel.height
        return recognized.compactMap { line in
            guard line.quad.count == 4 else { return nil }
            let q = line.quad
            let length = hypot((TextBandFinder.mid(q[1], q[2]).x - TextBandFinder.mid(q[0], q[3]).x) * cw,
                               (TextBandFinder.mid(q[1], q[2]).y - TextBandFinder.mid(q[0], q[3]).y) * ch)
            let height = (hypot((q[0].x - q[3].x) * cw, (q[0].y - q[3].y) * ch) + hypot((q[1].x - q[2].x) * cw, (q[1].y - q[2].y) * ch)) / 2
            let ns = line.text as NSString
            let chars = max(ScanAnalyzer.weightedLength(ns, NSRange(location: 0, length: ns.length)), 1)
            let looseness = length > 0 ? height / (length / chars) : .greatestFiniteMagnitude
            return Line(utf16: Array(line.text.utf16), quad: q.map(toPage), quadFor: { range in
                guard let raw = line.quadForRange(range), raw.count == 4 else { return nil }
                return (ScanAnalyzer.bandFitted(raw, line: line) ?? raw).map(toPage)
            }, looseness: looseness, x0: x0, x1: x0 + sx)
        }
    }

    // MARK: - 找同一段文字

    struct Candidate {
        let quad: [CGPoint]
        let context: Int
        let distance: CGFloat
        let margin: CGFloat
        let looseness: CGFloat
    }

    /// 在 pool 的各行里找 text[range] 这段文字，返回最可信的一处（整图坐标）。
    /// 竖条里那一行仍然很弯（looseness 大）时，在找到的位置附近切一小块重新识别再找一次。
    static func locate(_ text: [UInt16], _ range: NSRange, prior: CGPoint, in pool: [Line], size: CGSize,
                       image: CGImage, local: inout [(region: CGRect, lines: [Line])]) -> [CGPoint]? {
        guard let best = bestCandidate(text, range, prior: prior, in: pool, size: size) else { return nil }
        guard best.looseness > looseLimit else { return best.quad }
        // 小块：这段文字左右各留约 4.5 个字（够核对前后文），上下各 3 个字高
        let glyph = glyphSize(best.quad, size: size)
        let c = center(best.quad)
        let halfWidth = (CGFloat(range.length) + 9) / 2 * glyph / size.width
        let halfHeight = 3 * glyph / size.height
        let region = CGRect(x: c.x - halfWidth, y: c.y - halfHeight, width: 2 * halfWidth, height: 2 * halfHeight)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        // 附近已经切过的小块能覆盖这段文字时直接用
        let nearby: [Line]
        if let cached = local.first(where: { $0.region.insetBy(dx: halfWidth * 0.6, dy: halfHeight * 0.3).contains(c) }) {
            nearby = cached.lines
        } else {
            nearby = recognize(image, region: region)
            local.append((region, nearby))
        }
        if let again = bestCandidate(text, range, prior: c, in: nearby, size: size, maxDistance: 1.5),
           again.looseness < best.looseness {
            return again.quad
        }
        return best.quad
    }

    static func bestCandidate(_ text: [UInt16], _ range: NSRange, prior: CGPoint, in pool: [Line], size: CGSize,
                              maxDistance: CGFloat = maxDistance) -> Candidate? {
        let n = range.length
        guard n > 0, range.location >= 0, range.location + n <= text.count else { return nil }
        let key = Array(text[range.location..<(range.location + n)])
        let allowedMisses = n >= 4 ? 1 : 0
        var best: (score: (Int, CGFloat, CGFloat), candidate: Candidate)?
        for line in pool {
            let t = line.utf16
            guard t.count >= n else { continue }
            for p in 0...(t.count - n) {
                var misses = 0
                for i in 0..<n where !same(t[p + i], key[i]) {
                    misses += 1
                    if misses > allowedMisses { break }
                }
                guard misses <= allowedMisses else { continue }
                guard let quad = line.quadFor(NSRange(location: p, length: n)), quad.count == 4 else { continue }
                let glyph = glyphSize(quad, size: size)
                guard glyph > 0 else { continue }
                // 被这块区域的边界切到的字不可信
                let gx = glyph / size.width
                let xs = quad.map(\.x)
                guard let minX = xs.min(), let maxX = xs.max() else { continue }
                if line.x0 > 0.001, minX < line.x0 + 0.6 * gx { continue }
                if line.x1 < 0.999, maxX > line.x1 - 0.6 * gx { continue }
                // 前后文
                var left = 0, right = 0
                let availableLeft = min(contextLength, range.location, p)
                while left < availableLeft, same(text[range.location - 1 - left], t[p - 1 - left]) { left += 1 }
                let availableRight = min(contextLength, text.count - range.location - n, t.count - p - n)
                while right < availableRight, same(text[range.location + n + right], t[p + n + right]) { right += 1 }
                let context = left + right
                let complete = left == availableLeft && right == availableRight
                if misses > 0, context < 3 { continue }
                let needed = n <= 2 ? 3 : (n <= 4 ? 2 : 0)
                guard context >= needed || (complete && availableLeft + availableRight >= 1 && n >= 3) else { continue }
                // 离原来的框
                let c = center(quad)
                let distance = hypot((c.x - prior.x) * size.width, (c.y - prior.y) * size.height) / glyph
                guard distance <= maxDistance else { continue }
                let margin = min(minX - line.x0, line.x1 - maxX) / gx
                let candidate = Candidate(quad: quad, context: context - 2 * misses, distance: distance, margin: margin,
                                          looseness: line.looseness)
                let score = (candidate.context, -distance, margin)
                if best == nil || score > best!.score { best = (score, candidate) }
            }
        }
        return best?.candidate
    }

    // MARK: - 小工具

    /// 全角空格是整页识别时把外文片段遮掉留下的，和什么字都算一致
    static func same(_ a: UInt16, _ b: UInt16) -> Bool { a == b || a == 0x3000 || b == 0x3000 }

    static func isHorizontal(_ line: RecognizedLine) -> Bool {
        line.boundingBox.width > line.boundingBox.height * 1.5
    }

    static func center(_ q: [CGPoint]) -> CGPoint {
        guard !q.isEmpty else { return .zero }
        return CGPoint(x: q.map(\.x).reduce(0, +) / CGFloat(q.count), y: q.map(\.y).reduce(0, +) / CGFloat(q.count))
    }

    /// 四边形左右两条边的平均长度（像素），约等于字高
    static func glyphSize(_ q: [CGPoint], size: CGSize) -> CGFloat {
        guard q.count == 4 else { return 0 }
        let l = hypot((q[0].x - q[3].x) * size.width, (q[0].y - q[3].y) * size.height)
        let r = hypot((q[1].x - q[2].x) * size.width, (q[1].y - q[2].y) * size.height)
        return (l + r) / 2
    }

    static func flipPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
}
