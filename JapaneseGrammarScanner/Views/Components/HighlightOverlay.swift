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
    let onTap: (HighlightCluster) -> Void

    var body: some View {
        GeometryReader { geo in
            let display = fit.displayedRect(imageSize: imageSize, in: geo.size)
            let clustersByID = Dictionary(uniqueKeysWithValues: result.clusters.map { ($0.id, $0) })
            ForEach(result.boxes) { box in
                if let cluster = clustersByID[box.clusterID] {
                    let rect = CGRect(
                        x: display.minX + box.rect.minX * display.width,
                        y: display.minY + box.rect.minY * display.height,
                        width: box.rect.width * display.width,
                        height: box.rect.height * display.height
                    ).insetBy(dx: -2, dy: -2)
                    let color = clusterColor(cluster)
                    let selected = cluster.id == selectedClusterID
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(selected ? 0.55 : 0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(color, lineWidth: selected ? 3 : 1.5)
                        )
                        .overlay(alignment: .topTrailing) {
                            if cluster.grammarIDs.count > 1 {
                                Text(verbatim: "\(cluster.grammarIDs.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(color, in: Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                        .frame(width: max(rect.width, 8), height: max(rect.height, 8))
                        .contentShape(Rectangle().inset(by: -6))
                        .position(x: rect.midX, y: rect.midY)
                        .onTapGesture { onTap(cluster) }
                        .accessibilityElement()
                        .accessibilityLabel(cluster.grammarIDs.compactMap { library.point(id: $0)?.title }.joined(separator: "、"))
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
