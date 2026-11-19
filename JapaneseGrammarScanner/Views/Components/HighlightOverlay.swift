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
    var lineWidth: CGFloat = 2
    var showsCountBadge = true
    let onTap: (HighlightCluster) -> Void

    var body: some View {
        GeometryReader { geo in
            let display = fit.displayedRect(imageSize: imageSize, in: geo.size)
            let clustersByID = Dictionary(uniqueKeysWithValues: result.clusters.map { ($0.id, $0) })
            ForEach(result.boxes) { box in
                if let cluster = clustersByID[box.clusterID] {
                    // 照片上的框：主题色（深一档）实线 + 外圈白边 + 淡填充。
                    // 颜色不随深浅色模式变化——照片里的纸面总是浅色的，书页偏灰、有阴影时也要看得清
                    let rect = CGRect(
                        x: display.minX + box.rect.minX * display.width,
                        y: display.minY + box.rect.minY * display.height,
                        width: box.rect.width * display.width,
                        height: box.rect.height * display.height
                    ).insetBy(dx: 0.5, dy: 0.5)
                    let color = clusterColor(cluster)
                    let selected = cluster.id == selectedClusterID
                    let width = selected ? lineWidth * 1.5 : lineWidth
                    let corner = min(4, rect.height / 4)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(color.opacity(selected ? 0.30 : 0.14))
                        // 外圈白边：在任何底色上把框「托」出来
                        .overlay(
                            RoundedRectangle(cornerRadius: corner + width, style: .continuous)
                                .stroke(Color.white.opacity(0.9), lineWidth: width)
                                .padding(-width)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .stroke(color, lineWidth: width)
                        )
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
                        .contentShape(Rectangle().inset(by: -4))
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
