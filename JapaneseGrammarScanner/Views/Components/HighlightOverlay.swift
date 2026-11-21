import SwiftUI

enum ImageFit {
    case fit, fill

    /// 图片按 fit / fill 方式放进容器后实际占据的矩形。
    func displayedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: container) }
        let sx = container.width / imageSize.width
        let sy = container.height / imageSize.height
        let scale = self == .fit ? min(sx, sy) : max(sx, sy)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// 在图片 / 取景画面上绘制可点击的语法框：贴着文字的淡橙色细实线框，框内一层极淡的橙色，原文的字不变色。
/// 相机实时取景、识别结果页（拍照 / 相册）、放大查看三处统一用这一种样式，颜色固定不随主题。
/// - 点中的那一下底色加深，回到结果页后恢复。
/// - 一个框里有多个语法时不另外标数字，点开后在列表里选。
/// - 相邻的两个框之间始终留一道细缝，四角圆一点，不会糊成一条粗线。
struct HighlightOverlay: View {
    let result: ScanResult
    let imageSize: CGSize
    let fit: ImageFit
    let library: GrammarLibrary
    var selectedClusterID: Int? = nil
    /// 线宽：放大查看时按放大倍数变细，保持屏幕上看起来一样粗（缝隙、圆角、虚线间隔按同样比例缩放）
    var lineWidth: CGFloat = 1.2
    let onTap: (HighlightCluster) -> Void

    var body: some View {
        GeometryReader { geo in
            let display = fit.displayedRect(imageSize: imageSize, in: geo.size)
            let clustersByID = Dictionary(uniqueKeysWithValues: result.clusters.map { ($0.id, $0) })
            let unit = lineWidth / 1.2
            let quads = HighlightGeometry.layout(result.boxes.map { box in
                box.quad.map { CGPoint(x: display.minX + $0.x * display.width, y: display.minY + $0.y * display.height) }
            }, unit: unit)
            ForEach(Array(result.boxes.enumerated()), id: \.element.id) { i, box in
                if let cluster = clustersByID[box.clusterID], quads[i].count == 4 {
                    let bounds = HighlightGeometry.bounds(quads[i])
                    let local = quads[i].map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) }
                    let shape = QuadShape(points: local, cornerRadius: 3 * unit)
                    let selected = cluster.id == selectedClusterID
                    let style = HighlightStyle.of(selected: selected)
                    shape
                        .fill(Theme.scanHighlight.opacity(style.fillOpacity))
                        .overlay(
                            shape.stroke(Theme.scanHighlight.opacity(style.strokeOpacity),
                                         style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        )
                        .frame(width: max(bounds.width, 4), height: max(bounds.height, 4))
                        .contentShape(shape.inset(by: -4))
                        .position(x: bounds.midX, y: bounds.midY)
                        .onTapGesture { onTap(cluster) }
                        .accessibilityElement()
                        .accessibilityLabel(cluster.grammarIDs.compactMap { library.point(id: $0)?.displayTitle }.joined(separator: "、"))
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier(selected ? "highlight.box.selected" : "highlight.box")
                }
            }
        }
    }
}

/// 语法框的样式：所有框都是同一种淡橙色细实线 + 极淡底色（不再分虚线 / 实线）；
/// 点中的那一下底色加深作为反馈，返回结果页后恢复。
struct HighlightStyle: Equatable {
    let fillOpacity: Double
    let strokeOpacity: Double
    /// 线型：始终是实线
    let dashed: Bool

    static func of(selected: Bool) -> HighlightStyle {
        HighlightStyle(fillOpacity: selected ? 0.28 : 0.10, strokeOpacity: 0.8, dashed: false)
    }
}

