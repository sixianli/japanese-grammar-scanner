import CoreGraphics
import Foundation

/// 弯曲书页上一行文字真正所在的「文字带」。
///
/// 书页弯曲时，一行字是一条弧线，Vision 只能给出一个把整条弧线都包进去的直四边形，
/// 高度常常是字高的 2～4 倍，里面还夹着上下行的字。直接用它（或按它切出来的单词框）画高亮，
/// 框会盖住好几行、互相重叠。
///
/// 这里沿着这一行，在图片像素里追踪墨迹最集中、并且连贯的一条带子（动态规划），
/// 得到每个位置上文字的中心；高亮框只取这条带子附近、约 1.2 倍字高的范围。
/// 一页上按「最不含糊」的行先算，算完把这一行的文字从图里抹掉，后面的行就不会抢到同一行字。
/// 算法在 95 张实拍照片上评测过（docs/ocr-eval/runs/），Python 版本见 tools/text_band.py。
struct TextBand {
    /// 字高 / 整行四边形高度（0～1）
    let glyph: CGFloat
    /// 各列中心在行方向上的位置（0～1）
    let ts: [CGFloat]
    /// 各列文字带中心（0 = 四边形上边，1 = 下边），已平滑
    let centers: [CGFloat]
    /// 未平滑的中心，用来判断路径是否突然跳到了别的行
    let raw: [CGFloat]

    func center(at t: CGFloat) -> CGFloat {
        guard let first = ts.first, let last = ts.last else { return 0.5 }
        if t <= first { return centers[0] }
        if t >= last { return centers[centers.count - 1] }
        let n = CGFloat(ts.count)
        let x = t * n - 0.5
        let i = min(max(Int(x), 0), ts.count - 2)
        let f = x - CGFloat(i)
        return centers[i] + (centers[i + 1] - centers[i]) * f
    }

    /// 在 [t0, t1] 附近，路径单列移动超过 maxJump 个字高，说明可能跳到了别的行，不可信
    func isSteady(from t0: CGFloat, to t1: CGFloat, maxJump: CGFloat = 0.5) -> Bool {
        let n = raw.count
        guard n > 1 else { return true }
        let j0 = max(0, Int(t0 * CGFloat(n)) - 1)
        let j1 = min(n - 1, Int((t1 * CGFloat(n)).rounded(.up)) + 1)
        guard j1 > j0 else { return true }
        for j in j0..<j1 where abs(raw[j + 1] - raw[j]) / glyph > maxJump { return false }
        return true
    }
}

enum TextBandFinder {
    /// 为每一行计算文字带（不需要收紧的行为 nil）。坐标都是 Vision 归一化坐标（原点左下）。
    static func refine(_ lines: inout [RecognizedLine], image: CGImage) {
        guard !lines.isEmpty, let page = GrayPage(image: image, maxSide: 1600) else { return }
        // 先算最不含糊（四边形高度 / 字高 最小）的行
        let order = lines.indices.sorted { ambiguity(lines[$0], page) < ambiguity(lines[$1], page) }
        for i in order {
            let q = lines[i].quad
            guard q.count == 4 else { continue }
            let band = findBand(line: lines[i], page: page)
            lines[i].band = band
            page.erase(q: q.map(page.pixel), band: band)
        }
    }

    private static func geometry(_ line: RecognizedLine, _ page: GrayPage) -> (length: CGFloat, height: CGFloat, glyph: CGFloat)? {
        guard line.quad.count == 4 else { return nil }
        let q = line.quad.map(page.pixel)
        let length = dist(mid(q[0], q[3]), mid(q[1], q[2]))
        let height = (dist(q[0], q[3]) + dist(q[1], q[2])) / 2
        let ns = line.text as NSString
        let n = ScanAnalyzer.weightedLength(ns, NSRange(location: 0, length: ns.length))
        guard n >= 2, length > 0 else { return nil }
        return (length, height, length / n)
    }

    private static func ambiguity(_ line: RecognizedLine, _ page: GrayPage) -> CGFloat {
        guard let g = geometry(line, page), g.glyph > 0 else { return .greatestFiniteMagnitude }
        return g.height / g.glyph
    }

