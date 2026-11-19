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

/// 高亮的画法
enum HighlightStyle {
    /// 线框（相机实时取景：画面每秒变化，字变色会闪，线框最清楚）
    case boxes
    /// 荧光笔：语法所在的字染成主题色，底下垫一层淡色；相邻的两段深浅交替、中间留缝（识别结果页）
    case marker(ink: CGImage?)
}

/// 在图片 / 取景画面上绘制可点击的语法高亮。
struct HighlightOverlay: View {
    let result: ScanResult
    let imageSize: CGSize
    let fit: ImageFit
    let library: GrammarLibrary
    var selectedClusterID: Int? = nil
    /// 线宽：放大查看时按放大倍数变细，保持屏幕上看起来一样粗
    var lineWidth: CGFloat = 1.5
    var showsCountBadge = true
    var style: HighlightStyle = .boxes
    let onTap: (HighlightCluster) -> Void

    var body: some View {
        switch style {
        case .boxes: boxes
        case .marker(let ink): MarkerHighlight(result: result, imageSize: imageSize, fit: fit, library: library,
                                               selectedClusterID: selectedClusterID, showsCountBadge: showsCountBadge,
                                               ink: ink, onTap: onTap)
        }
    }

    private var boxes: some View {
        GeometryReader { geo in
            let display = fit.displayedRect(imageSize: imageSize, in: geo.size)
            let clustersByID = Dictionary(uniqueKeysWithValues: result.clusters.map { ($0.id, $0) })
            ForEach(result.boxes) { box in
                if let cluster = clustersByID[box.clusterID] {
                    // 照片上的框：贴着文字的四边形（斜拍时跟文字一起倾斜），主题色细线 + 外圈白边 + 淡填充。
                    // 颜色不随深浅色模式变化（照片里的纸面总是浅色）；线条半透明，框交叠时下面的字仍看得清
                    let rect = CGRect(
                        x: display.minX + box.rect.minX * display.width,
                        y: display.minY + box.rect.minY * display.height,
                        width: box.rect.width * display.width,
                        height: box.rect.height * display.height
                    )
                    // 四边形角点换算到这个框自己的坐标里
                    let points = box.quad.map {
                        CGPoint(x: display.minX + $0.x * display.width - rect.minX,
                                y: display.minY + $0.y * display.height - rect.minY)
                    }
                    let shape = QuadShape(points: points)
                    let color = clusterColor(cluster)
                    let selected = cluster.id == selectedClusterID
                    let width = selected ? lineWidth * 1.4 : lineWidth
                    shape
                        .fill(color.opacity(selected ? 0.26 : 0.10))
                        // 外圈白边：在任何底色上把框「托」出来
                        .overlay(shape.stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: width + 1.5, lineJoin: .round)))
                        .overlay(shape.stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: width, lineJoin: .round)))
                        .overlay(alignment: .topTrailing) {
                            if cluster.grammarIDs.count > 1 && showsCountBadge {
                                Text(verbatim: "\(cluster.grammarIDs.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 15, height: 15)
                                    .background(color, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 1.2))
                                    .offset(x: 7, y: -7)
                            }
                        }
                        .frame(width: max(rect.width, 4), height: max(rect.height, 4))
                        .contentShape(shape.inset(by: -4))
                        .position(x: rect.midX, y: rect.midY)
                        .onTapGesture { onTap(cluster) }
                        .accessibilityElement()
                        .accessibilityLabel(cluster.grammarIDs.compactMap { library.point(id: $0)?.displayTitle }.joined(separator: "、"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("highlight.box")
                }
            }
        }
    }

    private func clusterColor(_ cluster: HighlightCluster) -> Color {
        // 统一用主题色的深色版本（不随深浅色模式变化）
        Theme.photoHighlight
    }
}

/// 贴着文字的四边形（角点为视图内坐标：左上、右上、右下、左下），角稍微圆一点
struct QuadShape: InsettableShape {
    var points: [CGPoint]
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
        path.move(to: p[0])
        for q in p.dropFirst() { path.addLine(to: q) }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> QuadShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// 荧光笔样式：字变主题色 + 淡色底；相邻的两段深浅交替，两段之间留一道细缝
private struct MarkerHighlight: View {
    let result: ScanResult
    let imageSize: CGSize
    let fit: ImageFit
    let library: GrammarLibrary
    let selectedClusterID: Int?
    let showsCountBadge: Bool
    let ink: CGImage?
    let onTap: (HighlightCluster) -> Void