/// 高亮框的几何处理：四周略微放宽一点，相邻的框在交界处各自收回，中间留一道细缝。
enum HighlightGeometry {
    /// - Parameters:
    ///   - quads: 每个框的四个角（视图坐标：左上、右上、右下、左下）
    ///   - unit: 缩放系数（放大查看时 < 1）
    static func layout(_ quads: [[CGPoint]], unit: CGFloat = 1) -> [[CGPoint]] {
        let pad = 2 * unit          // 框比文字略大一点，线不压在笔画上
        let gap = 3 * unit          // 相邻两个框之间的缝
        var out = quads.map { q -> [CGPoint] in
            guard q.count == 4 else { return q }
            let (d, n) = axes(q)
            return [q[0] - d * pad - n * pad, q[1] + d * pad - n * pad, q[2] + d * pad + n * pad, q[3] - d * pad + n * pad]
        }
        for i in out.indices where out[i].count == 4 {
            for j in out.indices where j != i && out[j].count == 4 {
                let (d, n) = axes(out[i])
                // 同一行：沿垂直方向的范围重叠过半
                let ni = range(out[i], n), nj = range(out[j], n)
                let overlap = min(ni.1, nj.1) - max(ni.0, nj.0)
                guard overlap > 0.5 * min(ni.1 - ni.0, nj.1 - nj.0) else { continue }
                // i 在左、j 在右，并且两者挨着（重叠或间隔小于缝宽）
                let di = range(out[i], d), dj = range(out[j], d)
                guard di.0 < dj.0, dj.0 - di.1 < gap else { continue }
                let mid = (di.1 + dj.0) / 2
                let moveI = (mid - gap / 2) - di.1
                let moveJ = (mid + gap / 2) - dj.0
                out[i][1] = out[i][1] + d * moveI
                out[i][2] = out[i][2] + d * moveI
                out[j][0] = out[j][0] + d * moveJ
                out[j][3] = out[j][3] + d * moveJ
            }
        }
        return out
    }

    /// 文字方向（左→右）和垂直方向（上→下）的单位向量
    private static func axes(_ q: [CGPoint]) -> (CGPoint, CGPoint) {
        (normalized(q[1] - q[0], fallback: CGPoint(x: 1, y: 0)), normalized(q[3] - q[0], fallback: CGPoint(x: 0, y: 1)))
    }

    private static func range(_ q: [CGPoint], _ axis: CGPoint) -> (CGFloat, CGFloat) {
        let v = q.map { $0.x * axis.x + $0.y * axis.y }
        return (v.min() ?? 0, v.max() ?? 0)
    }

    private static func normalized(_ p: CGPoint, fallback: CGPoint) -> CGPoint {
        let len = hypot(p.x, p.y)
        return len > 0.0001 ? CGPoint(x: p.x / len, y: p.y / len) : fallback
    }

    static func bounds(_ p: [CGPoint]) -> CGRect {
        let xs = p.map(\.x), ys = p.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
}

/// 贴着文字的四边形（角点为视图内坐标：左上、右上、右下、左下），四角为圆角
struct QuadShape: InsettableShape {
    var points: [CGPoint]
    var cornerRadius: CGFloat = 0
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        guard points.count == 4 else { return Path(rect.insetBy(dx: inset, dy: inset)) }
        // 向外扩（inset 为负）或向内收：沿各点到中心的方向移动
        let cx = points.map(\.x).reduce(0, +) / 4, cy = points.map(\.y).reduce(0, +) / 4
        let p = points.map { pt -> CGPoint in
            let dx = pt.x - cx, dy = pt.y - cy
            let len = max(hypot(dx, dy), 0.001)
            return CGPoint(x: pt.x - dx / len * inset, y: pt.y - dy / len * inset)
        }
        var path = Path()
        guard cornerRadius > 0 else {
            path.move(to: p[0])
            for q in p.dropFirst() { path.addLine(to: q) }
            path.closeSubpath()
            return path
        }
        // 从第一条边的中点开始，每个角用切线圆弧连接
        let start = CGPoint(x: (p[0].x + p[1].x) / 2, y: (p[0].y + p[1].y) / 2)
        path.move(to: start)
        for k in 1...4 {
            let corner = p[k % 4], next = p[(k + 1) % 4]
            path.addArc(tangent1End: corner, tangent2End: next, radius: cornerRadius)
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> QuadShape {
        var s = self
        s.inset += amount
        return s
    }
}
