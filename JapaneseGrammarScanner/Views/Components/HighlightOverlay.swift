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
    /// 线宽：放大查看时用更细的线
    var lineWidth: CGFloat = 1.2
    var showsCountBadge = true
    let onTap: (HighlightCluster) -> Void

    var body: some View {
        GeometryReader { geo in
            let display = fit.displayedRect(imageSize: imageSize, in: geo.size)
            let clustersByID = Dictionary(uniqueKeysWithValues: result.clusters.map { ($0.id, $0) })
            ForEach(result.boxes) { box in
                if let cluster = clustersByID[box.clusterID] {
                    // 识别框略向内收，避免相邻框互相重叠；细虚线 + 极淡底色，不遮挡原文
                    let rect = CGRect(
                        x: display.minX + box.rect.minX * display.width,
                        y: display.minY + box.rect.minY * display.height,
                        width: box.rect.width * display.width,
                        height: box.rect.height * display.height
                    ).insetBy(dx: 0.5, dy: 0.5)
                    let color = clusterColor(cluster)
                    let selected = cluster.id == selectedClusterID
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(selected ? 0.28 : 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(color, style: StrokeStyle(lineWidth: selected ? 2 : lineWidth, dash: selected ? [] : [3, 2]))
                        )
                        .overlay(alignment: .topTrailing) {
                            if cluster.grammarIDs.count > 1 && showsCountBadge {
                                Text(verbatim: "\(cluster.grammarIDs.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 12, height: 12)
                                    .background(color, in: Circle())
                                    .offset(x: 5, y: -5)
                            }
                        }
                        .frame(width: max(rect.width, 4), height: max(rect.height, 4))
                        .contentShape(Rectangle().inset(by: -4))
                        .position(x: rect.midX, y: rect.midY)
                        .onTapGesture { onTap(cluster) }
                        .accessibilityElement()
                        .accessibilityLabel(cluster.grammarIDs.compactMap { library.point(id: $0)?.displayTitle }.joined(separator: "、"))
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    private func clusterColor(_ cluster: HighlightCluster) -> Color {
        // 一个高亮块包含多个语法点时，用其中最难的等级上色
        let levels = cluster.grammarIDs.compactMap { library.point(id: $0)?.level }
        return (levels.max() ?? .n5).color
    }
}
