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

/// 在图片 / 取景画面上绘制可点击的语法高亮框。
struct HighlightOverlay: View {
    let result: ScanResult
    let imageSize: CGSize
    let fit: ImageFit
    let library: GrammarLibrary
    var selectedClusterID: Int? = nil
    /// 线宽：放大查看时按放大倍数变细，保持屏幕上看起来一样粗
    var lineWidth: CGFloat = 1.5
    var showsCountBadge = true
    let onTap: (HighlightCluster) -> Void

    var body: some View {
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
