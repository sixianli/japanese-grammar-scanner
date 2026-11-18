import SwiftUI

/// 简单的流式布局：子视图从左到右排列，放不下就换行；同一行底部对齐。
/// 用于逐字/逐词排版带假名注音的文本（SwiftUI 的 Text 不支持 ruby）。
struct FlowLayout: Layout {
    var lineSpacing: CGFloat = 4

    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = arrange(maxWidth: maxWidth, subviews: subviews, sizes: cache.sizes)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + CGFloat(max(lines.count - 1, 0)) * lineSpacing
        // 只占内容实际宽度（不把整行撑满），这样标题后面的等级标签能紧贴在文字右上角
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let lines = arrange(maxWidth: bounds.width, subviews: subviews, sizes: cache.sizes)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for index in line.indices {
                let size = cache.sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + line.height - size.height),
                    proposal: ProposedViewSize(size)
                )
                x += size.width
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews, sizes: [CGSize]) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for (i, subview) in subviews.enumerated() {
            if subview[LineBreakKey.self] {
                lines.append(current)
                current = Line()
                continue
            }
            let size = sizes[i]
            if current.width + size.width > maxWidth, !current.indices.isEmpty {
                lines.append(current)
                current = Line()
            }
            current.indices.append(i)
            current.width += size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty || lines.isEmpty { lines.append(current) }
        return lines
    }
}

/// 标记一个强制换行的占位子视图。
struct LineBreakKey: LayoutValueKey {
    static let defaultValue = false
}
