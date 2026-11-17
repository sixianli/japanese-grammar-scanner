import SwiftUI

/// 把识别出的文本渲染出来，其中的语法点用背景色高亮，并可点击。
struct HighlightedText: View {
    let result: ScanResult
    let library: GrammarLibrary
    var selectedClusterID: Int? = nil
    let onTap: (HighlightCluster) -> Void

    var body: some View {
        Text(attributed)
            .font(.system(.title3))
            .lineSpacing(8)
            .tint(.primary)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "grammarcluster",
                      let id = Int(url.host ?? ""),
                      let cluster = result.clusters.first(where: { $0.id == id }) else { return .systemAction }
                onTap(cluster)
                return .handled
            })
    }

    private var attributed: AttributedString {
        let ns = result.text as NSString
        var output = AttributedString()
        var cursor = 0
        for cluster in result.clusters.sorted(by: { $0.range.location < $1.range.location }) {
            if cluster.range.location > cursor {
                output += AttributedString(ns.substring(with: NSRange(location: cursor, length: cluster.range.location - cursor)))
            }
            var piece = AttributedString(ns.substring(with: cluster.range))
            let levels = cluster.grammarIDs.compactMap { library.point(id: $0)?.level }
            let color = (levels.max() ?? .n5).color
            piece.backgroundColor = (color as Color).opacity(cluster.id == selectedClusterID ? 0.5 : 0.25)
            piece.foregroundColor = Color.primary
            piece.link = URL(string: "grammarcluster://\(cluster.id)")
            output += piece
            cursor = NSMaxRange(cluster.range)
        }
        if cursor < ns.length {
            output += AttributedString(ns.substring(from: cursor))
        }
        return output
    }
}