    var body: some View {
        GeometryReader { geo in
            let display = fit.displayedRect(imageSize: imageSize, in: geo.size)
            let shades = MarkerShading.shades(for: result, imageSize: imageSize)
            let clustersByID = Dictionary(uniqueKeysWithValues: result.clusters.map { ($0.id, $0) })
            let quads: [MarkerPiece] = result.boxes.map { box in
                let pts = box.quad.map { CGPoint(x: display.minX + $0.x * display.width, y: display.minY + $0.y * display.height) }
                return MarkerPiece(box: box, points: MarkerShading.shortened(pts), shade: shades[box.clusterID] ?? 0)
            }
            ZStack(alignment: .topLeading) {
                // 1. 淡色荧光笔底（选中的那段更深）
                ForEach(quads) { item in
                    let selected = item.box.clusterID == selectedClusterID
                    QuadShape(points: item.points)
                        .fill(MarkerShading.tint(item.shade, selected: selected))
                }
                // 2. 把这些位置上的笔画染成主题色（两种深浅各一层）
                if let ink {
                    ForEach(0..<2, id: \.self) { shade in
                        MarkerShading.textColor(shade)
                            .mask {
                                Image(decorative: ink, scale: 1)
                                    .resizable()
                                    .frame(width: display.width, height: display.height)
                                    .position(x: display.midX, y: display.midY)
                                    .luminanceToAlpha()
                            }
                            .mask {
                                MultiQuadShape(quads: quads.filter { $0.shade == shade }.map(\.points))
                            }
                    }
                    .allowsHitTesting(false)
                }
                // 3. 点击区域（每个片段一个，稍微放大一点好点中）
                ForEach(quads) { item in
                    if let cluster = clustersByID[item.box.clusterID] {
                        let full = item.box.quad.map { CGPoint(x: display.minX + $0.x * display.width, y: display.minY + $0.y * display.height) }
                        let bounds = MarkerShading.bounds(full)
                        let local = full.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) }
                        let shape = QuadShape(points: local)
                        Color.clear
                            .frame(width: max(bounds.width, 4), height: max(bounds.height, 4))
                            .contentShape(shape.inset(by: -4))
                            .overlay(alignment: .topTrailing) {
                                if cluster.grammarIDs.count > 1 && showsCountBadge && item.box.id == firstBox(of: cluster.id) {
                                    Text(verbatim: "\(cluster.grammarIDs.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 15, height: 15)
                                        .background(MarkerShading.textColor(item.shade), in: Circle())
                                        .overlay(Circle().stroke(.white, lineWidth: 1.2))
                                        .offset(x: 7, y: -7)
                                }
                            }
                            .position(x: bounds.midX, y: bounds.midY)
                            .onTapGesture { onTap(cluster) }
                            .accessibilityElement()
                            .accessibilityLabel(cluster.grammarIDs.compactMap { library.point(id: $0)?.displayTitle }.joined(separator: "、"))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("highlight.box")
                    }
                }
            }
        }
    }

    private func firstBox(of clusterID: Int) -> UUID? {
        result.boxes.first { $0.clusterID == clusterID }?.id
    }
}

private struct MarkerPiece: Identifiable {
    let box: HighlightBox
    let points: [CGPoint]
    let shade: Int
    var id: UUID { box.id }
}

/// 荧光笔样式的配色和几何
enum MarkerShading {
    /// 给每个高亮块分配深浅（0 / 1）：挨在一起的两块尽量不同
    static func shades(for result: ScanResult, imageSize: CGSize) -> [Int: Int] {
        let w = max(imageSize.width, 1), h = max(imageSize.height, 1)
        // 每个块的各个片段（像素坐标）及其字高
        var pieces: [Int: [(rect: CGRect, height: CGFloat)]] = [:]
        for box in result.boxes {
            let pts = box.quad.map { CGPoint(x: $0.x * w, y: $0.y * h) }
            guard pts.count == 4 else { continue }
            let height = (hypot(pts[0].x - pts[3].x, pts[0].y - pts[3].y) + hypot(pts[1].x - pts[2].x, pts[1].y - pts[2].y)) / 2
            pieces[box.clusterID, default: []].append((bounds(pts), height))
        }
        var assigned: [Int: Int] = [:]
        for id in pieces.keys.sorted() {
            var used = Set<Int>()
            for (other, shade) in assigned {
                if touches(pieces[id] ?? [], pieces[other] ?? []) { used.insert(shade) }
            }
            assigned[id] = used.contains(0) ? 1 : 0
        }
        return assigned
    }

    private static func touches(_ a: [(rect: CGRect, height: CGFloat)], _ b: [(rect: CGRect, height: CGFloat)]) -> Bool {
        for x in a {
            for y in b {
                let gap = 0.35 * min(x.height, y.height)
                if x.rect.insetBy(dx: -gap, dy: -gap / 2).intersects(y.rect) { return true }
            }
        }
        return false
    }

    /// 两端各收进约 0.14 个字高，相邻两段之间露出一道细缝
    static func shortened(_ p: [CGPoint]) -> [CGPoint] {
        guard p.count == 4 else { return p }
        let height = (hypot(p[0].x - p[3].x, p[0].y - p[3].y) + hypot(p[1].x - p[2].x, p[1].y - p[2].y)) / 2
        let length = max(hypot(p[1].x - p[0].x, p[1].y - p[0].y), 0.001)
        let t = min(0.14 * height / length, 0.2)
        func mv(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        return [mv(p[0], p[1]), mv(p[1], p[0]), mv(p[2], p[3]), mv(p[3], p[2])]
    }

    static func bounds(_ p: [CGPoint]) -> CGRect {
        let xs = p.map(\.x), ys = p.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// 字的颜色：主题色 / 更深一档的主题色（不随深浅色模式变化，照片里的纸总是浅色）
    static func textColor(_ shade: Int) -> Color {
        shade == 0 ? Theme.photoHighlight : Theme.photoHighlightDeep
    }

    static func tint(_ shade: Int, selected: Bool) -> Color {
        let base = shade == 0 ? 0.20 : 0.34
        return Theme.photoHighlight.opacity(selected ? base + 0.22 : base)
    }
}

/// 多个四边形合成一个形状（用作遮罩）
struct MultiQuadShape: Shape {
    var quads: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for q in quads where q.count == 4 {
            path.move(to: q[0])
            for p in q.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
        }
        return path
    }
}