    static func findBand(line: RecognizedLine, page: GrayPage) -> TextBand? {
        guard let g = geometry(line, page) else { return nil }
        let (length, height, h) = g
        // 已经贴字、竖排或很短的行不用处理
        guard height >= 1.45 * h, length >= height * 1.5 else { return nil }
        let q = line.quad.map(page.pixel)
        let n = max(4, Int((length / h).rounded()))
        let m = max(8, Int(height.rounded()))
        let hr = max(2, Int((h * CGFloat(m) / height).rounded()))
        guard hr < m else { return nil }

        // 每列（约一个字宽）沿高度方向的平均灰度
        var ink = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: m), count: n)
        var all: [CGFloat] = []
        all.reserveCapacity(n * m)
        for j in 0..<n {
            let t = (CGFloat(j) + 0.5) / CGFloat(n)
            for i in 0..<m {
                let s = (CGFloat(i) + 0.5) / CGFloat(m)
                var sum: CGFloat = 0
                for k in -2...2 {
                    let tt = min(max(t + CGFloat(k) / 5 / CGFloat(n), 0), 1)
                    let top = lerp(q[0], q[1], tt), bottom = lerp(q[3], q[2], tt)
                    sum += page.sample(lerp(top, bottom, s))
                }
                ink[j][i] = sum / 5
                all.append(sum / 5)
            }
        }
        all.sort()
        let background = all[min(all.count - 1, Int(CGFloat(all.count - 1) * 0.9))]

        // 每列每个起点、高度为一个字高的窗口里的墨迹量
        let k = m - hr + 1
        var win = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: k), count: n)
        for j in 0..<n {
            var prefix = [CGFloat](repeating: 0, count: m + 1)
            for i in 0..<m { prefix[i + 1] = prefix[i] + max(background - ink[j][i], 0) }
            for i in 0..<k { win[j][i] = prefix[i + hr] - prefix[i] }
        }

        // 动态规划：找墨迹总量最大、又平滑的连贯路径。
        // 相邻两列的起点最多相差 0.25 个字高；每移动一行再扣一点分（一列典型墨迹量 / 字高行数）。
        // 真正的文字行是平滑的弧线；不加这个约束时，在行距很密、倾斜的书页上路径会顺着墨迹滑到相邻的行。
        // 参数在 95 张实拍照片上对比选定（tools/text_band.py 的 DFRAC / LAM）。
        let d = max(1, Int((0.25 * CGFloat(hr)).rounded(.up)))
        let columnPeaks = win.map { $0.max() ?? 0 }.sorted()
        let unit = (columnPeaks.isEmpty ? 0 : columnPeaks[columnPeaks.count / 2]) / CGFloat(hr)
        let movePenalty = 1.0 * unit
        var score = win[0]
        var back = [[Int]](repeating: [Int](repeating: 0, count: k), count: n)
        for j in 1..<n {
            var next = [CGFloat](repeating: 0, count: k)
            for i in 0..<k {
                let lo = max(0, i - d), hi = min(k - 1, i + d)
                var best = lo
                var bestScore = -CGFloat.greatestFiniteMagnitude
                for c in lo...hi {
                    let v = score[c] - movePenalty * CGFloat(abs(c - i))
                    if v > bestScore { bestScore = v; best = c }
                }
                next[i] = bestScore + win[j][i]
                back[j][i] = best
            }
            score = next
        }
        var idx = score.indices.max { score[$0] < score[$1] } ?? 0
        var path = [Int](repeating: 0, count: n)
        path[n - 1] = idx
        if n > 1 {
            for j in stride(from: n - 1, to: 0, by: -1) {
                idx = back[j][idx]
                path[j - 1] = idx
            }
        }
        let raw = path.map { (CGFloat($0) + CGFloat(hr) / 2) / CGFloat(m) }
        var smooth = raw
        if n >= 3 {
            for j in 0..<n {
                let a = raw[max(j - 1, 0)], b = raw[j], c = raw[min(j + 1, n - 1)]
                smooth[j] = (a + b + c) / 3
            }
        }
        return TextBand(glyph: h / height,
                        ts: (0..<n).map { (CGFloat($0) + 0.5) / CGFloat(n) },
                        centers: smooth, raw: raw)
    }

    // MARK: - 几何

    static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

/// 灰度页面（缩小到最长边不超过 maxSide），可以采样，也可以把已经认领的文字带抹成背景色
final class GrayPage {
    let width: Int
    let height: Int
    private let context: CGContext
    private let data: UnsafeMutablePointer<UInt8>
    private let background: UInt8

    init?(image: CGImage, maxSide: Int) {
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * scale))
        let h = max(1, Int(CGFloat(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // 背景灰度：全页 90% 分位
        var histogram = [Int](repeating: 0, count: 256)
        let count = w * h
        for i in Swift.stride(from: 0, to: count, by: 7) { histogram[Int(ptr[i])] += 1 }
        let total = histogram.reduce(0, +)
        var acc = 0, value = 255
        for v in 0..<256 {
            acc += histogram[v]
            if CGFloat(acc) >= CGFloat(total) * 0.9 { value = v; break }
        }
        width = w
        height = h
        context = ctx
        data = ptr
        background = UInt8(value)
    }

    /// Vision 归一化坐标（原点左下） → 像素坐标（原点左上）
    func pixel(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * CGFloat(width), y: (1 - p.y) * CGFloat(height))
    }

    /// 双线性采样（像素坐标，原点左上）
    func sample(_ p: CGPoint) -> CGFloat {
        let x = min(max(p.x, 0), CGFloat(width) - 1.001)
        let y = min(max(p.y, 0), CGFloat(height) - 1.001)
        let x0 = Int(x), y0 = Int(y)
        let fx = x - CGFloat(x0), fy = y - CGFloat(y0)
        func v(_ xx: Int, _ yy: Int) -> CGFloat { CGFloat(data[yy * width + xx]) }
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        return v(x0, y0) * (1 - fx) * (1 - fy) + v(x1, y0) * fx * (1 - fy)
            + v(x0, y1) * (1 - fx) * fy + v(x1, y1) * fx * fy
    }

    /// 把这一行的文字带（没有文字带时整行四边形）抹成背景色。q 为像素坐标（原点左上）。
    func erase(q: [CGPoint], band: TextBand?) {
        var polygon: [CGPoint]
        if let band {
            let half = 0.55 * band.glyph
            let ts = [0] + band.ts + [1]
            let cs = [band.centers[0]] + band.centers + [band.centers[band.centers.count - 1]]
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            for (t, c) in zip(ts, cs) {
                let a = TextBandFinder.lerp(q[0], q[1], t), b = TextBandFinder.lerp(q[3], q[2], t)
                top.append(TextBandFinder.lerp(a, b, c - half))
                bottom.append(TextBandFinder.lerp(a, b, c + half))
            }
            polygon = top + bottom.reversed()
        } else {
            polygon = q
        }
        // CGContext 原点在左下：y 翻转
        let path = CGMutablePath()
        path.addLines(between: polygon.map { CGPoint(x: $0.x, y: CGFloat(height) - $0.y) })
        path.closeSubpath()
        context.setFillColor(gray: CGFloat(background) / 255, alpha: 1)
        context.addPath(path)
        context.fillPath()
    }
}
